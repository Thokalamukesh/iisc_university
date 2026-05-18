import 'dart:async';

import 'package:api_selfxo_project/core/device_layout.dart';
import 'package:api_selfxo_project/screens/admin_dashboard_screens/adim_homescreen.dart';
import 'package:api_selfxo_project/screens/main_navigation.dart';
import 'package:api_selfxo_project/screens/pickup_qr_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/kiosk_api.dart';
import '../core/device_info.dart';
import '../core/idle_timer.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';

class PaymentScreen extends StatefulWidget {
  final int totalAmount;
  final List<Map<String, dynamic>> cart;
  final String orderType;

  const PaymentScreen({
    super.key,
    required this.totalAmount,
    required this.cart,
    required this.orderType,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with WidgetsBindingObserver {
  static const Color _brand = Color(0xFF9F342C);
  static const Color _canvas = Color(0xFFF6F1EA);
  static const int _failAutoCloseSeconds = 3;

  int _remainingSeconds = 250;
  int _failSeconds = _failAutoCloseSeconds;
  double _failProgress = 1.0;
  double _failProgressTarget = 1.0;

  Timer? _countdownTimer;
  Timer? _paymentTimer;
  Timer? _timeoutTimer;
  Timer? _paymentFailTimer;

  bool _loading = true;
  bool _started = false;
  bool _active = true;
  bool _receiptPrinted = false;
  bool _waitingForPaymentCompletion = false;
  String _selectedPaymentLabel = "UPI";

  String? _errorMessage;
  int? _orderId;
  String? _qrData;
  double? _payableAmount;
  String _displayRestaurantName = "OUR KITCHEN";

  @override
  void initState() {
    super.initState();
    IdleTimer.pause();
    KioskMemoryService.instance.pause();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadRestaurantData();
      _startPaymentFlow();
      _startTimeout();
    });
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  Widget _homeDestination() {
    if (isTabletContext(context)) {
      return const AdminHomeScreen();
    }
    final safeOrderType =
        widget.orderType.trim().isEmpty ? 'dine_in' : widget.orderType;
    return MainNavigation(orderType: safeOrderType);
  }

  // --- POPUP DIALOG LOGIC ---
  void _showCancelConfirmation({required bool isStartAgain}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0EB),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    isStartAgain
                        ? Icons.refresh_rounded
                        : Icons.cancel_presentation_rounded,
                    color: _brand,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  isStartAgain ? "Start again?" : "Cancel payment?",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1D1D1D),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isStartAgain
                      ? "Your current order progress will be cleared."
                      : "This payment session will be closed and the order will be cancelled.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text("Stay"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (_) => _homeDestination()),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: _brand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          "Confirm",
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🔥 FETCH SAVED NAME
  Future<void> _preloadRestaurantData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString("restaurant_name")?.trim() ?? "";
      if (savedName.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _displayRestaurantName = savedName.toUpperCase();
        });
        return;
      }

      final res = await KioskApi().getRestaurantData();
      final restaurant = res.data["data"]?["restaurant"];
      final name = restaurant?["name"] ?? "OUR KITCHEN";

      await prefs.setString("restaurant_name", name);

      if (mounted) {
        setState(() {
          _displayRestaurantName = name.toUpperCase();
        });
      }
    } catch (e) {
      debugPrint("Failed to preload restaurant data: $e");
    }
  }

  Future<void> _startPaymentFlow() async {
    if (_started) return;
    _started = true;
    _startCountdown();

    try {
      final orderItems = widget.cart.map((item) {
        final basePrice = _asInt(item["price"]);
        final variation = item["variation"];
        final modifiers = (item["modifiers"] as List? ?? []);
        final finalUnitPrice = basePrice +
            _asInt(variation?["price"]) +
            modifiers.fold<int>(0, (sum, m) => sum + _asInt(m["price"]));

        return {
          "id": item["id"],
          "item_name": item["name"],
          "quantity": _asInt(item["qty"]),
          "price": finalUnitPrice,
          "itemPrice": finalUnitPrice,
          "item_photo_url": item["image"],
          "variation_id": variation?["id"],
          "variation_name": variation?["variation"],
          "has_modifiers": modifiers.isNotEmpty,
          "modifiers": modifiers
              .map((m) =>
                  {"id": m["id"], "name": m["name"], "price": m["price"]})
              .toList(),
        };
      }).toList();

      final createRes = await KioskApi().createOrder(
        orderType: widget.orderType,
        orderItems: orderItems,
      );

      _orderId = createRes.data["order"]?["id"];

      final prefs = await SharedPreferences.getInstance();
      final restaurantId = prefs.getString("restaurant_id");
      if (restaurantId != null && restaurantId.trim().isNotEmpty) {
        await DeviceInfoUtil.getDeviceId(restaurantId: restaurantId);
      }

      final qrRes = await KioskApi().generateQr(orderId: _orderId!);

      _qrData = _extractQrString(qrRes.data);

      final amountPaise = _extractAmountPaise(qrRes.data);
      _payableAmount = amountPaise != null
          ? amountPaise / 100
          : widget.totalAmount.toDouble();

      if (mounted) {
        setState(() {
          _loading = false;
          _waitingForPaymentCompletion = false;
        });
      }
      _startPaymentPolling();
    } catch (e) {
      _handleError(e.toString());
    }
  }

  String? _extractQrString(dynamic payload) {
    String? asString(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    dynamic readKey(Map map, List<String> keys) {
      for (final key in keys) {
        if (map.containsKey(key)) return map[key];
      }
      final wanted = keys.map((e) => e.toLowerCase()).toSet();
      for (final entry in map.entries) {
        final k = entry.key.toString().toLowerCase();
        if (wanted.contains(k)) return entry.value;
      }
      return null;
    }

    String? findIn(dynamic data, int depth) {
      if (data == null || depth <= 0) return null;
      if (data is String) return asString(data);
      if (data is Map) {
        final direct = readKey(data, const [
          "qrCode",
          "qr_code",
          "qr",
          "qrData",
          "qr_data",
          "upi_qr",
          "upiQr",
          "upi_string",
          "upiString",
          "payload",
        ]);
        final directStr = asString(direct);
        if (directStr != null) return directStr;

        for (final key in const [
          "data",
          "result",
          "response",
          "payload",
          "order",
          "qr_info",
        ]) {
          if (data.containsKey(key)) {
            final nested = findIn(data[key], depth - 1);
            if (nested != null) return nested;
          }
        }
      }
      return null;
    }

    return findIn(payload, 4);
  }

  num? _extractAmountPaise(dynamic payload) {
    num? asNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      return num.tryParse(v.toString());
    }

    num? findIn(dynamic data, int depth) {
      if (data == null || depth <= 0) return null;
      if (data is Map) {
        if (data.containsKey("amount")) {
          final val = asNum(data["amount"]);
          if (val != null) return val;
        }
        for (final key in const [
          "data",
          "result",
          "response",
          "payload",
          "order",
        ]) {
          if (data.containsKey(key)) {
            final nested = findIn(data[key], depth - 1);
            if (nested != null) return nested;
          }
        }
      }
      return null;
    }

    return findIn(payload, 4);
  }

  void _startPaymentPolling() {
    _paymentTimer?.cancel();
    _paymentTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_active || !mounted || _orderId == null) return;

      try {
        final res = await KioskApi().checkPayment(_orderId!);
        if (_isPaymentCompleted(res.data)) {
          _paymentTimer?.cancel();
          await _handlePaymentSuccess();
        }
      } catch (_) {}
    });
  }

  bool _isPaymentCompleted(dynamic data) {
    bool isPaidStatus(dynamic status) {
      if (status == true) return true;
      if (status is num) return status == 1;
      final s = status?.toString().trim().toLowerCase() ?? "";
      if (s.isEmpty) return false;
      if (s.contains("cancel") ||
          s.contains("refund") ||
          s.contains("failed") ||
          s.contains("void") ||
          s.contains("unpaid") ||
          s.contains("pending")) {
        return false;
      }
      return s.contains("paid") ||
          s.contains("completed") ||
          s.contains("success") ||
          s.contains("successful") ||
          s.contains("captured") ||
          s.contains("authorized");
    }

    bool findIn(dynamic value, int depth) {
      if (value == null || depth <= 0) return false;
      if (value is Map) {
        for (final key in const [
          "status",
          "payment_status",
          "paymentStatus",
          "order_status",
          "orderStatus",
          "state",
          "payment_state",
          "paymentState",
          "paid",
          "is_paid",
          "isPaid",
          "success",
          "is_success",
          "isSuccess",
          "result",
          "message",
        ]) {
          if (value.containsKey(key) && isPaidStatus(value[key])) {
            return true;
          }
        }
        for (final nestedKey in const [
          "data",
          "order",
          "payment",
          "response",
          "result",
          "payload",
        ]) {
          if (value.containsKey(nestedKey) &&
              findIn(value[nestedKey], depth - 1)) {
            return true;
          }
        }
        for (final entry in value.entries) {
          if (findIn(entry.value, depth - 1)) return true;
        }
      } else if (value is List) {
        for (final item in value) {
          if (findIn(item, depth - 1)) return true;
        }
      } else if (isPaidStatus(value)) {
        return true;
      }
      return false;
    }

    return findIn(data, 5);
  }

  Future<void> _handlePaymentSuccess() async {
    if (_receiptPrinted) return;
    _receiptPrinted = true;
    _countdownTimer?.cancel();
    _timeoutTimer?.cancel();
    _paymentFailTimer?.cancel();

    if (!_active || !mounted) return;
    setState(() {
      _waitingForPaymentCompletion = false;
    });

    bool alreadyPrinted = false;
    try {
      final orderId = _orderId;
      if (orderId != null) {
        final details = await KioskApi().getOrderDetails(orderId);
        alreadyPrinted = _hasPrintedMarker(details.data, 7);
      }
    } catch (_) {}

    if (!_active || !mounted) return;
    if (alreadyPrinted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PickupQrScreen(
            cart: widget.cart,
            orderId: _orderId!,
            restaurantName: _displayRestaurantName,
            orderType: widget.orderType,
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PickupQrScreen(
          cart: widget.cart,
          orderId: _orderId!,
          restaurantName: _displayRestaurantName,
          orderType: widget.orderType,
        ),
      ),
    );
  }

  bool _hasPrintedMarker(dynamic value, int depth) {
    if (value == null || depth <= 0) return false;

    bool looksPrinted(dynamic raw) {
      if (raw == true) return true;
      if (raw is num) return raw > 0;
      final s = raw?.toString().trim().toLowerCase() ?? '';
      if (s.isEmpty) return false;
      return s.contains('printed') ||
          s.contains('print_success') ||
          s.contains('receipt_printed') ||
          s.contains('served') ||
          s.contains('picked') ||
          s.contains('fulfilled') ||
          s.contains('completed');
    }

    if (value is Map) {
      for (final key in const [
        'is_printed',
        'printed',
        'print_status',
        'printStatus',
        'receipt_printed',
        'receiptPrinted',
        'printed_at',
        'printedAt',
        'print_count',
        'printCount',
        'status',
        'order_status',
        'orderStatus',
        'pickup_status',
        'pickupStatus',
      ]) {
        if (value.containsKey(key) && looksPrinted(value[key])) {
          return true;
        }
      }
      for (final nestedKey in const [
        'data',
        'order',
        'details',
        'order_details',
        'orderDetails',
        'payload',
        'result',
      ]) {
        if (value.containsKey(nestedKey) &&
            _hasPrintedMarker(value[nestedKey], depth - 1)) {
          return true;
        }
      }
      for (final entry in value.entries) {
        if (_hasPrintedMarker(entry.value, depth - 1)) return true;
      }
    } else if (value is List) {
      for (final item in value) {
        if (_hasPrintedMarker(item, depth - 1)) return true;
      }
    }

    return false;
  }

  void _handleError(String msg) {
    _paymentTimer?.cancel();
    _countdownTimer?.cancel();
    _paymentFailTimer?.cancel();
    if (!mounted || !_active || _receiptPrinted) return;
    setState(() {
      _loading = false;
      _errorMessage = msg;
      _waitingForPaymentCompletion = false;
    });
    _startFailAutoClose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_active || !mounted) return;
      if (_remainingSeconds <= 0) {
        timer.cancel();
        if (_errorMessage == null && !_receiptPrinted) {
          _handleError("Payment timed out");
        }
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(Duration(seconds: _remainingSeconds), () {
      if (!_active || !mounted || _receiptPrinted) return;
      _handleError("Payment timed out");
    });
  }

  void _startFailAutoClose() {
    _paymentFailTimer?.cancel();
    _failSeconds = _failAutoCloseSeconds;
    _failProgress = 1.0;
    _failProgressTarget = 1.0;
    _paymentFailTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_active || !mounted) {
        timer.cancel();
        return;
      }
      if (_failSeconds <= 1) {
        timer.cancel();
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => _homeDestination()),
          (route) => false,
        );
      } else {
        setState(() {
          _failSeconds--;
          _failProgressTarget = _failSeconds / _failAutoCloseSeconds;
        });
      }
    });
  }

  Future<void> _handlePayNow([String app = "generic"]) async {
    final upiValue = _resolveUpiPaymentLink();
    if (upiValue == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Payment link is not ready yet. Please wait a moment and try again.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _waitingForPaymentCompletion = true;
        _selectedPaymentLabel = _getAppDisplayName(app);
      });
    }

    final launched = _launchPreferredUpiTarget(upiValue, app);
    if (launched) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            app == "generic"
                ? "Complete payment in your UPI app. After payment, the scan-to-print screen will open automatically."
                : "Complete payment in $_selectedPaymentLabel. After payment, the scan-to-print screen will open automatically.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _waitingForPaymentCompletion = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Unable to open a UPI app on this device. Please try another UPI app.",
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _resolveUpiPaymentLink() {
    final raw = _qrData?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith("upi://pay")) {
      return raw;
    }
    return null;
  }

  bool _launchPreferredUpiTarget(String upiValue, String app) {
    final targets = _preferredLaunchTargets(upiValue, app);
    for (final target in targets) {
      if (_launchUpiInMobile(target)) {
        return true;
      }
    }
    return false;
  }

  bool _launchUpiInMobile(String target) {
    try {
      launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
      return true;
    } catch (_) {
      return false;
    }
  }

  List<String> _preferredLaunchTargets(String upiValue, String app) {
    final uri = Uri.parse(upiValue);
    final query = uri.hasQuery ? '?${uri.query}' : '';
    switch (app) {
      case "googlePay":
        return [
          'tez://upi/pay$query',
          'gpay://upi/pay$query',
          'intent://upi/pay$query#Intent;scheme=tez;package=com.google.android.apps.nbu.paisa.user;end',
        ];
      case "phonePe":
        return [
          'phonepe://pay$query',
          'intent://pay$query#Intent;scheme=phonepe;package=com.phonepe.app;end',
        ];
      case "paytm":
        return [
          'paytmmp://pay$query',
          'intent://pay$query#Intent;scheme=paytmmp;package=net.one97.paytm;end',
        ];
      default:
        return [upiValue];
    }
  }

  String _getAppDisplayName(String app) {
    switch (app) {
      case "googlePay":
        return "Google Pay";
      case "phonePe":
        return "PhonePe";
      case "paytm":
        return "Paytm";
      default:
        return "UPI";
    }
  }

  @override
  void dispose() {
    _active = false;
    WidgetsBinding.instance.removeObserver(this);
    _paymentTimer?.cancel();
    _timeoutTimer?.cancel();
    _countdownTimer?.cancel();
    _paymentFailTimer?.cancel();
    IdleTimer.resume();
    KioskMemoryService.instance.resume();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amountLabel =
        "₹${(_payableAmount ?? widget.totalAmount.toDouble()).toStringAsFixed(2)}";

    return Scaffold(
      backgroundColor: _canvas,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF8F2EA),
                    Color(0xFFF0E7DC),
                    Color(0xFFEDE6DE)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD97C59).withOpacity(0.12),
              ),
            ),
          ),
          Positioned(
            top: 180,
            left: -90,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB1493C).withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -50,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC7B39E).withOpacity(0.18),
              ),
            ),
          ),
          SafeArea(
            child: _loading
                ? _MobilePaymentLoading(
                    onCancel: () => _showCancelConfirmation(isStartAgain: true),
                  )
                : _MobilePaymentLayout(
                    remainingSeconds: _remainingSeconds,
                    restaurantName: _displayRestaurantName,
                    amountLabel: amountLabel,
                    viewportHeight: MediaQuery.sizeOf(context).height,
                    paymentQrData: _qrData,
                    paymentHint: _waitingForPaymentCompletion
                        ? "Complete payment in $_selectedPaymentLabel. After payment, the scan-to-print screen will open automatically."
                        : "Choose your payment app below to pay securely.",
                    onGooglePay: () => _handlePayNow("googlePay"),
                    onPhonePe: () => _handlePayNow("phonePe"),
                    onPaytm: () => _handlePayNow("paytm"),
                    onOtherUpi: () => _handlePayNow("generic"),
                    onCancel: () =>
                        _showCancelConfirmation(isStartAgain: false),
                    onStartAgain: () =>
                        _showCancelConfirmation(isStartAgain: true),
                  ),
          ),
          if (_errorMessage != null)
            _MobilePaymentErrorOverlay(
              message: _errorMessage!,
              seconds: _failSeconds,
              progress: _failProgress,
              targetProgress: _failProgressTarget,
              onProgressEnd: () {
                if (!mounted) return;
                if (_failProgress != _failProgressTarget) {
                  setState(() {
                    _failProgress = _failProgressTarget;
                  });
                }
              },
            ),
        ],
      ),
    );
  }
}

