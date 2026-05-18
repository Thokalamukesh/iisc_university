import 'dart:async';

import 'package:flutter/material.dart';
import 'package:api_selfxo_project/core/fast_page_route.dart';
import 'package:api_selfxo_project/core/image_url.dart';
import 'package:api_selfxo_project/core/kiosk_config.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';
import 'package:api_selfxo_project/widget/app_network_image.dart';
import 'payment_screen.dart';

// Note: Replace with your actual Welcome Screen import if needed
// import 'package:api_selfxo_project/screens/welcome_screen.dart';

class CartPage extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final List<Map<String, dynamic>> recommendedProducts;
  final bool isActive;
  final String orderType;
  final Function(
    int id,
    String name,
    String category,
    int price,
    String image,
    int qty,
    Map<String, dynamic>? variation,
    List<Map<String, dynamic>> modifiers,
    Rect? imageRect,
  ) onAddRecommended;
  final VoidCallback onBack;
  final VoidCallback onStartOver;
  final VoidCallback onCartUpdated;

  const CartPage({
    super.key,
    required this.cart,
    required this.recommendedProducts,
    required this.isActive,
    required this.orderType,
    required this.onAddRecommended,
    required this.onBack,
    required this.onStartOver,
    required this.onCartUpdated,
  });

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> with TickerProviderStateMixin {
  static const Color kGreen = Color(0xFF9F342C);
  static const Color _payGreen = Color(0xFF2F8F46);
  static const Color _softSurface = Color(0xFFF7F8F6);

  // 🔴 GST SETTINGS
  final bool gstEnabled = true;
  final double gstPercent = 5;
  bool gstExpanded = false;

  String _normalizeOrderType(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll("-", "_")
        .replaceAll(RegExp(r"\s+"), "_");
  }

  bool get _isTakeAway {
    final type = _normalizeOrderType(widget.orderType);
    return type == "pickup" || type == "takeaway" || type == "take_away";
  }

  late AnimationController _payController;
  late Animation<double> _payScale;
  int _lastCartCount = 0;
  final ScrollController _cartScrollController = ScrollController();
  VoidCallback? _maintenanceListener;
  OverlayEntry? _recommendedPopupEntry;
  Timer? _recommendedPopupTimer;
  Timer? _recommendedSheetDelayTimer;
  BuildContext? _recommendedSheetContext;
  bool _recommendedSheetShownForVisit = false;
  bool _recommendedSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _lastCartCount = widget.cart.length;
    _payController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _payScale = Tween<double>(
      begin: 1,
      end: 1.06,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_payController);
    if (widget.cart.isNotEmpty && KioskConfig.enableDecorativeAnimations) {
      _payController.repeat(reverse: true);
    }

    _maintenanceListener = _handleMaintenanceTick;
    KioskMemoryService.instance.maintenanceTick.addListener(
      _maintenanceListener!,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleRecommendedSheetIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant CartPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = widget.cart.length;
    if (count > 0 && _lastCartCount == 0) {
      _startPayBounce();
    } else if (count == 0 && _lastCartCount > 0) {
      _stopPayBounce();
    }
    _lastCartCount = count;

    if (!widget.isActive || widget.cart.isEmpty) {
      _recommendedSheetShownForVisit = false;
      _cancelRecommendedSheetTimers();
      _closeRecommendedSheetIfOpen();
    } else if (!oldWidget.isActive && widget.isActive) {
      _recommendedSheetShownForVisit = false;
      _scheduleRecommendedSheetIfNeeded();
    } else {
      _scheduleRecommendedSheetIfNeeded();
    }
  }

  @override
  void dispose() {
    _removeRecommendedPopup();
    _cancelRecommendedSheetTimers();
    if (_payController.isAnimating) {
      _payController.stop(canceled: true);
    }
    _payController.dispose();
    _cartScrollController.dispose();
    if (_maintenanceListener != null) {
      KioskMemoryService.instance.maintenanceTick.removeListener(
        _maintenanceListener!,
      );
    }
    super.dispose();
  }

  @override
  void deactivate() {
    if (_payController.isAnimating) {
      _payController.stop(canceled: true);
    }
    super.deactivate();
  }

  bool get _canShowRecommendedSheet {
    return widget.isActive &&
        mounted &&
        !_recommendedSheetShownForVisit &&
        !_recommendedSheetOpen &&
        widget.cart.isNotEmpty &&
        _filteredRecommendations().isNotEmpty;
  }

  void _scheduleRecommendedSheetIfNeeded() {
    if (!_canShowRecommendedSheet) {
      if (widget.cart.isEmpty || !widget.isActive) {
        _recommendedSheetDelayTimer?.cancel();
        _recommendedSheetDelayTimer = null;
      }
      return;
    }
    if (_recommendedSheetDelayTimer?.isActive ?? false) return;

    _recommendedSheetDelayTimer = Timer(const Duration(seconds: 0), () {
      _recommendedSheetDelayTimer = null;
      if (!_canShowRecommendedSheet) return;
      _showRecommendedAutoSheet();
    });
  }

  void _cancelRecommendedSheetTimers() {
    _recommendedSheetDelayTimer?.cancel();
    _recommendedSheetDelayTimer = null;
  }

  void _closeRecommendedSheetIfOpen() {
    if (!_recommendedSheetOpen) return;
    final contextToClose = _recommendedSheetContext;
    if (contextToClose == null) return;
    final navigator = Navigator.maybeOf(contextToClose);
    if (navigator?.canPop() == true) {
      navigator!.pop();
    }
  }

  Future<void> _showRecommendedAutoSheet() async {
    if (!_canShowRecommendedSheet) return;
    _recommendedSheetShownForVisit = true;
    _recommendedSheetOpen = true;

    final mediaSize = MediaQuery.of(context).size;
    final isTablet = mediaSize.shortestSide >= 700;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withOpacity(0.22),
        builder: (modalContext) {
          _recommendedSheetContext = modalContext;
          return _buildRecommendedAutoSheet(modalContext, isTablet);
        },
      );
    } finally {
      _recommendedSheetContext = null;
      _recommendedSheetOpen = false;
    }
  }

  void _startPayBounce() {
    if (!mounted) return;
    if (!KioskConfig.enableDecorativeAnimations) return;
    if (!_payController.isAnimating) {
      _payController.repeat(reverse: true);
    }
  }

  void _stopPayBounce() {
    if (!mounted) return;
    if (_payController.isAnimating) {
      _payController.stop();
      _payController.reset();
    }
  }

  void _handleMaintenanceTick() {
    if (!mounted) return;
    try {
      if (!KioskConfig.enableDecorativeAnimations) return;
      if (widget.cart.isEmpty) return;
      _payController.reset();
      _payController.repeat(reverse: true);
    } catch (_) {}
  }

  void _updateQty(int index, int newQty) {
    setState(() {
      if (newQty <= 0) {
        widget.cart.removeAt(index);
      } else {
        widget.cart[index] = {...widget.cart[index], "qty": newQty};
      }
    });
    widget.onCartUpdated();
    if (widget.cart.isNotEmpty) {
      _startPayBounce();
    }
    if (widget.cart.isEmpty) {
      _stopPayBounce();
      Future.microtask(widget.onBack);
    }
  }

  double _calculateSubtotal() {
    return widget.cart.fold<double>(0.0, (sum, item) {
      return sum + (_asDouble(item["price"]) * _asInt(item["qty"]));
    });
  }

  double _calculateParcelTotal() {
    if (!_isTakeAway) return 0.0;
    return widget.cart.fold<double>(0.0, (sum, item) {
      return sum + (_asDouble(item["take_away_charge"]) * _asInt(item["qty"]));
    });
  }

  double _calculateTotal() {
    return _calculateSubtotal() + _calculateParcelTotal();
  }

  double _calculateGstInclusive(double total) {
    if (!gstEnabled) return 0;
    return (total * gstPercent) / (100 + gstPercent);
  }

  double _calculateBaseAmount(double total) {
    return total - _calculateGstInclusive(total);
  }

  int _totalQtyForProduct(int id) {
    return widget.cart.fold<int>(
      0,
      (sum, item) => sum + (item["id"] == id ? _asInt(item["qty"]) : 0),
    );
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? "") ?? 0.0;
  }

  List<Map<String, dynamic>> _filteredRecommendations() {
    if (widget.cart.isEmpty) return [];
    final recs = widget.recommendedProducts
        .take(5)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return recs;
  }

  Rect? _rectFromContext(BuildContext? context) {
    if (context == null) return null;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached) return null;
    final topLeft = render.localToGlobal(Offset.zero);
    return topLeft & render.size;
  }

  void _addRecommended(Map<String, dynamic> item, Rect? imageRect) {
    final id = int.tryParse(item["id"].toString()) ?? 0;
    if (id == 0) return;
    final name =
        item["name"]?.toString() ?? item["item_name"]?.toString() ?? "";
    final category = item["category"]?.toString() ?? "";
    final price = int.tryParse(item["price"].toString()) ?? 0;
    final image =
        item["image"]?.toString() ?? item["item_photo_url"]?.toString() ?? "";
    final variation = item["variation"] as Map<String, dynamic>? ??
        (item["variations"] is List && (item["variations"] as List).isNotEmpty
            ? Map<String, dynamic>.from(item["variations"][0])
            : null);
    final modifiers = item["modifiers"] is List
        ? (item["modifiers"] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const <Map<String, dynamic>>[];

    final newQty = _totalQtyForProduct(id) + 1;
    widget.onAddRecommended(
      id,
      name,
      category,
      price,
      image,
      newQty,
      variation,
      modifiers,
      imageRect,
    );
    widget.onCartUpdated();
    _showRecommendedAddedPopup(name);
  }

  void _removeRecommendedPopup() {
    _recommendedPopupTimer?.cancel();
    _recommendedPopupTimer = null;
    _recommendedPopupEntry?.remove();
    _recommendedPopupEntry = null;
  }

  void _showRecommendedAddedPopup(String name) {
    if (!mounted) return;
    _removeRecommendedPopup();
    _recommendedPopupEntry = OverlayEntry(
      builder: (context) {
        final topInset = MediaQuery.of(context).padding.top;
        return Positioned(
          top: topInset + 12,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEFE1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEED8B8)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: _removeRecommendedPopup,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Color(0xFF7A4A2D),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    "Added from Recommended",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF5D3320),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name.isEmpty ? "Item added to cart" : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7B5A44),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    final overlay = Overlay.of(context);
    overlay.insert(_recommendedPopupEntry!);
    _recommendedPopupTimer = Timer(
      const Duration(seconds: 4),
      _removeRecommendedPopup,
    );
  }

  void _showStartOverDialog(BuildContext context) {
    final bool isTablet = MediaQuery.of(context).size.width > 600;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isTablet ? 40 : 26),
          ),
          contentPadding: EdgeInsets.all(isTablet ? 40 : 24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(isTablet ? 30 : 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBAA30).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.restaurant_rounded,
                  color: const Color(0xFFFBAA30),
                  size: isTablet ? 100 : 50,
                ),
              ),
              SizedBox(height: isTablet ? 30 : 20),
              Text(
                "CANCEL ORDER?",
                style: TextStyle(
                  fontSize: isTablet ? 32 : 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 15),
              Text(
                "Are you sure you want to cancel this order\nand start again?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isTablet ? 20 : 15.5,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              SizedBox(height: isTablet ? 45 : 30),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: isTablet ? 85 : 55,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.grey.shade300,
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              isTablet ? 20 : 12,
                            ),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: Icon(
                          Icons.close_rounded,
                          size: isTablet ? 22 : 18,
                          color: Colors.grey.shade700,
                        ),
                        label: Text(
                          "NO, KEEP",
                          style: TextStyle(
                            fontSize: isTablet ? 18 : 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isTablet ? 20 : 12),
                  Expanded(
                    child: SizedBox(
                      height: isTablet ? 85 : 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFBAA30),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              isTablet ? 20 : 12,
                            ),
                          ),
                        ),
                        onPressed: () {
                          widget.cart.clear();
                          widget.onCartUpdated();
                          Navigator.pop(dialogContext);
                          widget.onStartOver();
                        },
                        child: Text(
                          "YES, CANCEL",
                          style: TextStyle(
                            fontSize: isTablet ? 18 : 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.of(context).size;
    final bool isTablet = mediaSize.shortestSide >= 700;

    return Scaffold(
      backgroundColor: _softSurface,
      appBar: AppBar(
        toolbarHeight: isTablet ? 100 : 64,
        backgroundColor: kGreen,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: Colors.white,
            size: isTablet ? 30 : 22,
          ),
          onPressed: widget.onBack,
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            isTablet
                ? "Your Cart (${widget.cart.length})"
                : "Cart (${widget.cart.length})",
            maxLines: 1,
            style: TextStyle(
              fontSize: isTablet ? 28 : 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: isTablet ? 20 : 12),
            child: SizedBox(
              height: isTablet ? 50 : 38,
              child: ElevatedButton.icon(
                onPressed: () => _showStartOverDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFFBAA30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                icon: Icon(Icons.home, size: isTablet ? 22 : 18),
                label: Text(
                  isTablet ? "Start Again" : "Restart",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isTablet ? 18 : 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: isTablet
            ? [
                _tableHeader(isTablet),
                Expanded(
                  child: Scrollbar(
                    controller: _cartScrollController,
                    thumbVisibility: true,
                    thickness: 5,
                    radius: const Radius.circular(8),
                    child: ListView.builder(
                      controller: _cartScrollController,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      itemCount: widget.cart.length,
                      itemBuilder: (context, i) =>
                          _cartItem(widget.cart[i], i, isTablet),
                    ),
                  ),
                ),
                _totalSection(isTablet),
                _bottomActions(isTablet),
              ]
            : [
                Expanded(
                  child: Scrollbar(
                    controller: _cartScrollController,
                    thumbVisibility: false,
                    thickness: 4,
                    radius: const Radius.circular(8),
                    child: ListView.builder(
                      controller: _cartScrollController,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                      itemCount: widget.cart.length,
                      itemBuilder: (context, i) =>
                          _cartItemMobile(widget.cart[i], i),
                    ),
                  ),
                ),
                _totalSection(isTablet),
                _bottomActions(isTablet),
              ],
      ),
    );
  }

  Widget _tableHeader(bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: 12,
        horizontal: isTablet ? 24 : 8,
      ),
      color: const Color(0xFFE9F4EC),
      child: Row(
        children: [
          SizedBox(width: isTablet ? 80 : 50), // Matches image width + spacing
          _headerText("ITEM", 3, isTablet),
          _headerText("PRICE", 2, isTablet, true),
          _headerText(isTablet ? "QUANTITY" : "QTY", 2, isTablet, true),
          _headerText("TOTAL", 2, isTablet, true),
          _headerText(isTablet ? "ACTION" : "ACT", 1, isTablet, true),
        ],
      ),
    );
  }

  Widget _buildRecommendedSection(bool isTablet) {
    final recs = _filteredRecommendations();

    if (widget.cart.isEmpty || recs.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = !isTablet || width < 600;

        final double cardWidth = isMobile
            ? ((width - 38) / 2.35).clamp(124.0, 150.0)
            : (isTablet ? 210 : 165);

        final double cardHeight = isMobile ? 146 : (isTablet ? 222 : 198);

        final double imageHeight = isMobile ? 70 : (isTablet ? 136 : 118);

        final double titleSize = isMobile ? 16 : (isTablet ? 22 : 20);

        final double textSize = isMobile ? 11.5 : (isTablet ? 13 : 12);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 2 : 16,
            isMobile ? 2 : 4,
            isMobile ? 2 : 16,
            isMobile ? 8 : 10,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFEFE1),
              borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// HEADER
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 12 : 16,
                    isMobile ? 10 : 12,
                    isMobile ? 12 : 16,
                    isMobile ? 6 : 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: isMobile ? 16 : 24,
                        color: const Color(0xFF22E6C7),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Recommended",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                /// LIST
                Padding(
                  padding: const EdgeInsets.only(
                    left: 8,
                    right: 8,
                    bottom: 8,
                  ),
                  child: SizedBox(
                    height: cardHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: recs.length,
                      separatorBuilder: (_, __) => SizedBox(
                        width: isMobile ? 10 : 8,
                      ),
                      itemBuilder: (_, index) {
                        final item = recs[index];

                        final name = item["name"]?.toString() ??
                            item["item_name"]?.toString() ??
                            "";

                        final price = item["price"] ?? 0;

                        final image = item["image"]?.toString() ?? "";

                        BuildContext? imageContext;

                        return SizedBox(
                          width: cardWidth,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: imageHeight,
                                  width: double.infinity,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Builder(
                                      builder: (ctx) {
                                        imageContext = ctx;

                                        final url = normalizeImageUrl(image);

                                        return image.isNotEmpty
                                            ? AppNetworkImage(
                                                url: url,
                                                fit: BoxFit.cover,
                                                fallback:
                                                    const Icon(Icons.fastfood),
                                              )
                                            : const Icon(Icons.fastfood);
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: textSize,
                                    height: 1.15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "₹$price",
                                      style: TextStyle(
                                        fontSize: textSize,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFFC40012),
                                      ),
                                    ),
                                    SizedBox(
                                      height: isMobile ? 30 : 28,
                                      width: isMobile ? 58 : 64,
                                      child: ElevatedButton(
                                        onPressed: () => _addRecommended(
                                          item,
                                          _rectFromContext(imageContext),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          elevation: 4,
                                          shadowColor:
                                              _payGreen.withOpacity(0.35),
                                          backgroundColor: _payGreen,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              isMobile ? 9 : 7,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          "Add",
                                          style: TextStyle(
                                            fontSize: isMobile ? 12 : 11,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
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
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecommendedAutoSheet(BuildContext sheetContext, bool isTablet) {
    final maxHeight =
        MediaQuery.of(context).size.height * (isTablet ? 0.48 : 0.55);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          color: const Color(0xFFFFEFE1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isTablet ? 18 : 10,
              8,
              isTablet ? 18 : 10,
              12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: "Close",
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: _buildRecommendedSection(isTablet),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerText(
    String label,
    int flex,
    bool isTablet, [
    bool center = false,
  ]) {
    return Expanded(
      flex: flex,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: center ? Alignment.center : Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: isTablet ? 16 : 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _cartItem(Map<String, dynamic> item, int index, bool isTablet) {
    final int price = _asInt(item["price"]);
    final int qty = _asInt(item["qty"]);
    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final int imagePx = ((isTablet ? 70 : 34) * dpr).round();
    final imageUrl = normalizeImageUrlValue(item["image"]);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.all(isTablet ? 20 : 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl.isNotEmpty
                ? AppNetworkImage(
                    url: imageUrl,
                    width: isTablet ? 70 : 34,
                    height: isTablet ? 70 : 34,
                    cacheWidth: imagePx,
                    cacheHeight: imagePx,
                    fit: BoxFit.cover,
                    fallback: Icon(Icons.fastfood, size: isTablet ? 70 : 34),
                  )
                : Icon(Icons.fastfood, size: isTablet ? 70 : 34),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              item["name"],
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isTablet ? 18 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                "₹$price",
                style: TextStyle(fontSize: isTablet ? 18 : 13),
              ),
            ),
          ),

          // Fixed Quantity Selector for Mobile
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _iconTap(
                    Icons.remove,
                    Colors.red,
                    () => _updateQty(index, qty - 1),
                    isTablet,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      "$qty",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 20 : 15,
                      ),
                    ),
                  ),
                  _iconTap(
                    Icons.add,
                    Colors.green,
                    () => _updateQty(index, qty + 1),
                    isTablet,
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Center(
              child: Text(
                "₹${price * qty}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kGreen,
                  fontSize: isTablet ? 18 : 13,
                ),
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              Icons.delete_outline,
              color: kGreen,
              size: isTablet ? 30 : 20,
            ),
            onPressed: () {
              setState(() => widget.cart.removeAt(index));
              widget.onCartUpdated();
              if (widget.cart.isEmpty) widget.onBack();
            },
          ),
        ],
      ),
    );
  }

  Widget _cartItemMobile(Map<String, dynamic> item, int index) {
    final int price = _asInt(item["price"]);
    final int qty = _asInt(item["qty"]);
    final int parcelCharge = _asInt(item["take_away_charge"]);
    final imageUrl = normalizeImageUrlValue(item["image"]);
    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final int imagePx = (66 * dpr).round();
    final String name = item["name"]?.toString() ?? "Item";
    final String? variation = item["variation"] is Map
        ? (item["variation"] as Map)["variation"]?.toString()
        : null;
    final modifiers = item["modifiers"] is List
        ? (item["modifiers"] as List)
            .map((e) => e is Map ? e["name"]?.toString() : null)
            .whereType<String>()
            .where((e) => e.trim().isNotEmpty)
            .take(2)
            .join(", ")
        : "";

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9E9E9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageUrl.isNotEmpty
                    ? AppNetworkImage(
                        url: imageUrl,
                        width: 66,
                        height: 66,
                        cacheWidth: imagePx,
                        cacheHeight: imagePx,
                        fit: BoxFit.cover,
                        fallback: const Icon(Icons.fastfood, size: 38),
                      )
                    : const SizedBox(
                        width: 66,
                        height: 66,
                        child: Icon(Icons.fastfood, size: 38),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1F1F1F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "₹$price each",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.black54,
                      ),
                    ),
                    if ((variation ?? "").isNotEmpty || modifiers.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if ((variation ?? "").isNotEmpty) variation,
                            if (modifiers.isNotEmpty) modifiers,
                          ].whereType<String>().join(" - "),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (_isTakeAway && parcelCharge > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "Parcel ₹$parcelCharge",
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: kGreen,
                  size: 22,
                ),
                onPressed: () {
                  setState(() => widget.cart.removeAt(index));
                  widget.onCartUpdated();
                  if (widget.cart.isEmpty) widget.onBack();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _quantityStepper(index, qty),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    "Item total",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "₹${price * qty}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: kGreen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quantityStepper(int index, int qty) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F4),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E4DF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepperButton(
            icon: Icons.remove_rounded,
            color: kGreen,
            onTap: () => _updateQty(index, qty - 1),
          ),
          SizedBox(
            width: 36,
            child: Text(
              "$qty",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _stepperButton(
            icon: Icons.add_rounded,
            color: _payGreen,
            onTap: () => _updateQty(index, qty + 1),
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _totalSection(bool isTablet) {
    final subtotal = _calculateSubtotal();
    final parcelTotal = _calculateParcelTotal();
    final total = subtotal + parcelTotal;
    final gstAmount = _calculateGstInclusive(total);
    final baseAmount = _calculateBaseAmount(total);

    return Container(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 30 : 16,
        isTablet ? 30 : 14,
        isTablet ? 30 : 16,
        isTablet ? 30 : 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 14,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          _summaryRow(
            "Grand Total",
            "₹${total.toStringAsFixed(2)}",
            isBold: true,
            fontSize: isTablet ? 27 : 21,
            color: const Color.fromARGB(255, 0, 0, 0),
            isTablet: isTablet,
          ),
          if (_isTakeAway && parcelTotal > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _summaryRow(
                "Parcel Charge",
                "₹${parcelTotal.toStringAsFixed(2)}",
                isSmall: true,
                isTablet: isTablet,
              ),
            ),
          const Divider(height: 18),
          if (gstEnabled) ...[
            InkWell(
              onTap: () => setState(() => gstExpanded = !gstExpanded),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        "GST Included",
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: isTablet ? 18 : 13,
                        ),
                      ),
                      Icon(
                        gstExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: isTablet ? 24 : 18,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                  if (gstExpanded)
                    Text(
                      "₹${gstAmount.toStringAsFixed(2)}",
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: isTablet ? 18 : 13,
                      ),
                    ),
                ],
              ),
            ),
            if (gstExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: [
                    _summaryRow(
                      "GST Amount",
                      "₹${gstAmount.toStringAsFixed(2)}",
                      isSmall: true,
                      isTablet: isTablet,
                    ),
                    const SizedBox(height: 6),
                    _summaryRow(
                      "Base Amount",
                      "₹${baseAmount.toStringAsFixed(2)}",
                      isSmall: true,
                      isTablet: isTablet,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _bottomActions(bool isTablet) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(12, 8, 12, isTablet ? 22 : 12),
        child: Row(
          children: [
            Expanded(
              flex: isTablet ? 1 : 5,
              child: SizedBox(
                height: isTablet ? 64 : 50,
                width: isTablet ? 260 : null,
                child: OutlinedButton.icon(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1F1F1F),
                    side: const BorderSide(color: Color(0xFFD5D8D0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    Icons.add_circle_outline_rounded,
                    color: _payGreen,
                    size: isTablet ? 28 : 20,
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      isTablet ? "Add More Items" : "Add More",
                      style: TextStyle(
                        fontSize: isTablet ? 18 : 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: isTablet ? 1 : 6,
              child: SizedBox(
                height: isTablet ? 64 : 50,
                width: isTablet ? 260 : null,
                child: ScaleTransition(
                  scale: _payScale,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _payGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _goToPayment,
                    icon: Icon(
                      Icons.shopping_cart_checkout_rounded,
                      size: isTablet ? 24 : 20,
                    ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isTablet ? "PROCEED TO PAY" : "Pay Now",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: isTablet ? 0.6 : 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 16,
    Color? color,
    bool isSmall = false,
    required bool isTablet,
  }) {
    double finalFontSize = isTablet ? (fontSize * 1.2) : fontSize;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: finalFontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: isSmall ? Colors.grey : Colors.black87,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: finalFontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? (isSmall ? Colors.grey : Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _iconTap(
    IconData icon,
    Color color,
    VoidCallback onTap,
    bool isTablet,
  ) {
    final double size = isTablet ? 34 : 28;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: isTablet ? 20 : 18),
      ),
    );
  }

  void _goToPayment() {
    final total = _calculateTotal();
    if (total <= 0) return;
    Navigator.push(
      context,
      fastPageRoute(
        (_) => PaymentScreen(
          cart: List<Map<String, dynamic>>.from(widget.cart),
          totalAmount: total.toInt(),
          orderType: widget.orderType,
        ),
      ),
    );
  }
}
