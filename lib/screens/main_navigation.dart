import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:api_selfxo_project/core/device_layout.dart';
import 'package:api_selfxo_project/core/fast_page_route.dart';
import 'package:api_selfxo_project/core/kiosk_config.dart';
import 'package:api_selfxo_project/core/image_url.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';
import 'package:api_selfxo_project/screens/block_screen.dart';
import 'package:api_selfxo_project/widget/app_network_image.dart';
import 'home_page2.dart';
import 'cart_page.dart';

class MainNavigation extends StatefulWidget {
  final String orderType;

  const MainNavigation({super.key, required this.orderType});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with TickerProviderStateMixin {
  int currentIndex = 0;

  /// 🔥 BACKEND SAFE CART
  List<Map<String, dynamic>> cart = [];
  List<Map<String, dynamic>> recommendedProducts = [];
  List<dynamic> _productsRaw = [];
  String _productsSignature = "";
  final Map<int, int> _takeAwayChargeById = {};
  Set<int> _cartIdSet() => cart
      .map((e) => int.tryParse(e["id"].toString()) ?? 0)
      .where((e) => e > 0)
      .toSet();

  void _refreshRecommendations() {
    if (_productsRaw.isEmpty) return;
    recommendedProducts = buildRecommendedProducts(
      _productsRaw,
      _cartIdSet(),
    );
  }

  String _normalizeKey(String k) =>
      k.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "");

  dynamic _readKey(Map src, List<String> keys) {
    for (final key in keys) {
      if (src.containsKey(key)) return src[key];
    }
    final wanted = keys.map(_normalizeKey).toSet();
    for (final entry in src.entries) {
      final nk = _normalizeKey(entry.key.toString());
      if (wanted.contains(nk)) return entry.value;
    }
    return null;
  }

  String _buildProductsSignature(List<dynamic> products) {
    if (products.isEmpty) return "0";
    final buffer = StringBuffer("${products.length}:");
    for (final item in products.take(20)) {
      if (item is Map) {
        buffer
          ..write(item["id"] ?? item["product_id"] ?? "")
          ..write("|")
          ..write(item["updated_at"] ?? item["price"] ?? "")
          ..write(",");
      }
    }
    return buffer.toString();
  }