class _MobilePaymentLoading extends StatelessWidget {
  final VoidCallback onCancel;

  const _MobilePaymentLoading({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFFFF8F2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFFEBDFD3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 34,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Image.asset(
                      "assets/self.png",
                      height: 42,
                      fit: BoxFit.contain,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: onCancel,
                      child: const Text("Cancel"),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB3483A), Color(0xFF862A22)],
                    ),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Preparing payment",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1D1D1D),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Creating your order and preparing your payment apps.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobilePaymentLayout extends StatelessWidget {
  final int remainingSeconds;
  final String restaurantName;
  final String amountLabel;
  final double viewportHeight;
  final String? paymentQrData;
  final String paymentHint;
  final VoidCallback onGooglePay;
  final VoidCallback onPhonePe;
  final VoidCallback onPaytm;
  final VoidCallback onOtherUpi;
  final VoidCallback onCancel;
  final VoidCallback onStartAgain;

  const _MobilePaymentLayout({
    required this.remainingSeconds,
    required this.restaurantName,
    required this.amountLabel,
    required this.viewportHeight,
    required this.paymentQrData,
    required this.paymentHint,
    required this.onGooglePay,
    required this.onPhonePe,
    required this.onPaytm,
    required this.onOtherUpi,
    required this.onCancel,
    required this.onStartAgain,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final safeVertical = media.padding.top + media.padding.bottom;
    final shortScreen = screenSize.height < 820;
    final topPadding = shortScreen ? 14.0 : 20.0;
    final bottomPadding = shortScreen ? 18.0 : 24.0;
    final availableHeight =
        (screenSize.height - safeVertical - topPadding - bottomPadding)
            .clamp(420.0, screenSize.height);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, bottomPadding),
      child: SizedBox(
        width: double.infinity,
        height: availableHeight,
        child: _MobilePaymentMainCard(
          remainingSeconds: remainingSeconds,
          restaurantName: restaurantName,
          amountLabel: amountLabel,
          paymentQrData: paymentQrData,
          paymentHint: paymentHint,
          onGooglePay: onGooglePay,
          onPhonePe: onPhonePe,
          onPaytm: onPaytm,
          onOtherUpi: onOtherUpi,
          onCancel: onCancel,
          onStartAgain: onStartAgain,
        ),
      ),
    );
  }
}

