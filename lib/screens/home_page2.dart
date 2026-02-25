import 'dart:async';
import 'dart:convert';

import 'package:api_selfxo_project/background_image/background_image.dart';
import 'package:api_selfxo_project/core/connectivity_service.dart';
import 'package:api_selfxo_project/core/kiosk_config.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/modules/product_model.dart';
import 'package:api_selfxo_project/widget/product_card.dart';
import 'best_selling.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SelectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    // This value controls how "deep" the curve goes into the red area
    const double curveDepth = 25.0;

    // Start at top right
    path.moveTo(size.width, 0);

    // 1. Top Outward Curve (Concave)
    path.quadraticBezierTo(
      size.width,
      curveDepth,
      size.width - curveDepth,
      curveDepth,
    );

    // 2. Main Body with rounded inner corners
    path.lineTo(curveDepth, curveDepth);
    path.quadraticBezierTo(0, curveDepth, 0, curveDepth * 2);
    path.lineTo(0, size.height - (curveDepth * 2));
    path.quadraticBezierTo(
      0,
      size.height - curveDepth,
      curveDepth,
      size.height - curveDepth,
    );
    path.lineTo(size.width - curveDepth, size.height - curveDepth);

    // 3. Bottom Outward Curve (Concave)
    path.quadraticBezierTo(
      size.width,
      size.height - curveDepth,
      size.width,
      size.height,
    );

    path.lineTo(size.width, 0);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HomePage2 extends StatefulWidget {
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
  )
  onAddToCart;
  final ValueChanged<Rect?> onCartIconRect;
  final Function(List<dynamic>) onProductsLoaded;
  final VoidCallback onRestart;
  final VoidCallback onViewCart;
  final VoidCallback onClearCart;
  final List<Map<String, dynamic>> cart;
  final int Function(int productId) getQtyForProduct;
  final bool isActive;

  const HomePage2({
    super.key,
    required this.onAddToCart,
    required this.onRestart,
    required this.onViewCart,
    required this.onClearCart,
    required this.onCartIconRect,
    required this.onProductsLoaded,
    required this.cart,
    required this.getQtyForProduct,
    required this.isActive,
  });

  @override
  State<HomePage2> createState() => _HomePage2State();
}

class _HomePage2State extends State<HomePage2> with TickerProviderStateMixin {
  final Map<int, List<Map<String, dynamic>>> variationsMap = {};
  final Map<int, List<Map<String, dynamic>>> modifiersMap = {};
  Rect? _lastCartIconRect;
  List<dynamic> _rawProducts = [];
  final Map<int, Map<String, dynamic>> _productOverrides = {};
  static const String _overridesKey = "admin_product_overrides";

  void _goToWelcome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  List<ProductModel> allProducts = [];
  List<String> categories = [];
  Map<String, String> categoryImages = {};
  bool isLoading = true;
  bool hasError = false;
  String errorMessage = "Failed to load products";
  int selectedIndex = 0;
  int _activeCategoryIndex = 0;
  String searchQuery = "";

  final TextEditingController searchCtrl = TextEditingController();
  final ScrollController scrollCtrl = ScrollController();
  // Separate scroll for categories

  final ScrollController _categoryScrollController = ScrollController();
  bool _showScrollArrow = false;
  bool _showProductScrollHint = false;
  late AnimationController _leftScrollHintController;
  Timer? _categorySyncTimer;
  final Map<String, BuildContext> _leftCategoryContexts = {};
  final Map<String, BuildContext> _rightCategoryContexts = {};
  VoidCallback? _categoryScrollListener;
  Timer? _retryTimer;
  bool _loadingProducts = false;
  VoidCallback? _onlineListener;
  bool _showScrollToTop = false;
  VoidCallback? _maintenanceListener;
  VoidCallback? _mediaRefreshListener;

  // Bottom bar animations
  late AnimationController _cartBounceController;
  late Animation<double> _cartBounceAnim;
  late AnimationController _viewCartController;
  late Animation<double> _viewCartScale;
  int _lastItemCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();