  void _rebuildTakeAwayChargeMap(List<dynamic> raw) {
    _takeAwayChargeById.clear();
    for (final category in raw) {
      if (category is! Map) continue;
      final items = category["items"];
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        final id = _asInt(
          _readKey(
            item,
            ["id", "Id", "ID", "item_id", "itemId"],
          ),
        );
        if (id == 0) continue;
        final nested = item["item"];
        final nestedMap =
            nested is Map ? Map<String, dynamic>.from(nested) : null;
        final rawCharge = _readKey(
              item,
              [
                "take_away_charge",
                "takeaway_charge",
                "takeAwayCharge",
                "parcel_charge",
                "parcelCharge",
              ],
            ) ??
            (nestedMap == null
                ? null
                : _readKey(
                    nestedMap,
                    [
                      "take_away_charge",
                      "takeaway_charge",
                      "takeAwayCharge",
                      "parcel_charge",
                      "parcelCharge",
                    ],
                  ));
        _takeAwayChargeById[id] = _asInt(rawCharge);
      }
    }
  }

  int _takeAwayChargeForId(int id) => _takeAwayChargeById[id] ?? 0;
  List<Map<String, dynamic>> buildRecommendedProducts(
    List<dynamic> apiProducts,
    Set<int> excludeIds,
  ) {
    bool isTruthy(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value == 1 || value == 1.0;
      final s = value.toString().toLowerCase().trim();
      if (s == "1" || s == "true" || s == "yes" || s == "y") return true;
      final parsed = num.tryParse(s);
      return parsed == 1 || parsed == 1.0;
    }

    int toInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? "") ?? 0;
    }

    String normKey(String k) =>
        k.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "");

    dynamic readNestedKey(Map<String, dynamic>? item, List<String> keys) {
      if (item == null) return null;
      for (final key in keys) {
        if (item.containsKey(key)) return item[key];
      }
      final wanted = keys.map(normKey).toSet();
      for (final entry in item.entries) {
        final nk = normKey(entry.key.toString());
        if (wanted.contains(nk)) return entry.value;
      }
      return null;
    }

    int resolveItemId(Map<String, dynamic> item, Map<String, dynamic>? nested) {
      final direct = readNestedKey(
        item,
        ["id", "Id", "ID", "item_id", "itemId", "itemId"],
      );
      if (direct != null) return toInt(direct);
      final nestedId = readNestedKey(
        nested,
        ["id", "Id", "ID", "item_id", "itemId", "itemId"],
      );
      return toInt(nestedId);
    }

    final List<Map<String, dynamic>> list = [];
    final Set<int> seen = {};

    final products =
        apiProducts.map((e) => Map<String, dynamic>.from(e)).toList();

    for (final category in products) {
      final catActiveRaw = category["is_active"];
      final bool catActive = catActiveRaw == null || isTruthy(catActiveRaw);
      if (!catActive) continue;
      final String catName = category["category_name"] ?? "Others";
      final List items = (category["items"] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      for (final item in items) {
        final nested = readNestedKey(
          item,
          ["item", "menu_item", "product", "details"],
        );
        final nestedMap =
            nested is Map ? Map<String, dynamic>.from(nested) : null;
        final avail = readNestedKey(
              item,
              ["is_available", "isAvailable", "available", "isAvailableNow"],
            ) ??
            readNestedKey(
              nestedMap,
              ["is_available", "isAvailable", "available", "isAvailableNow"],
            );
        final bool isAvailable = avail == null || isTruthy(avail);
        if (!isAvailable) continue;
        final rec = readNestedKey(
              item,
              [
                "is_recommended",
                "isRecommended",
                "recommended",
                "is_recommend",
                "is_recommanded",
              ],
            ) ??
            readNestedKey(
              nestedMap,
              [
                "is_recommended",
                "isRecommended",
                "recommended",
                "is_recommend",
                "is_recommanded",
              ],
            );
        final bool isRecommended = isTruthy(rec);
        if (!isRecommended) continue;
        final int id = resolveItemId(item, nestedMap);
        if (id == 0 || seen.contains(id) || excludeIds.contains(id)) continue;
        seen.add(id);

        final List<Map<String, dynamic>> variations =
            (item["variations"] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e))
                    .toList() ??
                [];

        final rawModifiers = item["modifiers"];
        final List<Map<String, dynamic>> modifiers =
            rawModifiers is Map && rawModifiers["options"] is List
                ? (rawModifiers["options"] as List)
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
                : [];

        final image = item["item_photo_url"] ??
            item["image"] ??
            item["photo_url"] ??
            nestedMap?["item_photo_url"] ??
            nestedMap?["image"] ??
            nestedMap?["photo_url"] ??
            "";
        final name = item["item_name"] ??
            item["name"] ??
            nestedMap?["item_name"] ??
            nestedMap?["name"] ??
            "";
        final Map<String, dynamic>? defaultVariation =
            variations.isNotEmpty ? variations.first : null;

        list.add({
          "id": id,
          "name": name,
          "price": toInt(
            item["price"] ??
                item["item_price"] ??
                nestedMap?["price"] ??
                nestedMap?["item_price"] ??
                0,
          ),
          "image": normalizeImageUrlValue(image),
          "category": catName,
          "variations": variations,
          "variation": defaultVariation,
          "modifiers": modifiers,
        });
      }
    }
    return list;
  }

  int getQtyForProduct(int productId) {
    return cart.fold<int>(
      0,
      (sum, item) => sum + (item["id"] == productId ? _asInt(item["qty"]) : 0),
    );
  }

  bool _sameModifiers(List<dynamic>? a, List<dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;

    final aIds = a.map((e) => e["id"]).toList()..sort();
    final bIds = b.map((e) => e["id"]).toList()..sort();

    for (int i = 0; i < aIds.length; i++) {
      if (aIds[i] != bIds[i]) return false;
    }
    return true;
  }

  int displayedItems = 0;
  int displayedPrice = 0;

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? "") ?? 0;
  }

  UniqueKey homeKey = UniqueKey();
  Rect? _cartIconRect;

  OverlayEntry? _overlayEntry;
  AnimationController? _flyController;
  Animation<double>? _flyAnim;
  Timer? _flyTimeoutTimer;

  /// CART ICON BOUNCE
  late AnimationController _cartBounceController;
  late Animation<double> _cartBounceAnim;

  /// VIEW CART INFINITE BOUNCE
  late AnimationController _viewCartController;
  late Animation<double> _viewCartScale;

  bool bounceActive = false;
  VoidCallback? _maintenanceListener;

  @override
  void initState() {
    super.initState();

    /// CART ICON BOUNCE
    _cartBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _cartBounceAnim = Tween<double>(
      begin: 1,
      end: 1.15,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_cartBounceController);

    _cartBounceController.addStatusListener((s) {
      if (!mounted) return;
      try {
        if (s == AnimationStatus.completed) {
          _cartBounceController.reverse();
        }
      } catch (_) {}
    });

    /// VIEW CART INFINITE BOUNCE
    _viewCartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _viewCartScale = Tween<double>(
      begin: 1,
      end: 1.13,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_viewCartController);

    _viewCartController.addStatusListener((s) {
      if (!mounted) return;
      try {
        if (!bounceActive) {
          if (_viewCartController.isAnimating) {
            _viewCartController.stop(canceled: true);
            _viewCartController.reset();
          }
          return;
        }

        if (s == AnimationStatus.completed) {
          _viewCartController.reverse();
        } else if (s == AnimationStatus.dismissed) {
          _viewCartController.forward();
        }
      } catch (_) {}
    });

    _maintenanceListener = _handleMaintenanceTick;
    KioskMemoryService.instance.maintenanceTick.addListener(
      _maintenanceListener!,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _stopCartAnimations();
    _cartBounceController.dispose();
    _viewCartController.dispose();
    if (_maintenanceListener != null) {
      KioskMemoryService.instance.maintenanceTick.removeListener(
        _maintenanceListener!,
      );
    }
    super.dispose();
  }

  @override
  void deactivate() {
    _stopCartAnimations();
    super.deactivate();
  }

  int get totalItems => displayedItems;
  int get totalPrice => displayedPrice;

  void _handleAddToCart(
    int id,
    String name,
    String category,
    int price,
    String image,
    int qty,
    Map<String, dynamic>? variation,
    List<Map<String, dynamic>> modifiers,
    Rect? imageRect,
  ) {
    final int takeAwayCharge = _takeAwayChargeForId(id);
    final idx = cart.indexWhere(
      (c) =>
          c["id"] == id &&
          c["variation"]?["id"] == variation?["id"] &&
          _sameModifiers(c["modifiers"], modifiers),
    );

    final totalForProduct = cart.fold<int>(
      0,
      (sum, item) => sum + (item["id"] == id ? _asInt(item["qty"]) : 0),
    );
    final delta = qty - totalForProduct;

    if (delta != 0) {
      if (idx != -1) {
        final newEntryQty = _asInt(cart[idx]["qty"]) + delta;
        if (newEntryQty <= 0) {
          cart.removeAt(idx);
        } else {
          cart[idx]["qty"] = newEntryQty;
          cart[idx]["category"] ??= category;
          cart[idx]["take_away_charge"] = takeAwayCharge;
        }
      } else if (delta > 0) {
        cart.add({
          "id": id,
          "name": name,
          "category": category,
          "price": price,
          "image": image,
          "qty": delta,
          "variation": variation,
          "modifiers": modifiers,
          "take_away_charge": takeAwayCharge,
        });
      } else {
        final anyIdx = cart.lastIndexWhere((c) => c["id"] == id);
        if (anyIdx != -1) {
          final newEntryQty = _asInt(cart[anyIdx]["qty"]) + delta;
          if (newEntryQty <= 0) {
            cart.removeAt(anyIdx);
          } else {
            cart[anyIdx]["qty"] = newEntryQty;
            cart[anyIdx]["category"] ??= category;
            cart[anyIdx]["take_away_charge"] = takeAwayCharge;
          }
        }
      }
    }

    displayedItems = cart.fold<int>(
      0,
      (sum, item) => sum + _asInt(item["qty"]),
    );

    displayedPrice = cart.fold<int>(
      0,
      (sum, item) => sum + (_asInt(item["price"]) * _asInt(item["qty"])),
    );

    // Flying add-to-cart animation removed per request.

    if (displayedItems > 0) {
      bounceActive = KioskConfig.enableDecorativeAnimations;
      if (KioskConfig.enableDecorativeAnimations) {
        _viewCartController.forward(from: 0);
      }
    } else {
      bounceActive = false;
      if (_viewCartController.isAnimating) {
        _viewCartController.stop(canceled: true);
        _viewCartController.reset();
      }
    }

    _refreshRecommendations();
    setState(() {});
  }

  void restartHomePage() {
    setState(() {
      cart.clear();
      displayedItems = 0;
      displayedPrice = 0;
      bounceActive = false;
      if (_viewCartController.isAnimating) {
        _viewCartController.stop(canceled: true);
        _viewCartController.reset();
      }
    });

    if (kIsWeb) {
      Navigator.of(context, rootNavigator: true).push(
        fastPageRoute((_) => const CustomerBlockScreen()),
      );
      return;
    }

    if (!isTabletContext(context)) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        fastPageRoute((_) => const CustomerBlockScreen()),
        (_) => false,
      );
      return;
    }

    setState(() {
      homeKey = UniqueKey();
      displayedItems = 0;
      displayedPrice = 0;
      bounceActive = false;
      if (_viewCartController.isAnimating) {
        _viewCartController.stop(canceled: true);
        _viewCartController.reset();
      }
    });
  }

  /// CLEAR CART
  void _clearAllPopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_sweep_outlined,
                size: 32,
                color: Colors.red.shade600,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Clear Cart?",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        content: const Text(
          "This will remove all items from your cart.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 20),
        actions: [
          SizedBox(
            width: 140,
            height: 42,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                "CANCEL",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            height: 42,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  cart.clear();
                  displayedItems = 0;
                  displayedPrice = 0;
                  homeKey = UniqueKey();
                  bounceActive = false;
                  _stopCartAnimations();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                "CLEAR ALL",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// REMOVE FLY OVERLAY
  void _removeOverlay() {
    _flyTimeoutTimer?.cancel();
    _flyTimeoutTimer = null;
    if (_flyController?.isAnimating ?? false) {
      _flyController?.stop(canceled: true);
    }
    _flyController?.dispose();
    _flyController = null;
    _flyAnim = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _stopCartAnimations() {
    _flyTimeoutTimer?.cancel();
    _flyTimeoutTimer = null;
    if (_flyController?.isAnimating ?? false) {
      _flyController?.stop(canceled: true);
    }
    _flyController?.dispose();
    _flyController = null;
    _flyAnim = null;
    if (_cartBounceController.isAnimating) {
      _cartBounceController.stop(canceled: true);
      _cartBounceController.reset();
    }
    if (_viewCartController.isAnimating) {
      _viewCartController.stop(canceled: true);
      _viewCartController.reset();
    }
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _handleMaintenanceTick() {
    if (!mounted) return;
    try {
      if (bounceActive) {
        _viewCartController.reset();
        _viewCartController.forward();
      }
      if (_cartBounceController.isAnimating) {
        _cartBounceController.reset();
        _cartBounceController.forward();
      }
      _removeOverlay();
    } catch (_) {}
  }

  double _quadBezier(double t, double a, double b, double c) {
    final mt = 1 - t;
    return mt * mt * a + 2 * mt * t * b + t * t * c;
  }

  /// FLY IMAGE → CART ICON
  void startFlyAnimationFromRect({
    required Rect imageRect,
    required String imageUrl,
  }) {
    if (!mounted) return;
    final normalizedImageUrl = normalizeImageUrl(imageUrl);
    if (normalizedImageUrl.isEmpty) {
      _finishFlyAnimation(force: true);
      return;
    }
    final start = imageRect.center;

    final cartRect = _cartIconRect;
    if (cartRect == null) return;

    final end = cartRect.center;

    final control = Offset(
      (start.dx + end.dx) / 2,
      min(start.dy, end.dy) - 140,
    );

    _removeOverlay();

    if (_flyController?.isAnimating ?? false) {
      _flyController?.stop(canceled: true);
    }
    _flyController?.dispose();

    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _flyAnim = CurvedAnimation(
      parent: _flyController!,
      curve: Curves.easeInOut,
    );

    _overlayEntry = OverlayEntry(
      builder: (_) => IgnorePointer(
        ignoring: true,
        child: AnimatedBuilder(
          animation: _flyAnim!,
          builder: (_, __) {
            final t = _flyAnim!.value;
            final x = _quadBezier(t, start.dx, control.dx, end.dx);
            final y = _quadBezier(t, start.dy, control.dy, end.dy);

            final size = lerpDouble(48, 20, t)!;
            final opacity = lerpDouble(1, 0, t)!;

            final dpr = MediaQuery.of(context).devicePixelRatio;
            final cacheSize = (size * dpr).round().clamp(1, 1024);
            return Positioned(
              left: x - size / 2,
              top: y - size / 2,
              child: Opacity(
                opacity: opacity,
                child: AppNetworkImage(
                  url: normalizedImageUrl,
                  width: size,
                  height: size,
                  cacheWidth: cacheSize,
                  cacheHeight: cacheSize,
                  fallback: const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      ),
    );

    final overlay = Overlay.of(context);
    overlay.insert(_overlayEntry!);

    final duration =
        _flyController!.duration ?? const Duration(milliseconds: 900);
    _flyTimeoutTimer?.cancel();
    _flyTimeoutTimer = Timer(duration + const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _finishFlyAnimation(force: true);
    });

    _flyController!.forward().whenComplete(() {
      if (!mounted) return;
      _finishFlyAnimation();
    });
  }

  void _finishFlyAnimation({bool force = false}) {
    _flyTimeoutTimer?.cancel();
    _flyTimeoutTimer = null;
    if (force && (_flyController?.isAnimating ?? false)) {
      _flyController?.stop(canceled: true);
    }
    _removeOverlay();
    if (!mounted) return;
    if (KioskConfig.enableDecorativeAnimations) {
      _cartBounceController.forward(from: 0);
    }

    if (displayedItems > 0) {
      bounceActive = KioskConfig.enableDecorativeAnimations;
      if (KioskConfig.enableDecorativeAnimations) {
        _viewCartController.forward(from: 0);
      }
    }
  }

  // ================= MAIN UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // We remove the bottomSheet property entirely because it spans 100% width.
      // Instead, we build the bottom bar as part of the body.
      body: Column(
        children: [
          // 1. THE MAIN CONTENT (HomePage or CartPage)
          Expanded(
            child: RepaintBoundary(
              // IndexedStack keeps Home and Cart alive so tab changes do not
              // fetch products again. RepaintBoundary also keeps cart updates
              // from repainting the whole menu surface on web.
              child: IndexedStack(
                index: currentIndex,
                children: [
                  HomePage2(
                    key: homeKey,
                    onRestart: restartHomePage,
                    onViewCart: () => setState(() => currentIndex = 1),
                    onClearCart: _clearAllPopup,
                    onCartIconRect: (rect) => _cartIconRect = rect,
                    isActive: currentIndex == 0,
                    showBottomBar: false,
                    onAddToCart: (
                      int id,
                      String name,
                      String category,
                      int price,
                      String image,
                      int qty,
                      Map<String, dynamic>? variation,
                      List<Map<String, dynamic>> modifiers,
                      Rect? imageRect,
                    ) {
                      _handleAddToCart(
                        id,
                        name,
                        category,
                        price,
                        image,
                        qty,
                        variation,
                        modifiers,
                        imageRect,
                      );
                    },
                    onProductsLoaded: (List<dynamic> p1) {
                      final signature = _buildProductsSignature(p1);
                      if (signature == _productsSignature) return;
                      setState(
                        () {
                          _productsSignature = signature;
                          _productsRaw = p1;
                          _rebuildTakeAwayChargeMap(p1);
                          _refreshRecommendations();
                        },
                      );
                    },
                    getQtyForProduct: getQtyForProduct,
                    cart: cart,
                  ),
                  CartPage(
                    cart: cart,
                    recommendedProducts: recommendedProducts,
                    isActive: currentIndex == 1,
                    orderType: widget.orderType,
                    onAddRecommended: _handleAddToCart,
                    onBack: () => setState(() => currentIndex = 0),
                    onStartOver: restartHomePage,
                    onCartUpdated: () {
                      setState(() {
                        _refreshRecommendations();
                        displayedItems = cart.fold(
                          0,
                          (s, i) => s + _asInt(i["qty"]),
                        );
                        displayedPrice = cart.fold(
                          0,
                          (s, i) => s + (_asInt(i["qty"]) * _asInt(i["price"])),
                        );
                        if (displayedItems == 0) {
                          bounceActive = false;
                          if (_viewCartController.isAnimating) {
                            _viewCartController.stop(canceled: true);
                            _viewCartController.reset();
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: currentIndex == 0 ? _bottomBar() : null,
    );
  }

  // ================= BOTTOM BAR =================
  Widget _bottomBar() {
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    final int totalItems = cart.fold<int>(
      0,
      (sum, item) => sum + _asInt(item["qty"]),
    );
    final int totalPrice = cart.fold<int>(
      0,
      (sum, item) => sum + (_asInt(item["qty"]) * _asInt(item["price"])),
    );
    final bool hasItems = totalItems > 0;

    return Container(
      height: isTablet ? 86 : 78,
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 16 : 12,
        vertical: isTablet ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: const Color(0xFFEAEFF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: isTablet ? 122 : 96,
            child: OutlinedButton.icon(
              onPressed: hasItems ? _clearAllPopup : _showEmptyCartDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF9F342C),
                side: const BorderSide(color: Color(0xFFDFCCC3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 10 : 8,
                  vertical: isTablet ? 10 : 8,
                ),
              ),
              icon: Icon(
                Icons.delete_outline_rounded,
                size: isTablet ? 18 : 16,
              ),
              label: Text(
                "CLEAR",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: isTablet ? 13 : 11,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 12 : 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$totalItems items",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF646F7D),
                      fontWeight: FontWeight.w700,
                      fontSize: isTablet ? 13 : 11,
                    ),
                  ),
                  Text(
                    "₹$totalPrice",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: isTablet ? 26 : 19,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: isTablet ? 188 : 148,
            child: ScaleTransition(
              scale: _viewCartScale,
              child: ElevatedButton(
                onPressed: () {
                  if (!hasItems) {
                    _showEmptyCartDialog();
                    return;
                  }
                  setState(() => currentIndex = 1);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F9D48),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: const Color(0xFF2F9D48).withOpacity(0.28),
                  padding: EdgeInsets.symmetric(
                    vertical: isTablet ? 12 : 10,
                    horizontal: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ScaleTransition(
                        scale: _cartBounceAnim,
                        child: Builder(
                          builder: (ctx) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              final render = ctx.findRenderObject();
                              if (render is! RenderBox || !render.attached) {
                                return;
                              }
                              _cartIconRect =
                                  render.localToGlobal(Offset.zero) &
                                      render.size;
                            });
                            return Icon(
                              Icons.shopping_cart_rounded,
                              size: isTablet ? 20 : 16,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "VIEW CART",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: isTablet ? 15 : 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Moved the Dialog logic here to keep the build method clean
  void _showEmptyCartDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 32,
                color: Colors.orange.shade600,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Cart is Empty",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        content: const Text(
          "Please add a product before viewing the cart.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.black54, height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 20),
        actions: [
          SizedBox(
            width: 160,
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                "ADD ITEMS",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int calculateCartTotal(List<Map<String, dynamic>> cart) {
    int total = 0;

    for (final item in cart) {
      final int qty = item["qty"] ?? 1;

      final int basePrice = item["price"] ?? 0;

      // variation price (safe)
      final int variationPrice = item["variation"]?["price"] ?? 0;

      // modifiers total price (safe)
      final int modifiersPrice = (item["modifiers"] as List?)?.fold<int>(
            0,
            (sum, m) => sum + ((m["price"] ?? 0) as int),
          ) ??
          0;

      total += (basePrice + variationPrice + modifiersPrice) * qty;
    }

    return total;
  }
}