class _MobilePaymentMainCard extends StatelessWidget {
  final int remainingSeconds;
  final String restaurantName;
  final String amountLabel;
  final String? paymentQrData;
  final String paymentHint;
  final VoidCallback onGooglePay;
  final VoidCallback onPhonePe;
  final VoidCallback onPaytm;
  final VoidCallback onOtherUpi;
  final VoidCallback onCancel;
  final VoidCallback onStartAgain;

  const _MobilePaymentMainCard({
    required this.remainingSeconds,
    required this.restaurantName,
    required this.amountLabel,
    required this.paymentQrData,
    required this.paymentHint,
    required this.onGooglePay,
    required this.onPhonePe,
    required this.onPaytm,
    required this.onOtherUpi,
    required this.onCancel,
    required this.onStartAgain,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final ultraShortCard = constraints.maxHeight < 620;
        final outerPadding = compact ? 16.0 : 22.0;
        final heroPadding = compact ? 18.0 : 24.0;
        final sectionPadding = compact ? 14.0 : 18.0;
        final heroActionHeight = compact ? 68.0 : 72.0;
        final footerActionHeight = compact ? 48.0 : 54.0;
        final amountSize = ultraShortCard ? 24.0 : (compact ? 30.0 : 36.0);
        final timerValueSize = ultraShortCard ? 22.0 : 28.0;

        return Padding(
          padding: EdgeInsets.all(outerPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.all(heroPadding),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFAA4337),
                      Color(0xFF862A22),
                      Color(0xFF6E211A),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset(
                          "assets/self.png",
                          height: compact ? 32 : 38,
                          fit: BoxFit.contain,
                        ),
                        const Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 14 : 18,
                            vertical: compact ? 10 : 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                "Time left",
                                style: TextStyle(
                                  color: Color(0xFFFDEAE2),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${remainingSeconds}s",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: timerValueSize,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 16 : 18),
                    const SizedBox(height: 6),
                    Text(
                      restaurantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFFDE4DB),
                        fontSize: compact ? 12.5 : 13.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 18),
                    SizedBox(
                      height: heroActionHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            fit: FlexFit.tight,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 14 : 18,
                                vertical: compact ? 8 : 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_rounded,
                                    color: Colors.white,
                                    size: compact ? 22 : 26,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Amount to pay",
                                          style: TextStyle(
                                            color: Color(0xFFFDEAE2),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            height: 1.1,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.bottomLeft,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                amountLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: amountSize,
                                                  fontWeight: FontWeight.w900,
                                                  height: 1,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            height: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: onStartAgain,
                              icon: Icon(
                                Icons.refresh_rounded,
                                size: compact ? 16 : 18,
                              ),
                              label: Text(compact ? "Restart" : "Start Again"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.34),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 12 : 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 14 : 18),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: sectionPadding,
                    vertical: compact ? 2 : 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Choose your payment app",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 17 : 19,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1D1D1D),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        paymentHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 12.5 : 13.5,
                          height: 1.45,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: compact ? 14 : 16),
                      if (paymentQrData != null) ...[
                        _MobilePaymentQrCard(
                          qrData: paymentQrData!,
                          amountLabel: amountLabel,
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 12 : 14),
                      ],
                      _MobilePayAppTile(
                        title: "Google Pay",
                        subtitle: "Open Google Pay",
                        assetPath: "assets/payment_icons/google_pay.svg",
                        accent: const Color(0xFFEAF2FF),
                        foreground: const Color(0xFF1A73E8),
                        compact: compact,
                        onTap: onGooglePay,
                      ),
                      SizedBox(height: compact ? 10 : 12),
                      _MobilePayAppTile(
                        title: "PhonePe",
                        subtitle: "Open PhonePe",
                        assetPath: "assets/payment_icons/phonepe.svg",
                        accent: const Color(0xFFF4ECFF),
                        foreground: const Color(0xFF5F259F),
                        compact: compact,
                        onTap: onPhonePe,
                      ),
                      SizedBox(height: compact ? 10 : 12),
                      _MobilePayAppTile(
                        title: "Paytm",
                        subtitle: "Open Paytm",
                        assetPath: "assets/payment_icons/paytm.svg",
                        accent: const Color(0xFFEAF8FF),
                        foreground: const Color(0xFF20336B),
                        compact: compact,
                        onTap: onPaytm,
                      ),
                      SizedBox(height: compact ? 10 : 12),
                      _MobilePayAppTile(
                        title: "Open Any UPI",
                        subtitle: "Open any UPI app",
                        icon: Icons.account_balance_wallet_rounded,
                        accent: const Color(0xFFFFF0E5),
                        foreground: const Color(0xFFB55A21),
                        compact: compact,
                        onTap: onOtherUpi,
                      ),
                      SizedBox(height: compact ? 12 : 14),
                      SizedBox(
                        height: footerActionHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Flexible(
                              fit: FlexFit.tight,
                              child: OutlinedButton(
                                onPressed: onOtherUpi,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF9F342C),
                                  side: const BorderSide(
                                    color: Color(0xFFD8C6B4),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: Text(
                                  "Open Any UPI",
                                  style: TextStyle(
                                    fontSize: compact ? 13.5 : 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: double.infinity,
                              child: TextButton(
                                onPressed: onCancel,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF9F342C),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 8 : 12,
                                  ),
                                ),
                                child: Text(
                                  compact ? "Cancel" : "Cancel Order",
                                  style: TextStyle(
                                    fontSize: compact ? 13.5 : 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MobilePaymentQrCard extends StatelessWidget {
  final String qrData;
  final String amountLabel;
  final bool compact;

  const _MobilePaymentQrCard({
    required this.qrData,
    required this.amountLabel,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final qrSize = compact ? 170.0 : 196.0;

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEADCCD)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF9F342C).withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              "TEST PAYMENT QR",
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: const Color(0xFF9F342C),
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          Text(
            "Scan this QR with any UPI app to pay $amountLabel.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 12.5 : 13.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF3B3028),
            ),
          ),
          SizedBox(height: compact ? 12 : 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              size: qrSize,
              backgroundColor: Colors.white,
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          Text(
            "After payment is completed, the order QR and barcode screen will open automatically for printing.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 11.5 : 12.5,
              height: 1.45,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePayAppTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? assetPath;
  final IconData? icon;
  final Color accent;
  final Color foreground;
  final bool compact;
  final VoidCallback onTap;

  const _MobilePayAppTile({
    required this.title,
    required this.subtitle,
    this.assetPath,
    this.icon,
    required this.accent,
    required this.foreground,
    this.compact = false,
    required this.onTap,
  }) : assert(assetPath != null || icon != null);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 10 : 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE8DDD2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 40 : 48,
                height: compact ? 40 : 48,
                padding: EdgeInsets.all(compact ? 8 : 10),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: assetPath != null
                    ? SvgPicture.asset(
                        assetPath!,
                        colorFilter: ColorFilter.mode(
                          foreground,
                          BlendMode.srcIn,
                        ),
                      )
                    : Icon(icon, color: foreground, size: compact ? 22 : 28),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13.5 : 15.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1D1D1D),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 11.5 : 13,
                        color: Colors.black54,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 6 : 8),
              Icon(
                Icons.arrow_forward_rounded,
                color: foreground,
                size: compact ? 16 : 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobilePaymentErrorOverlay extends StatelessWidget {
  final String message;
  final int seconds;
  final double progress;
  final double targetProgress;
  final VoidCallback onProgressEnd;

  const _MobilePaymentErrorOverlay({
    required this.message,
    required this.seconds,
    required this.progress,
    required this.targetProgress,
    required this.onProgressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isTimeout = message.toLowerCase().contains("timed out");

    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0EB),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF9F342C),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    isTimeout ? "Order Timed Out" : "Payment Failed",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1D1D1D),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: TweenAnimationBuilder<double>(
                      tween:
                          Tween<double>(begin: progress, end: targetProgress),
                      duration: const Duration(milliseconds: 450),
                      onEnd: onProgressEnd,
                      builder: (_, value, __) {
                        return Directionality(
                          textDirection: TextDirection.rtl,
                          child: LinearProgressIndicator(
                            value: value.clamp(0, 1),
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF9F342C),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Returning in ${seconds}s",
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