    ConnectivityService.instance.start();
    _onlineListener = () {
      final online = ConnectivityService.instance.isOnline.value;
      if (online && hasError) {
        _retryTimer?.cancel();
        if (mounted) {
          setState(() {
            hasError = false;
            isLoading = true;
          });
        }
        _loadProducts();
      }
    };
    ConnectivityService.instance.isOnline.addListener(_onlineListener!);

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
        if (_totalItems() == 0) {
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

    _leftScrollHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (KioskConfig.enableDecorativeAnimations) {
      _leftScrollHintController.repeat(reverse: true);
    }

    _categoryScrollListener = () {
      if (_categoryScrollController.hasClients) {
        final pos = _categoryScrollController.position;

        // Show only when the list is scrollable and the user is still at top.
        final bool shouldShow =
            pos.maxScrollExtent > 0 && pos.pixels < (pos.maxScrollExtent - 4);

        if (_showScrollArrow != shouldShow) {
          setState(() => _showScrollArrow = shouldShow);
        }
      }
    };
    _categoryScrollController.addListener(_categoryScrollListener!);

    // Product list scroll listener (add once to avoid duplicates)
    scrollCtrl.addListener(_onProductScroll);

    // Check on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_categoryScrollController.hasClients) {
        setState(() {
          _showScrollArrow =
              _categoryScrollController.position.maxScrollExtent > 0 &&
              _categoryScrollController.position.pixels <
                  (_categoryScrollController.position.maxScrollExtent - 4);
        });
      }
    });

    _lastItemCount = _totalItems();
    if (_lastItemCount > 0) {
      _cartBounceController.forward(from: 0);
      _viewCartController.forward(from: 0);
    }

    _maintenanceListener = _handleMaintenanceTick;
    KioskMemoryService.instance.maintenanceTick.addListener(
      _maintenanceListener!,
    );
    _mediaRefreshListener = _handleMediaRefreshTick;
    KioskMemoryService.instance.mediaRefreshTick.addListener(
      _mediaRefreshListener!,
    );
  }

  @override
  void dispose() {
    widget.onCartIconRect(null);
    // ✅ ALWAYS dispose controllers to prevent memory leaks
    scrollCtrl.removeListener(_onProductScroll);
    searchCtrl.dispose();
    if (_cartBounceController.isAnimating) {
      _cartBounceController.stop(canceled: true);
    }
    if (_viewCartController.isAnimating) {
      _viewCartController.stop(canceled: true);
    }
    if (_leftScrollHintController.isAnimating) {
      _leftScrollHintController.stop(canceled: true);
    }
    _cartBounceController.dispose();
    _viewCartController.dispose();
    _leftScrollHintController.dispose();
    if (_categoryScrollListener != null) {
      _categoryScrollController.removeListener(_categoryScrollListener!);
    }
    _categoryScrollController.dispose();

    if (_onlineListener != null) {
      ConnectivityService.instance.isOnline.removeListener(_onlineListener!);
    }
    if (_maintenanceListener != null) {
      KioskMemoryService.instance.maintenanceTick.removeListener(
        _maintenanceListener!,
      );
    }
    if (_mediaRefreshListener != null) {
      KioskMemoryService.instance.mediaRefreshTick.removeListener(
        _mediaRefreshListener!,
      );
    }
    _retryTimer?.cancel();
    _categorySyncTimer?.cancel();
    super.dispose();
  }

  @override
  void deactivate() {
    _retryTimer?.cancel();
    _categorySyncTimer?.cancel();
    if (_cartBounceController.isAnimating) {
      _cartBounceController.stop(canceled: true);
    }
    if (_viewCartController.isAnimating) {
      _viewCartController.stop(canceled: true);
    }
    if (_leftScrollHintController.isAnimating) {
      _leftScrollHintController.stop(canceled: true);
    }
    super.deactivate();
  }

  @override
  void didUpdateWidget(covariant HomePage2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = _totalItems();
    if (count > _lastItemCount && KioskConfig.enableDecorativeAnimations) {
      _cartBounceController.forward(from: 0);
      _viewCartController.forward(from: 0);
    }
    if (count == 0) {
      if (_viewCartController.isAnimating) {
        _viewCartController.stop(canceled: true);
        _viewCartController.reset();
      }
    }
    _lastItemCount = count;

    if (!widget.isActive && oldWidget.isActive) {
      _retryTimer?.cancel();
    }
    if (widget.isActive != oldWidget.isActive) {
      if (!widget.isActive) {
        if (KioskConfig.enableDecorativeAnimations) {
          _leftScrollHintController.stop(canceled: true);
        }
        if (_cartBounceController.isAnimating) {
          _cartBounceController.stop(canceled: true);
        }
        if (_viewCartController.isAnimating) {
          _viewCartController.stop(canceled: true);
        }
      } else if (KioskConfig.enableDecorativeAnimations &&
          !_leftScrollHintController.isAnimating) {
        _leftScrollHintController.repeat(reverse: true);
      }
    }
  }

  Future<void> _loadProducts() async {
    if (_loadingProducts) return;
    _loadingProducts = true;
    _retryTimer?.cancel();
    if (mounted) {
      setState(() {
        isLoading = true;
        hasError = false;
      });
    }
    try {
      await _loadProductOverrides();
      final res = await KioskApi().getProducts();

      final List raw = res.data["products"] ?? [];
      _rawProducts = raw;
      widget.onProductsLoaded(raw);

      final parsed = await compute(_parseProductsIsolate, raw);
      if (!mounted) return;

      final productMaps = List<Map<String, dynamic>>.from(
        parsed["products"] ?? const [],
      );
      _applyOverridesToProductMaps(productMaps);
      final tempProducts = productMaps
          .map(
            (p) => ProductModel(
              id: p["id"],
              name: p["name"] ?? "",
              category: p["category"] ?? "Others",
              price: int.tryParse(p["price"].toString()) ?? 0,
              image: p["image"] ?? "",
              type: p["type"],
            ),
          )
          .toList();

      final tempCategories = List<String>.from(
        parsed["categories"] ?? const <String>[],
      );
      if (_productOverrides.isNotEmpty) {
        final overrideCats = _productOverrides.values
            .map((o) => o["category_name"] ?? o["category"])
            .where((o) => o != null && o.toString().trim().isNotEmpty)
            .map((o) => o.toString())
            .toSet();
        for (final c in overrideCats) {
          if (!tempCategories.contains(c)) {
            tempCategories.add(c);
          }
        }
      }
      if (tempCategories.isEmpty || tempCategories.first != "All") {
        tempCategories.insert(0, "All");
      }

      final tempCatImages = Map<String, String>.from(
        parsed["categoryImages"] ?? const <String, String>{},
      );

      variationsMap
        ..clear()
        ..addAll(
          (parsed["variationsMap"] as Map? ?? const {}).map(
            (k, v) => MapEntry(
              int.tryParse(k.toString()) ?? 0,
              List<Map<String, dynamic>>.from(v ?? const []),
            ),
          )..removeWhere((key, value) => key == 0),
        );

      modifiersMap
        ..clear()
        ..addAll(
          (parsed["modifiersMap"] as Map? ?? const {}).map(
            (k, v) => MapEntry(
              int.tryParse(k.toString()) ?? 0,
              List<Map<String, dynamic>>.from(v ?? const []),
            ),
          )..removeWhere((key, value) => key == 0),
        );

      // 2. Update UI with data
      if (!mounted) return;
      setState(() {
        allProducts = tempProducts;
        categories = tempCategories;
        categoryImages = tempCatImages;
        _leftCategoryContexts.clear();
        _rightCategoryContexts.clear();
        isLoading = false;
        hasError = false;
        if (selectedIndex >= categories.length) {
          selectedIndex = 0;
        }
        if (_activeCategoryIndex >= categories.length) {
          _activeCategoryIndex = 0;
        }
      });

      // 3. 🔥 THE KEY UPDATE: Check for scrollability AFTER rendering
      // We use a post-frame callback to let Flutter finish building the list
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          // Check Left Category Bar
          if (_categoryScrollController.hasClients) {
            _showScrollArrow =
                _categoryScrollController.position.maxScrollExtent > 0;
          }
          // Check Right Product Area
          if (scrollCtrl.hasClients) {
            _showProductScrollHint =
                scrollCtrl.position.maxScrollExtent > 0 &&
                scrollCtrl.position.pixels <= 4;
          }
        });
        _precacheProductImages();
      });
    } catch (e) {
      final online = ConnectivityService.instance.isOnline.value;
      final hasCachedData = allProducts.isNotEmpty;

      if (!mounted) return;

      if (online) {
        // If internet is back, don't block UI—just retry.
        setState(() {
          hasError = false;
          isLoading = !hasCachedData;
        });
        _retryTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) _loadProducts();
        });
      } else {
        // Offline: keep showing existing data if we have it
        setState(() {
          errorMessage = "Kiosk is Offline";
          hasError = !hasCachedData;
          isLoading = false;
        });
      }
    } finally {
      _loadingProducts = false;
    }
  }

  void _precacheProductImages() {
    if (!mounted) return;
    final context = this.context;
    final int maxItems = 24;
    final productsToCache = allProducts.take(maxItems);
    for (final p in productsToCache) {
      final url = p.image.trim();
      if (url.isNotEmpty) {
        precacheImage(NetworkImage(url), context);
      }
    }
    int cached = 0;
    for (final url in categoryImages.values) {
      if (cached >= 8) break;
      final u = url.trim();
      if (u.isEmpty) continue;
      precacheImage(NetworkImage(u), context);
      cached++;
    }
  }

  void _onProductScroll() {
    if (!scrollCtrl.hasClients) return;
    final pos = scrollCtrl.position;
    final bool shouldShow = pos.maxScrollExtent > 0 && pos.pixels <= 4;
    if (_showProductScrollHint != shouldShow) {
      setState(() => _showProductScrollHint = shouldShow);
    }
    final bool showTop = pos.pixels > 240;
    if (_showScrollToTop != showTop) {
      setState(() => _showScrollToTop = showTop);
    }
    _scheduleCategorySync();
  }

  void _scheduleCategorySync() {
    if (selectedIndex != 0) return;
    if (_categorySyncTimer?.isActive ?? false) return;
    _categorySyncTimer = Timer(const Duration(milliseconds: 120), () {
      _categorySyncTimer = null;
      if (!mounted) return;
      _updateActiveCategoryFromScroll();
    });
  }

  void _updateActiveCategoryFromScroll() {
    if (!scrollCtrl.hasClients) return;
    if (categories.length <= 1) return;

    final sectionCategories = _sectionCategories();
    if (sectionCategories.isEmpty) return;

    final currentOffset = scrollCtrl.offset;
    double? firstOffset;
    double bestOffset = -double.infinity;
    int bestIndex = 0;

    for (final cat in sectionCategories) {
      final ctx = _rightCategoryContexts[cat];
      if (ctx == null) continue;
      final render = ctx.findRenderObject();
      if (render == null || !render.attached) continue;
      final viewport = RenderAbstractViewport.of(render);
      if (viewport == null) continue;

      final offset = viewport.getOffsetToReveal(render, 0).offset;
      firstOffset ??= offset;

      if (offset <= currentOffset + 6 && offset > bestOffset) {
        bestOffset = offset;
        bestIndex = categories.indexOf(cat);
      }
    }

    if (firstOffset != null && currentOffset < (firstOffset! - 8)) {
      bestIndex = 0;
    }

    if (bestIndex != _activeCategoryIndex && mounted) {
      setState(() => _activeCategoryIndex = bestIndex);
      _scrollLeftCategoryIntoView(bestIndex);
    }
  }

  void _scrollLeftCategoryIntoView(int index) {
    if (index < 0 || index >= categories.length) return;
    final ctx = _leftCategoryContexts[categories[index]];
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      alignment: 0.5,
      curve: Curves.easeOut,
    );
  }

  void _handleMaintenanceTick() {
    if (!mounted) return;
    try {
      if (KioskConfig.enableDecorativeAnimations) {
        if (_leftScrollHintController.isAnimating) {
          _leftScrollHintController.reset();
          _leftScrollHintController.repeat(reverse: true);
        }
        if (_viewCartController.isAnimating) {
          _viewCartController.reset();
          _viewCartController.forward();
        }
        if (_cartBounceController.isAnimating) {
          _cartBounceController.reset();
          _cartBounceController.forward();
        }
      }
      _categorySyncTimer?.cancel();
    } catch (_) {}
  }

  void _handleMediaRefreshTick() {
    if (!mounted) return;
    if (_loadingProducts) return;
    _loadProducts();
  }

  Future<void> _loadProductOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_overridesKey);
      if (raw == null || raw.isEmpty) {
        _productOverrides.clear();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _productOverrides
        ..clear()
        ..addAll(
          decoded.map(
            (k, v) => MapEntry(
              int.tryParse(k.toString()) ?? 0,
              v is Map
                  ? Map<String, dynamic>.from(v as Map)
                  : <String, dynamic>{},
            ),
          )..removeWhere((key, value) => key == 0),
        );
    } catch (_) {}
  }

  void _applyOverridesToProductMaps(List<Map<String, dynamic>> productMaps) {
    if (_productOverrides.isEmpty) return;
    final Set<int> seenIds = {};
    for (final p in productMaps) {
      final id = p["id"];
      final pid = id is int ? id : int.tryParse(id?.toString() ?? "");
      if (pid == null) continue;
      seenIds.add(pid);
      final override = _productOverrides[pid];
      if (override == null) continue;
      final name = override["item_name"] ?? override["name"];
      if (name != null && name.toString().trim().isNotEmpty) {
        p["name"] = name;
      }
      final price = override["price"] ?? override["item_price"];
      if (price != null) {
        p["price"] = price;
      }
      final category = override["category_name"] ?? override["category"];
      if (category != null && category.toString().trim().isNotEmpty) {
        p["category"] = category;
      }
      final type = override["type"];
      if (type != null) {
        p["type"] = type;
      }
      final image =
          override["item_photo_url"] ?? override["image"];
      if (image != null && image.toString().trim().isNotEmpty) {
        p["image"] = image;
      }
    }

    // Add missing items from overrides (newly created products)
    for (final entry in _productOverrides.entries) {
      if (seenIds.contains(entry.key)) continue;
      final o = entry.value;
      final name = (o["item_name"] ?? o["name"] ?? "").toString();
      final price = o["price"] ?? o["item_price"] ?? 0;
      if (name.trim().isEmpty) continue;
      productMaps.add({
        "id": entry.key,
        "name": name,
        "category": o["category_name"] ?? o["category"] ?? "Others",
        "price": price,
        "image": o["item_photo_url"] ?? o["image"] ?? "",
        "type": o["type"],
      });
    }
  }

  List<String> _sectionCategories() {
    return categories.where((c) => c != "All").toList();
  }

  List<ProductModel> _filterProductsForCategory(String? category) {
    return allProducts.where((p) {
      final matchesCategory = category == null || p.category == category;
      if (!matchesCategory) return false;
      if (searchQuery.isEmpty) return true;
      return p.name.toLowerCase().contains(searchQuery);
    }).toList();
  }

  bool _debugIsTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value == 1 || value == 1.0;
    final s = value.toString().toLowerCase().trim();
    if (s == "1" || s == "true" || s == "yes" || s == "y") return true;
    final parsed = num.tryParse(s);
    return parsed == 1 || parsed == 1.0;
  }

  String _debugNormKey(String k) =>
      k.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "");

  dynamic _debugReadKey(Map? item, List<String> keys) {
    if (item == null) return null;
    for (final key in keys) {
      if (item.containsKey(key)) return item[key];
    }
    final wanted = keys.map(_debugNormKey).toSet();
    for (final entry in item.entries) {
      final nk = _debugNormKey(entry.key.toString());
      if (wanted.contains(nk)) return entry.value;
    }
    return null;
  }

  int _debugToInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }

  List<Map<String, dynamic>> _collectRecommendationDebugItems() {
    final List<Map<String, dynamic>> out = [];
    for (final category in _rawProducts) {
      if (category is! Map) continue;
      final catName =
          category["category_name"] ?? category["name"] ?? "Category";
      final items = category["items"];
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        final rec = _debugReadKey(item, [
          "is_recommended",
          "isRecommended",
          "recommended",
          "is_recommend",
          "is_recommanded",
        ]);
        final id = _debugToInt(
          _debugReadKey(item, ["id", "Id", "ID", "item_id", "itemId"]),
        );
        final name = (item["item_name"] ?? item["name"] ?? "").toString();
        out.add({
          "id": id,
          "name": name,
          "category": catName.toString(),
          "recRaw": rec,
          "isRecommended": _debugIsTruthy(rec),
        });
      }
    }
    return out;
  }

  void _showRecommendedDebug() {
    if (!kDebugMode) return;
    final data = _collectRecommendationDebugItems();
    final int total = data.length;
    final int recCount = data.where((e) => e["isRecommended"] == true).length;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        "Recommended Debug",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text("Total items: $total"),
                  Text("Recommended (is_recommended=1): $recCount"),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Expanded(
                    child: data.isEmpty
                        ? const Center(child: Text("No items found"))
                        : ListView.separated(
                            itemCount: data.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final row = data[i];
                              final bool isRec = row["isRecommended"] == true;
                              return ListTile(
                                dense: true,
                                title: Text(
                                  "${row["name"]} (id: ${row["id"]})",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  "Cat: ${row["category"]} | raw: ${row["recRaw"]}",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Icon(
                                  isRec ? Icons.check_circle : Icons.cancel,
                                  color: isRec
                                      ? const Color(0xFF1B8E3E)
                                      : Colors.red,
                                  size: 18,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (hasError) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF9F342C)),
        ),
      );
    }

    final bool sectionMode = selectedIndex == 0;
    final filtered = sectionMode
        ? _filterProductsForCategory(null)
        : _filterProductsForCategory(categories[selectedIndex]);

    final width = MediaQuery.of(context).size.width;
    final bool isTablet = width > 600;
    final gridCount = width < 600
        ? 2
        : width < 900
        ? 3
        : 4;

    // 🎯 FIX: We wrap the whole body in a Row so the Left Bar is independent
    // of the main content scroll and spans the full height.
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ================= LEFT BAR (FULL HEIGHT) =================
              _buildLeftCategoryBar(),

              // ================= RIGHT CONTENT AREA =================
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: _buildRightArea(filtered, gridCount),
                ),
              ),
            ],
          ),
          if (_showScrollToTop)
            Positioned(
              right: 18,
              bottom: (isTablet ? 110 : 96),
              child: FloatingActionButton(
                onPressed: () {
                  if (!scrollCtrl.hasClients) return;
                  scrollCtrl.animateTo(
                    0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                  );
                },
                backgroundColor: const Color(0xFF9F342C),
                elevation: 4,
                child: const Icon(
                  Icons.keyboard_arrow_up,
                  color: Color.fromARGB(255, 255, 255, 255),
                  size: 55,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeftCategoryBar() {
    // Determine device type
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final double radius = isTablet ? 35 : 28;
    final double scale = isTablet ? 1.4 : 0.8;

    return Container(
      // Updated width logic: 140 for Tablet, 100 for Mobile
      width: isTablet ? 170 : 100,
      color: const Color.fromARGB(255, 120, 33, 27),
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 20),
              // Adjusted logo height for mobile
              InkWell(
                onTap: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    (_) => false,
                  );
                },
                onLongPress: kDebugMode ? _showRecommendedDebug : null,
                child: Image.asset(
                  "assets/self.png",
                  height: isTablet ? 50 : 40,
                ),
              ),
              const SizedBox(height: 10),

              Expanded(
                child: Column(
                  children: [
                    // ================= CATEGORY LIST =================
                    Expanded(
                      child: ListView.builder(
                        controller: _categoryScrollController,
                        padding: EdgeInsets.only(bottom: isTablet ? 90 : 80),
                        itemCount: categories.length,
                        itemBuilder: (_, i) {
                          final selected = selectedIndex == 0
                              ? i == _activeCategoryIndex
                              : i == selectedIndex;
                          final catName = categories[i];
                          final double cacheScale = scale < 1 ? 1 : scale;
                          final int imageSize = (radius * 2 * cacheScale * dpr)
                              .round();
                          ImageProvider? imageProvider;
                          if (catName == "All") {
                            imageProvider = const AssetImage(
                              "assets/catall.jpg",
                            );
                          } else if (categoryImages.containsKey(catName)) {
                            imageProvider = ResizeImage(
                              NetworkImage(categoryImages[catName]!),
                              width: imageSize,
                              height: imageSize,
                            );
                          }
                          return Builder(
                            builder: (ctx) {
                              _leftCategoryContexts[catName] = ctx;
                              return GestureDetector(
                                key: ValueKey("left-cat-$catName"),
                                onTap: () {
                                  setState(() {
                                    selectedIndex = i;
                                    _activeCategoryIndex = i;
                                    searchQuery = "";
                                    searchCtrl.clear();
                                  });
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (!scrollCtrl.hasClients) return;
                                    scrollCtrl.jumpTo(0);
                                  });
                                },
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    if (selected)
                                      Positioned(
                                        top: -25,
                                        bottom: -15,
                                        left: 15,
                                        right: 0,
                                        child: CustomPaint(
                                          painter: SelectionPainter(),
                                        ),
                                      ),

                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        vertical: isTablet ? 20 : 15,
                                      ),
                                      width: double.infinity,
                                      constraints: BoxConstraints(
                                        minHeight: isTablet ? 120 : 90,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          AnimatedScale(
                                            scale: scale,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: selected
                                                      ? Colors.white
                                                      : Colors.transparent,
                                                  width: 2,
                                                ),
                                                boxShadow: selected
                                                    ? [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withOpacity(0.2),
                                                          blurRadius: 10,
                                                          offset: const Offset(
                                                            0,
                                                            5,
                                                          ),
                                                        ),
                                                      ]
                                                    : [],
                                              ),
                                              child: ClipOval(
                                                child: SizedBox(
                                                  width: radius * 2,
                                                  height: radius * 2,
                                                  child: imageProvider != null
                                                      ? Image(
                                                          image: imageProvider,
                                                          fit: BoxFit.cover,
                                                          filterQuality:
                                                              FilterQuality
                                                                  .high,
                                                        )
                                                      : Container(
                                                          color: Colors.white10,
                                                          child: Icon(
                                                            Icons.fastfood,
                                                            color:
                                                                Colors.white70,
                                                            size: isTablet
                                                                ? 32
                                                                : 24,
                                                          ),
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: isTablet ? 12 : 6),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 4,
                                                  ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  8.0,
                                                ),
                                                child: AnimatedDefaultTextStyle(
                                                  duration: const Duration(
                                                    milliseconds: 250,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: selected
                                                        ? Colors.black
                                                        : Color.fromARGB(
                                                            255,
                                                            242,
                                                            220,
                                                            188,
                                                          ),
                                                    fontSize: isTablet
                                                        ? 16
                                                        : 14,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  child: Text(
                                                    catName,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_showScrollArrow)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _leftScrollHintController,
                  builder: (_, __) {
                    return Transform.translate(
                      offset: Offset(0, 18 * _leftScrollHintController.value),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color.fromARGB(255, 255, 255, 255),
                        size: 68,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRightArea(List<ProductModel> filtered, int gridCount) {
    final double width = MediaQuery.of(context).size.width;
    final bool isTablet = width > 600;
    final bool sectionMode = selectedIndex == 0;
    final double leftBarWidth = isTablet ? 170 : 100;
    final double rightAreaWidth = (width - leftBarWidth).clamp(320, width);
    final double gridPadding = 24; // SliverPadding left + right
    final double crossAxisSpacing = isTablet ? 17 : 12;
    final double gridWidth = (rightAreaWidth - gridPadding).clamp(200, width);
    final double itemWidth =
        (gridWidth - ((gridCount - 1) * crossAxisSpacing)) / gridCount;
    final double imageHeight = itemWidth / 1.2;
    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final int imageCacheWidth = (itemWidth * dpr).round().clamp(1, 4096);
    final int imageCacheHeight = (imageHeight * dpr).round().clamp(1, 4096);
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double bottomBarHeight = isTablet ? 95 : 82;
    final double bottomSpace = bottomBarHeight + bottomInset + 16;
    return Column(
      children: [
        Padding(padding: const EdgeInsets.all(12), child: _buildSearchRow()),
        Expanded(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(overscroll: false),
                      child: CustomScrollView(
                        controller: scrollCtrl,
                        physics: const ClampingScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: BestSellingWidget(
                              products: allProducts,
                              isActive: widget.isActive,
                              onAddToCart: widget.onAddToCart,
                            ),
                          ),

                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                          if (sectionMode)
                            ..._buildCategorySections(
                              gridCount,
                              isTablet,
                              imageCacheWidth: imageCacheWidth,
                              imageCacheHeight: imageCacheHeight,
                              showHeaders: true,
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.all(12),
                              sliver: SliverGrid(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  i,
                                ) {
                                  final p = filtered[i];
                                  return ProductCardRef(
                                    id: p.id,
                                    name: p.name,
                                    category: p.category,
                                    price: p.price,
                                    imagePath: p.image,
                                    isVeg: p.isVeg,
                                    qty: widget.getQtyForProduct(p.id),
                                    onAddToCart: widget.onAddToCart,
                                    imageCacheWidth: imageCacheWidth,
                                    imageCacheHeight: imageCacheHeight,
                                    variations: variationsMap[p.id] ?? [],
                                    modifiers: modifiersMap[p.id] ?? [],
                                  );
                                }, childCount: filtered.length),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: gridCount,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: isTablet ? 17 : 12,
                                      childAspectRatio: isTablet ? 0.69 : 0.62,
                                    ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: SizedBox(height: bottomSpace),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showProductScrollHint && filtered.length > gridCount * 2)
                    const SizedBox.shrink(),
                ],
              ),
              Align(alignment: Alignment.bottomCenter, child: _bottomBar()),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCategorySections(
    int gridCount,
    bool isTablet, {
    required int imageCacheWidth,
    required int imageCacheHeight,
    required bool showHeaders,
  }) {
    final List<Widget> slivers = [];
    for (final cat in _sectionCategories()) {
      final items = _filterProductsForCategory(cat);
      if (items.isEmpty) continue;

      if (showHeaders) {
        slivers.add(
          SliverToBoxAdapter(
            child: Builder(
              builder: (ctx) {
                _rightCategoryContexts[cat] = ctx;
                return Container(
                  key: ValueKey("cat-header-$cat"),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    cat,
                    style: TextStyle(
                      fontSize: isTablet ? 22 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } else {
        slivers.add(
          SliverToBoxAdapter(
            child: Builder(
              builder: (ctx) {
                _rightCategoryContexts[cat] = ctx;
                return SizedBox(key: ValueKey("cat-spacer-$cat"), height: 10);
              },
            ),
          ),
        );
      }

      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((context, i) {
              final p = items[i];
              return ProductCardRef(
                id: p.id,
                name: p.name,
                category: p.category,
                price: p.price,
                imagePath: p.image,
                isVeg: p.isVeg,
                qty: widget.getQtyForProduct(p.id),
                onAddToCart: widget.onAddToCart,
                imageCacheWidth: imageCacheWidth,
                imageCacheHeight: imageCacheHeight,
                variations: variationsMap[p.id] ?? [],
                modifiers: modifiersMap[p.id] ?? [],
              );
            }, childCount: items.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: isTablet ? 17 : 12,
              childAspectRatio: isTablet ? 0.69 : 0.62,
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  int _totalItems() {
    return widget.cart.fold<int>(
      0,
      (sum, item) => sum + ((item["qty"] ?? 0) as int),
    );
  }

  int _totalPrice() {
    return widget.cart.fold<int>(
      0,
      (sum, item) =>
          sum + ((item["price"] ?? 0) as int) * ((item["qty"] ?? 0) as int),
    );
  }

  Widget _bottomBar() {
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double baseHeight = isTablet ? 95 : 82;
    final bool hasItems = _totalItems() > 0;
    final int totalItems = _totalItems();
    final int totalPrice = _totalPrice();

    const Color accentOrange = Color(0xFF9F342C);
    final Color cartGreen = const Color.fromARGB(255, 65, 159, 44);

    return SizedBox(
      height: baseHeight + bottomInset,
      child: Container(
        padding: EdgeInsets.only(
          left: isTablet ? 24 : 16,
          right: isTablet ? 24 : 16,
          top: 10,
          bottom: 10 + bottomInset,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(10),
            topRight: Radius.circular(10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.89),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // 1. CLEAR ACTION (Outlined)
            SizedBox(
              width: isTablet ? 130 : 110,
              height: isTablet ? 54 : 46,
              child: OutlinedButton.icon(
                onPressed: hasItems ? widget.onClearCart : _showEmptyCartDialog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color.fromARGB(255, 120, 33, 27),
                  side: const BorderSide(color: accentOrange, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: isTablet ? 24 : 18,
                  color: const Color.fromARGB(255, 120, 33, 27),
                ),
                label: Text(
                  "CLEAR",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: isTablet ? 16 : 11,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 2. TOTAL INFO (Expands to fill space)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "Your order",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: isTablet ? 13 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(1),
                          ),
                          child: Text(
                            "$totalItems",
                            style: TextStyle(
                              fontSize: isTablet ? 12 : 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "RS $totalPrice.00",
                          style: TextStyle(
                            color: const Color.fromARGB(255, 0, 0, 0),
                            fontSize: isTablet ? 18 : 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 12),

            // 3. VIEW CART BUTTON (Compact & Fixed Width)
            SizedBox(
              width: isTablet ? 180 : 140, // Fixed width prevents stretching
              child: ScaleTransition(
                scale: _viewCartScale,
                child: ElevatedButton(
                  onPressed: () {
                    if (!hasItems) {
                      _showEmptyCartDialog();
                      return;
                    }
                    widget.onViewCart();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cartGreen,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: cartGreen.withOpacity(0.4),
                    padding: const EdgeInsets.symmetric(vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    minimumSize: const Size(double.infinity, 54),
                  ),
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
                              final rect =
                                  render.localToGlobal(Offset.zero) &
                                  render.size;
                              if (rect != _lastCartIconRect) {
                                _lastCartIconRect = rect;
                                widget.onCartIconRect(rect);
                              }
                            });
                            return const Icon(
                              Icons.shopping_cart,
                              size: 18,
                              color: Colors.white,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "VIEW CART",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: isTablet ? 15 : 13,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildNoNetworkIndicator() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Colors.redAccent,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "No INTERNET",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "Offline",
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchRow() {
    return Row(
      children: [
        Flexible(
          flex: 3,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: TextField(
                controller: searchCtrl,
                onChanged: (v) => setState(() => searchQuery = v.toLowerCase()),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search),
                  hintText: "Search items...",
                  suffixIcon: searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            searchCtrl.clear();
                            setState(() => searchQuery = "");
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        OutlinedButton(
          onPressed: () {
            _showRestartDialog(context);
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF9F342C),
            side: BorderSide(color: const Color.fromARGB(255, 0, 0, 0)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.home_outlined,
                size: 18,
                color: Color.fromARGB(255, 0, 0, 0),
              ),
              SizedBox(width: 6),
              Text(
                "Restart",
                style: TextStyle(color: Color.fromARGB(255, 0, 0, 0)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showRestartDialog(BuildContext context) {
    final bool isTablet = MediaQuery.of(context).size.width > 600;

    showDialog(
      context: context,
      barrierDismissible: false, // kiosk-safe
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isTablet ? 40 : 26),
        ),
        contentPadding: EdgeInsets.all(isTablet ? 40 : 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Theme-matching Icon Container
            Container(
              padding: EdgeInsets.all(isTablet ? 30 : 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFBAA30).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.refresh_rounded, // Refresh icon for "Restart"
                color: const Color(0xFFFBAA30),
                size: isTablet ? 80 : 50,
              ),
            ),
            SizedBox(height: isTablet ? 30 : 20),

            // Header Text
            Text(
              "RESTART ORDER?",
              style: TextStyle(
                fontSize: isTablet ? 32 : 22,
                fontWeight: FontWeight.w900,
                color: Colors.black87,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 15),

            // Descriptive Text
            Text(
              "Are you sure you want to restart?\nYour current selection will be cleared.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isTablet ? 20 : 15.5,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
            SizedBox(height: isTablet ? 45 : 30),

            // Action Buttons
            Row(
              children: [
                // "No" Button
                Expanded(
                  child: SizedBox(
                    height: isTablet ? 75 : 55,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            isTablet ? 20 : 12,
                          ),
                        ),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: Icon(
                        Icons.close_rounded,
                        size: isTablet ? 20 : 16,
                        color: Colors.black54,
                      ),
                      label: Text(
                        "NO, GO BACK",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isTablet ? 20 : 12),

                // "Yes" Button
                Expanded(
                  child: SizedBox(
                    height: isTablet ? 75 : 55,
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
                        Navigator.pop(dialogContext); // Close dialog
                        _goToWelcome(context); // Execute reset logic
                      },
                      child: Text(
                        "YES, RESTART",
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 14,
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
      ),
    );
  }
}

Map<String, dynamic> _parseProductsIsolate(List<dynamic> raw) {
  bool isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value == 1;
    final s = value.toString().toLowerCase().trim();
    return s == "1" || s == "true" || s == "yes" || s == "y";
  }

  int toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? "") ?? 0;
  }

  int resolveItemId(Map item) {
    return toInt(
      item["id"] ??
          item["Id"] ??
          item["ID"] ??
          item["item_id"] ??
          item["itemId"],
    );
  }

  dynamic firstNonEmptyType(List<dynamic> values) {
    for (final v in values) {
      if (v == null) continue;
      if (v is String) {
        final s = v.trim();
        if (s.isEmpty) continue;
        return s;
      }
      return v;
    }
    return null;
  }

  final List<Map<String, dynamic>> products = [];
  final Map<String, String> categoryImages = {};
  final Map<int, List<Map<String, dynamic>>> variationsMap = {};
  final Map<int, List<Map<String, dynamic>>> modifiersMap = {};
  final Set<String> categories = {};

  for (final category in raw) {
    if (category is! Map) continue;
    final bool catActive =
        category["is_active"] == null || isTruthy(category["is_active"]);
    if (!catActive) continue;

    final String catName = category["category_name"]?.toString() ?? "Others";
    final String catImage =
        category["item_photo_url"]?.toString() ??
        category["category_image"]?.toString() ??
        category["image"]?.toString() ??
        "";

    if (catImage.isNotEmpty) {
      categoryImages[catName] = catImage;
    }

    final items = category["items"];
    if (items is! List) continue;

    for (final item in items) {
      if (item is! Map) continue;
      final avail = item["is_available"] ?? item["isAvailable"];
      if (!(avail == null || isTruthy(avail))) continue;

      final int itemId = resolveItemId(item);
      if (itemId == 0) continue;

      final variationsRaw = item["variations"];
      final List<Map<String, dynamic>> variations = variationsRaw is List
          ? variationsRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final rawModifiers = item["modifiers"];
      final List<Map<String, dynamic>> modifiers =
          rawModifiers is Map && rawModifiers["options"] is List
          ? (rawModifiers["options"] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      variationsMap[itemId] = variations;
      modifiersMap[itemId] = modifiers;

      final nested = item["item"];
      final nestedMap =
          nested is Map ? Map<String, dynamic>.from(nested) : null;
      final preferredType = firstNonEmptyType([
        item["type"],
        item["veg_type"],
        item["vegType"],
        item["food_type"],
        item["foodType"],
        item["item_type"],
        item["itemType"],
        nestedMap?["type"],
        nestedMap?["veg_type"],
        nestedMap?["vegType"],
        nestedMap?["food_type"],
        nestedMap?["foodType"],
        nestedMap?["item_type"],
        nestedMap?["itemType"],
      ]);
      final fallbackType = firstNonEmptyType([
        item["is_veg"],
        item["isVeg"],
        item["is_vegetarian"],
        item["isVegetarian"],
        item["vegetarian"],
        nestedMap?["is_veg"],
        nestedMap?["isVeg"],
        nestedMap?["is_vegetarian"],
        nestedMap?["isVegetarian"],
        nestedMap?["vegetarian"],
      ]);
      final rawType = preferredType ?? fallbackType;

      String pickName() {
        final direct = item["item_name"] ?? item["name"];
        if (direct != null && direct.toString().trim().isNotEmpty) {
          return direct.toString();
        }
        final nestedName = nestedMap?["item_name"] ?? nestedMap?["name"];
        return nestedName?.toString() ?? "";
      }

      dynamic pickPrice() {
        final direct = item["price"] ?? item["item_price"];
        if (direct != null) return direct;
        return nestedMap?["price"] ?? nestedMap?["item_price"] ?? 0;
      }

      String pickImage() {
        final direct = item["item_photo_url"] ?? item["image"];
        if (direct != null && direct.toString().trim().isNotEmpty) {
          return direct.toString();
        }
        final nestedImage =
            nestedMap?["item_photo_url"] ?? nestedMap?["image"];
        return nestedImage?.toString() ?? "";
      }

      final String name = pickName();
      final dynamic price = pickPrice();
      final String image = pickImage();

      products.add({
        "id": itemId,
        "name": name,
        "category": catName,
        "price": price,
        "image": image,
        "type": ProductModel.normalizeType(rawType),
      });

      categories.add(catName);
    }
  }

  return {
    "products": products,
    "categories": categories.toList(),
    "categoryImages": categoryImages,
    "variationsMap": variationsMap,
    "modifiersMap": modifiersMap,
  };
}

///
///
///
