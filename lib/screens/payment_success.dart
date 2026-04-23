import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:api_selfxo_project/background_image/background_image.dart';
import 'package:api_selfxo_project/core/kiosk_config.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';
import 'package:api_selfxo_project/printer/printer_s.dart';
import 'package:api_selfxo_project/api/kiosk_api.dart';

enum PrinterStatus { printing, success, error }

class PaymentSuccessDialog extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final int orderNumber;
  final String language;
  final String? restaurantName;
  final String? transactionId;
  final DateTime? orderDate;
  final String? orderType;
  final bool autoPrint;
  final String? debugSource;

  const PaymentSuccessDialog({
    super.key,
    required this.cart,
    required this.orderNumber,
    this.language = "en",
    this.restaurantName,
    this.transactionId,
    this.orderDate,
    this.orderType,
    this.autoPrint = true,
    this.debugSource,
  });

  static Future<void> printReceiptUsingTabletFlow({
    required List<Map<String, dynamic>> cart,
    required int orderNumber,
    String? restaurantName,
    String? transactionId,
    DateTime? orderDate,
    String? orderType,
  }) async {
    String? resolvedRestaurantName = restaurantName;
    final prefs = await SharedPreferences.getInstance();
    if (resolvedRestaurantName == null ||
        resolvedRestaurantName.trim().isEmpty) {
      resolvedRestaurantName = prefs.getString("restaurant_name");
    }
    resolvedRestaurantName ??= "OUR KITCHEN";
    final taxId = prefs.getString("gst_number") ?? prefs.getString("tax_id");

    String? resolvedTransactionId = transactionId;
    DateTime? resolvedOrderDate = orderDate;
    var printItems = cart;
    String? resolvedPaymentMode = "PAID";
    num? taxAmount;
    num? discountAmount;
    if (resolvedTransactionId == null || resolvedOrderDate == null) {
      try {
        final res = await KioskApi().getOrderDetails(orderNumber);
        final raw = res.data;
        final backendItems = _extractOrderItemsFromPayload(raw);
        if (backendItems.isNotEmpty) {
          printItems = backendItems;
        }
        resolvedTransactionId ??= _findTxnIdInPayload(raw);
        resolvedOrderDate ??= _parseOrderDateFromPayload(raw);
        resolvedPaymentMode = _findStringInPayload(raw, const [
              "payment_mode",
              "paymentMode",
              "payment_method",
              "paymentMethod",
            ]) ??
            resolvedPaymentMode;
        taxAmount = _findNumInPayload(raw, const [
          "tax",
          "tax_amount",
          "gst",
          "total_tax",
        ]);
        discountAmount = _findNumInPayload(raw, const [
          "discount",
          "discount_amount",
        ]);
      } catch (_) {}
    }

    await PrinterService().printOrder(
      orderId: orderNumber,
      cartItems: printItems,
      restaurantName: resolvedRestaurantName,
      taxId: taxId,
      paymentMode: resolvedPaymentMode,
      transactionId: resolvedTransactionId,
      orderDate: resolvedOrderDate,
      taxAmount: taxAmount,
      discountAmount: discountAmount,
      orderType: orderType,
      forceLocal: true,
      removeTaxLines: true,
    );
  }

  static List<Map<String, dynamic>> _extractOrderItemsFromPayload(
    dynamic data,
  ) {
    List<dynamic> raw = [];
    if (data is Map) {
      final candidates = [
        data["order_items"],
        data["items"],
        data["orderItems"],
        data["order_item_list"],
        data["orderItemList"],
        data["orderDetails"],
        data["order_details"],
        data["order"] is Map ? data["order"]["order_items"] : null,
        data["data"] is Map ? data["data"]["order_items"] : null,
        data["data"] is Map ? data["data"]["items"] : null,
        data["data"] is Map && data["data"]["order"] is Map
            ? data["data"]["order"]["order_items"]
            : null,
      ];
      for (final c in candidates) {
        if (c is List) {
          raw = c;
          break;
        }
        if (c is Map && c["data"] is List) {
          raw = c["data"];
          break;
        }
      }
    }
    raw = raw.isNotEmpty ? raw : (_findItemsList(data) ?? const []);

    return raw.whereType<Map>().map((item) {
      final menuItem = item["menu_item"] is Map
          ? item["menu_item"] as Map
          : item["menuItem"] is Map
              ? item["menuItem"] as Map
              : item["item"] is Map
                  ? item["item"] as Map
                  : item["product"] is Map
                      ? item["product"] as Map
                      : const {};
      final pivot = item["pivot"] is Map ? item["pivot"] as Map : const {};
      final qty = _asNum(
        item["qty"] ??
            item["quantity"] ??
            item["count"] ??
            pivot["quantity"] ??
            1,
      );
      final safeQty = qty <= 0 ? 1 : qty;
      var price = _asNum(
        item["price"] ??
            item["unit_price"] ??
            item["unitPrice"] ??
            item["item_price"] ??
            item["rate"] ??
            pivot["price"] ??
            menuItem["price"] ??
            0,
      );
      final amount = _asNum(
        item["amount"] ??
            item["total"] ??
            item["total_amount"] ??
            item["totalAmount"] ??
            item["total_price"] ??
            item["totalPrice"] ??
            item["line_total"] ??
            item["lineTotal"],
      );
      if (price <= 0 && amount > 0) {
        price = amount / safeQty;
      }

      final name = _firstNonEmpty([
        item["item_name"],
        item["name"],
        item["title"],
        item["menu_item_name"],
        item["menuItemName"],
        item["product_name"],
        item["productName"],
        menuItem["item_name"],
        menuItem["name"],
        menuItem["title"],
        menuItem["product_name"],
      ], fallback: "Item");
      final category = _firstNonEmpty([
        item["category_name"],
        item["category"],
        menuItem["category_name"],
        menuItem["category"],
      ], fallback: "Items");
      final image = item["item_photo_url"] ??
          item["image_url"] ??
          item["image"] ??
          menuItem["item_photo_url"] ??
          menuItem["image_url"] ??
          menuItem["image"];
      return {
        "qty": safeQty,
        "price": price,
        "amount": amount > 0 ? amount : price * safeQty,
        "name": name,
        "category": category,
        "image": image?.toString(),
      };
    }).toList();
  }

  static List<dynamic>? _findItemsList(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        final v = entry.value;
        if (v is List &&
            (key.contains("item") ||
                key.contains("detail") ||
                key.contains("order"))) {
          return v;
        }
        final nested = _findItemsList(v);
        if (nested != null) return nested;
      }
    } else if (value is List) {
      for (final item in value) {
        final nested = _findItemsList(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static String? _findTxnIdInPayload(dynamic value) {
    const keys = [
      "transaction_id",
      "payment_id",
      "txn_id",
      "transactionId",
      "paymentId",
      "razorpay_payment_id",
      "payment_reference",
      "payment_txn_id",
      "txnid",
      "txnId",
    ];

    if (value is Map) {
      for (final k in keys) {
        if (value.containsKey(k) && value[k] != null) {
          final v = value[k].toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
      for (final entry in value.entries) {
        final found = _findTxnIdInPayload(entry.value);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final item in value) {
        final found = _findTxnIdInPayload(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String? _findStringInPayload(dynamic value, List<String> keys) {
    if (value is Map) {
      for (final k in keys) {
        final v = value[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      for (final entry in value.entries) {
        final found = _findStringInPayload(entry.value, keys);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final item in value) {
        final found = _findStringInPayload(item, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static num? _findNumInPayload(dynamic value, List<String> keys) {
    if (value is Map) {
      for (final k in keys) {
        final v = value[k];
        if (v is num) return v;
        final parsed = num.tryParse(v?.toString() ?? "");
        if (parsed != null) return parsed;
      }
      for (final entry in value.entries) {
        final found = _findNumInPayload(entry.value, keys);
        if (found != null) return found;
      }
    } else if (value is List) {
      for (final item in value) {
        final found = _findNumInPayload(item, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static num _asNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? "") ?? 0;
  }

  static String _firstNonEmpty(
    List<dynamic> values, {
    required String fallback,
  }) {
    for (final value in values) {
      final text = value?.toString().trim() ?? "";
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static DateTime? _parseOrderDateFromPayload(dynamic value) {
    final keys = [
      "created_at",
      "order_date",
      "date",
      "createdAt",
      "placed_at",
      "order_time",
    ];
    if (value is Map) {
      for (final k in keys) {
        final parsed = _parseDateValueFromPayload(value[k]);
        if (parsed != null) return parsed;
      }
      for (final entry in value.entries) {
        final parsed = _parseOrderDateFromPayload(entry.value);
        if (parsed != null) return parsed;
      }
    } else if (value is List) {
      for (final item in value) {
        final parsed = _parseOrderDateFromPayload(item);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static DateTime? _parseDateValueFromPayload(dynamic v) {
    if (v == null) return null;
    try {
      if (v is int) {
        return v > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(v)
            : DateTime.fromMillisecondsSinceEpoch(v * 1000);
      }
      if (v is num) {
        final i = v.toInt();
        return i > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(i)
            : DateTime.fromMillisecondsSinceEpoch(i * 1000);
      }
      if (v is String && v.trim().isNotEmpty) {
        return DateTime.tryParse(v.trim());
      }
    } catch (_) {}
    return null;
  }

  @override
  State<PaymentSuccessDialog> createState() => _PaymentSuccessDialogState();
}

class _PaymentSuccessDialogState extends State<PaymentSuccessDialog>
    with TickerProviderStateMixin {
  static const Color kPrimary = Color(0xFF00C853);
  static const Color kBackground = Color(0xFFF1F5F9);
  static const Color kAccent = Color(0xFF00BFA5);

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _receiptController;
  late AnimationController _vibrateController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final bool _enableSuccessAnimations = KioskConfig.enableSuccessAnimations;

  Timer? autoCloseTimer;
  Timer? _pulseStopTimer;
  int _countdownSeconds = 3;
  bool isPrinting = false;
  bool _blockUi = false;
  VoidCallback? _maintenanceListener;

  PrinterStatus? printerStatus;
  String? printerStatusMessage;
  String _printStatusText = "Preparing...";
  String _restaurantName = "OUR KITCHEN";

  static const MethodChannel _usbEvents = MethodChannel(
    'com.whimsicaldev/usb_events',
  );

  int get totalAmount => widget.cart.fold(
        0,
        (sum, item) => sum + _asInt(item["price"]) * _asInt(item["qty"]),
      );

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: _enableSuccessAnimations
          ? const Duration(milliseconds: 600)
          : const Duration(milliseconds: 1),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _receiptController = AnimationController(
      vsync: this,
      duration: _enableSuccessAnimations
          ? const Duration(milliseconds: 2000)
          : const Duration(milliseconds: 1),
    );
    _vibrateController = AnimationController(
      vsync: this,
      duration: _enableSuccessAnimations
          ? const Duration(milliseconds: 50)
          : const Duration(milliseconds: 1),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: _enableSuccessAnimations
          ? const Duration(milliseconds: 1800)
          : const Duration(milliseconds: 1),
    );
    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (_enableSuccessAnimations) {
      _animationController.forward();
      _pulseController.repeat(reverse: true);
      _pulseStopTimer?.cancel();
      _pulseStopTimer = Timer(const Duration(seconds: 3), () {
        if (_pulseController.isAnimating) {
          _pulseController.stop(canceled: true);
        }
      });
    } else {
      _animationController.value = 1;
    }

    _loadRestaurantName();

    _maintenanceListener = _handleMaintenanceTick;
    KioskMemoryService.instance.maintenanceTick.addListener(
      _maintenanceListener!,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.autoPrint) {
        _handlePrintingProcess();
      } else {
        setState(() {
          printerStatus = PrinterStatus.success;
          printerStatusMessage = "Print successful";
          _printStatusText = "Print successful";
        });
        _startAutoCloseTimer(seconds: 3);
      }
    });

    _usbEvents.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'onPrinterPrintStatus') {
        final status = call.arguments?['status']?.toString() ?? '';
        final message = call.arguments?['message']?.toString() ?? '';
        _handlePrintStatus(status, message);
      }
    });
  }

  // ================= PRINT =================
  Future<void> _handlePrintingProcess() async {
    if (isPrinting) return;

    // Stop auto-close timer if reprinting
    autoCloseTimer?.cancel();
    bool hadError = false;

    setState(() {
      isPrinting = true;
      _blockUi = true;
      printerStatus = PrinterStatus.printing;
      printerStatusMessage = "Printing receipt...";
      _printStatusText = "Printing your receipt...";
      _countdownSeconds = 3; // Reset countdown
    });

    if (_enableSuccessAnimations) {
      _receiptController.forward(from: 0);
      _vibrateController.repeat(reverse: true);
    } else {
      _receiptController.value = 1;
    }

    try {
      await PaymentSuccessDialog.printReceiptUsingTabletFlow(
        cart: widget.cart,
        orderNumber: widget.orderNumber,
        restaurantName: widget.restaurantName,
        transactionId: widget.transactionId,
        orderDate: widget.orderDate,
        orderType: widget.orderType,
      );

      if (!mounted) return;
      setState(() {
        printerStatus = PrinterStatus.success;
        printerStatusMessage = "Printer Ready";
        _printStatusText = "Print successful";
      });
    } on DioException catch (e) {
      if (!mounted) return;
      hadError = true;
      setState(() {
        printerStatus = PrinterStatus.error;
        printerStatusMessage = kDebugMode
            ? (e.response?.data?.toString() ?? e.message ?? "Backend error")
            : "Printer error. Contact staff.";
        _printStatusText = printerStatusMessage ?? "Printer error";
      });
    } catch (e) {
      if (!mounted) return;
      hadError = true;
      setState(() {
        printerStatus = PrinterStatus.error;
        printerStatusMessage = kDebugMode ? e.toString() : "Printer error.";
        _printStatusText = printerStatusMessage ?? "Printer error";
      });
    } finally {
      if (mounted) {
        _vibrateController.stop();
        setState(() {
          isPrinting = false;
          _blockUi = false;
        });
        if (printerStatus == PrinterStatus.success ||
            printerStatus == PrinterStatus.error) {
          _startAutoCloseTimer(seconds: 3);
        }
      }
    }
  }

  List<String> _counterFooterLines(List<Map<String, dynamic>> items) {
    String category = "";
    for (final item in items) {
      final c = item["category"]?.toString().trim() ?? "";
      if (c.isNotEmpty) {
        category = c.toUpperCase();
        break;
      }
    }
    if (category.isEmpty) {
      category = "CATEGORY";
    }
    return [category, "COUNTER"];
  }

  // ================= AUTO CLOSE =================
  void _startAutoCloseTimer({int seconds = 3}) {
    autoCloseTimer?.cancel();
    _countdownSeconds = seconds;
    autoCloseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds <= 0) {
        timer.cancel();
        _navigateToWelcome();
      } else {
        setState(() => _countdownSeconds--);
      }
    });
  }

  void _navigateToWelcome() {
    _scheduleImageCacheClear();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  void _scheduleImageCacheClear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  @override
  void dispose() {
    autoCloseTimer?.cancel();
    _pulseStopTimer?.cancel();
    if (_animationController.isAnimating) {
      _animationController.stop(canceled: true);
    }
    if (_receiptController.isAnimating) {
      _receiptController.stop(canceled: true);
    }
    if (_vibrateController.isAnimating) {
      _vibrateController.stop(canceled: true);
    }
    if (_pulseController.isAnimating) {
      _pulseController.stop(canceled: true);
    }
    _animationController.dispose();
    _receiptController.dispose();
    _vibrateController.dispose();
    _pulseController.dispose();
    _usbEvents.setMethodCallHandler(null);
    if (_maintenanceListener != null) {
      KioskMemoryService.instance.maintenanceTick.removeListener(
        _maintenanceListener!,
      );
    }
    super.dispose();
  }

  void _handleMaintenanceTick() {
    if (!mounted) return;
    if (_pulseController.isAnimating) {
      _pulseController.reset();
      _pulseController.repeat(reverse: true);
    }
    if (_vibrateController.isAnimating) {
      _vibrateController.reset();
      _vibrateController.repeat(reverse: true);
    }
  }

  Future<void> _loadRestaurantName() async {
    String? name = widget.restaurantName;
    if (name == null || name.trim().isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString("restaurant_name");
    }
    if (!mounted) return;
    setState(() {
      _restaurantName = (name == null || name.trim().isEmpty)
          ? _restaurantName
          : name!.trim();
    });
  }

  // ================= UI COMPONENTS =================
  @override
  Widget build(BuildContext context) {
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        toolbarHeight: isTablet ? 100 : 80,
        backgroundColor: const Color(0xFF5BCB73),
        elevation: 0,
        centerTitle: true,
        leadingWidth: 140,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image.asset(
              "assets/self.png",
              height: 36,
              fit: BoxFit.contain,
            ),
          ),
        ),
        title: Text(
          _restaurantName,
          style: const TextStyle(
            color: Color.fromARGB(221, 255, 255, 255),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildBackground(),
          Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: _buildMainCard(),
                ),
              ),
            ),
          ),
          if (_blockUi) _printingOverlay(),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5BCB73), Color(0xFF4DBA63), Color(0xFF43B05A)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _glowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildPrinterSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_enableSuccessAnimations)
          AnimatedBuilder(
            animation: _vibrateController,
            builder: (_, child) {
              final offset = isPrinting ? (Random().nextDouble() * 2 - 1) : 0.0;
              return Transform.translate(
                offset: Offset(offset, 0),
                child: child,
              );
            },
            child: Container(
              width: 240,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
              ),
            ),
          )
        else
          Container(
            width: 240,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
          ),
        const SizedBox(height: 6),
        if (_enableSuccessAnimations)
          ClipRect(
            child: AnimatedBuilder(
              animation: _receiptController,
              builder: (_, child) => Align(
                alignment: Alignment.topCenter,
                heightFactor: _receiptController.value,
                child: child,
              ),
              child: _buildPhysicalReceipt(),
            ),
          )
        else
          _buildPhysicalReceipt(),
      ],
    );
  }

  Widget _buildPhysicalReceipt() {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "RECEIPT",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          ...widget.cart.take(3).map(
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          "${i["qty"]}x ${i["name"]}",
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        "₹${i["price"] * i["qty"]}",
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TOTAL",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                "₹$totalAmount",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text("*** THANK YOU ***", style: TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  Widget _buildMainCard() {
    return SizedBox(
      width: 520,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 24, 36, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.check, size: 46, color: kPrimary),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Payment Successful!",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Your Receipt Is Printing. Kindly Do Not Pull Until Fully Printed.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Please show this receipt at the counter to get your order.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 20),
            const Text(
              "AMOUNT PAID",
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.4,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "₹$totalAmount",
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            _buildPrinterSection(),
            if (printerStatus == PrinterStatus.error) ...[
              const SizedBox(height: 8),
              Text(
                printerStatusMessage ?? "Printer error",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if ((widget.debugSource?.trim().isNotEmpty ?? false) ||
                printerStatusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  [
                    if (widget.debugSource?.trim().isNotEmpty ?? false)
                      widget.debugSource!.trim(),
                    if (printerStatusMessage != null)
                      'printerStatus=$printerStatusMessage',
                    'printText=$_printStatusText',
                  ].join('\n'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.35,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kPrimary.withOpacity(0.12), kPrimary.withOpacity(0.04)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kPrimary.withOpacity(0.25)),
            ),
            child: const Text(
              "SUCCESS",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: kPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _restaurantName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 16),
          if (_enableSuccessAnimations)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (_, __) => Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kPrimary.withOpacity(0.12),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: kPrimary,
                    size: 74,
                  ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPrimary.withOpacity(0.12),
              ),
              child: const Icon(
                Icons.check_circle,
                color: kPrimary,
                size: 74,
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            "Payment Successful",
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          Text(
            "Order #${widget.orderNumber}",
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "₹$totalAmount",
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.bold,
              color: kPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Total Amount",
            style: TextStyle(color: Colors.blueGrey, fontSize: 14),
          ),
          const SizedBox(height: 14),
          _printerStatusChip(),
        ],
      ),
    );
  }

  Widget _printerStatusChip() {
    if (printerStatus == PrinterStatus.success) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: kPrimary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kPrimary.withOpacity(0.2)),
        ),
        child: const Text(
          "Print successful",
          style: TextStyle(
            color: kPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      );
    }
    String text;
    Color color;
    switch (printerStatus) {
      case PrinterStatus.printing:
        text = "Printing...";
        color = Colors.blue;
        break;
      case PrinterStatus.error:
        text = "Print Failed";
        color = Colors.red;
        break;
      default:
        text = "Ready";
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildOrderDetails() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kPrimary.withOpacity(0.08)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: ListView(
          shrinkWrap: true,
          children: widget.cart
              .map(
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        "${i["qty"]}x ",
                        style: const TextStyle(
                          color: kPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          i["name"],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        "₹${i["price"] * i["qty"]}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        if (isPrinting)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(
              color: kPrimary,
              backgroundColor: Colors.transparent,
            ),
          ),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: isPrinting ? null : _handlePrintingProcess,
            icon: const Icon(Icons.print_outlined),
            label: Text(
              isPrinting ? "Printing..." : "Reprint Receipt",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _printingOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: Colors.black.withOpacity(0.55),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.print, color: Colors.white, size: 64),
                const SizedBox(height: 16),
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  _printStatusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handlePrintStatus(String status, String message) {
    switch (status) {
      case "PRINT_STARTED":
      case "PRINTING":
        setState(() {
          isPrinting = true;
          _blockUi = true;
          printerStatus = PrinterStatus.printing;
          printerStatusMessage = "Printing receipt...";
          _printStatusText =
              message.isNotEmpty ? message : "Printing your receipt...";
        });
        break;
      case "PRINT_SUCCESS":
        setState(() {
          isPrinting = false;
          _blockUi = false;
          printerStatus = PrinterStatus.success;
          printerStatusMessage = "Printer Ready";
          _printStatusText = "Print successful";
        });
        _startAutoCloseTimer(seconds: 3);
        break;
      case "PRINT_ERROR":
        setState(() {
          isPrinting = false;
          _blockUi = false;
          printerStatus = PrinterStatus.error;
          printerStatusMessage = "Print Failed";
          _printStatusText = message.isNotEmpty ? message : "Print failed";
        });
        _startAutoCloseTimer(seconds: 3);
        break;
      default:
        break;
    }
  }
}
