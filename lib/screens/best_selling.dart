import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:api_selfxo_project/core/kiosk_config.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';
import '../modules/product_model.dart';

class BestSellingWidget extends StatefulWidget {
  final List<ProductModel> products;
  final bool isActive;
  final void Function(
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

  const BestSellingWidget({
    super.key,
    required this.products,
    this.isActive = true,
    required this.onAddToCart,
  });

  @override
  State<BestSellingWidget> createState() => _BestSellingWidgetState();
}

class _BestSellingWidgetState extends State<BestSellingWidget> {
  PageController _pageController = PageController(viewportFraction: 0.78);
  int currentIndex = 0;
  List<ProductModel> displayedProducts = [];
  final Map<int, int> qtyMap = {};
  Timer? _autoScrollTimer;
  double _viewportFraction = 0.78;
  VoidCallback? _maintenanceListener;

  static const Color kGreen = Colors.green;
  static const Color kBg = Color(0xFFE8F5E9);

  @override
  void initState() {
    super.initState();
    _prepareData();
    _maintenanceListener = _handleMaintenanceTick;
    KioskMemoryService.instance.maintenanceTick.addListener(
      _maintenanceListener!,
    );
  }

  @override
  void didUpdateWidget(covariant BestSellingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (!widget.isActive) {
        _autoScrollTimer?.cancel();
      } else {
        _startAutoScroll();
      }
    }
    if (widget.products != oldWidget.products) {
      _prepareData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    final double nextFraction = isTablet ? 0.42 : 0.78;
    if (_viewportFraction != nextFraction) {
      _viewportFraction = nextFraction;
      final int page = _pageController.hasClients
          ? (_pageController.page?.round() ?? currentIndex)
          : currentIndex;
      _pageController.dispose();
      _pageController = PageController(
        viewportFraction: _viewportFraction,
        initialPage: page,
      );
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    if (_maintenanceListener != null) {
      KioskMemoryService.instance.maintenanceTick.removeListener(
        _maintenanceListener!,
      );
    }
    super.dispose();
  }

  @override
  void deactivate() {
    _autoScrollTimer?.cancel();
    super.deactivate();
  }

  void _prepareData() {
    if (widget.products.isEmpty) return;
    List<ProductModel> all = List.from(widget.products);
    List<ProductModel> fastSelling = all
        .where((p) => p.isBestSeller ?? false)
        .toList();

    if (fastSelling.length < 5) {
      List<ProductModel> remaining = all
          .where((p) => !fastSelling.contains(p))
          .toList();
      remaining.shuffle(Random());
      fastSelling.addAll(remaining.take(5 - fastSelling.length));
    }

    setState(() => displayedProducts = fastSelling.take(5).toList());
    _resetPager();
    _startAutoScroll();
  }

  void _resetPager() {
    if (displayedProducts.isEmpty) return;
    final int start = displayedProducts.length * 1000;
    _pageController.dispose();
    _pageController = PageController(
      viewportFraction: _viewportFraction,
      initialPage: start,
    );
    currentIndex = start % displayedProducts.length;
  }

  void _handleMaintenanceTick() {
    if (!mounted) return;
    if (!widget.isActive) return;
    _autoScrollTimer?.cancel();
    _resetPager();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (!widget.isActive) return;
    if (!KioskConfig.enableAutoScroll) return;
    if (displayedProducts.length < 2) return;

    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      try {
        if (!mounted) return;
        if (!widget.isActive) return;
        if (!_pageController.hasClients) return;

        final int currentPage = _pageController.page?.round() ?? currentIndex;
        final next = currentPage + 1;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    if (displayedProducts.isEmpty) return const SizedBox();

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isTablet = screenWidth > 600;

    // ✅ TABLET → EXACTLY 2 ITEMS
    // Controller is managed in didChangeDependencies.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🌈 GRADIENT TITLE WITH ICON
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: isTablet ? 26 : 24,
                color: const Color(0xFF22E6C7), // sparkle color
              ),
              const SizedBox(width: 8),
              ShaderMask(
                shaderCallback: (bounds) {
                  return const LinearGradient(
                    colors: [
                      Color(0xFF22E6C7), // teal
                      Color(0xFF3A7BFF), // blue
                      Color(0xFF9B4DFF), // purple
                    ],
                  ).createShader(bounds);
                },
                child: Text(
                  "Top Selling Items (Today)",
                  style: TextStyle(
                    fontSize: isTablet ? 24 : 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white, // required for ShaderMask
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 📦 PRODUCT SLIDER CONTAINER
        Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 242, 220, 188),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: isTablet ? 155 : 130,
                  child: PageView.builder(
                    controller: _pageController,
                    padEnds: false,
                    onPageChanged: (i) {
                      final next = i % displayedProducts.length;
                      if (next != currentIndex && mounted) {
                        setState(() => currentIndex = next);
                      }
                    },
                    itemBuilder: (_, i) => _buildProductCard(
                      displayedProducts[i % displayedProducts.length],
                      isTablet,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildDots(displayedProducts.length, isTablet),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Rect? _rectFromContext(BuildContext? context) {
    if (context == null) return null;
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached) return null;
    final topLeft = render.localToGlobal(Offset.zero);
    return topLeft & render.size;
  }

  Widget _buildProductCard(ProductModel p, bool isTablet) {
    BuildContext? imageContext;
    final int qty = qtyMap[p.id] ?? 0;

    final bool needsCustomization =
        p.variations.isNotEmpty || p.modifiers.isNotEmpty;

    void handleAdd() {
      setState(() => qtyMap[p.id] = qty + 1);
      widget.onAddToCart(
        p.id,
        p.name,
        p.category,
        p.price,
        p.image,
        qty + 1,
        null,
        const [],
        _rectFromContext(imageContext),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _imageSection(
            p,
            isTablet,
            onContextReady: (ctx) => imageContext = ctx,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isTablet ? 16 : 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "₹${p.price}",
                    style: TextStyle(
                      color: const Color.fromARGB(255, 0, 0, 0),
                      fontSize: isTablet ? 18 : 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (needsCustomization)
                    const Text(
                      "Variants Available",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 6),
                  qty == 0
                      ? _addButton(handleAdd, isTablet)
                      : _counter(
                        p,
                        qty,
                        isTablet,
                        () => _rectFromContext(imageContext),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageSection(
    ProductModel p,
    bool isTablet, {
    required ValueChanged<BuildContext> onContextReady,
  }) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final double size = isTablet ? 110 : 80;
    final double cardHeight = isTablet ? 155 : 130;
    final int cacheWidth = (size * dpr).round();
    final int cacheHeight = (cardHeight * dpr).round();

    return SizedBox(
      width: size,
      height: double.infinity,
      child: Builder(
        builder: (ctx) {
          onContextReady(ctx);
          return ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(14),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.network(
                    p.image,
                    key: ValueKey("best-selling-image-${p.id}"),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    cacheWidth: cacheWidth,
                    cacheHeight: cacheHeight,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.fastfood),
                    ),
                  ),
                ),
                Positioned(top: 8, left: 8, child: _vegIcon(p.isVeg)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _vegIcon(bool isVeg) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: isVeg ? Colors.green : Colors.red, width: 1),
    ),
    child: Icon(
      Icons.circle,
      size: 6,
      color: isVeg ? Colors.green : Colors.red,
    ),
  );

  Widget _addButton(VoidCallback onTap, bool isTablet) {
    return SizedBox(
      width: double.infinity,
      height: isTablet ? 44 : 34,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFFF4C66A),
          foregroundColor: const Color(0xFF1F1F1F),
          side: const BorderSide(color: Color(0xFFE2B85E), width: 1),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              color: const Color(0xFF1F1F1F),
              size: isTablet ? 18 : 16,
            ),
            const SizedBox(width: 6),
            Text(
              "Add",
              style: TextStyle(
                color: const Color(0xFF1F1F1F),
                fontWeight: FontWeight.w800,
                fontSize: isTablet ? 16 : 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counter(
    ProductModel p,
    int qty,
    bool isTablet,
    Rect? Function() imageRectBuilder,
  ) {
    final double buttonHeight = isTablet ? 40 : 32;
    return SizedBox(
      height: buttonHeight,
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: _qtyInnerButton(
                label: "-",
                onTap: () {
                  final newQty = (qty - 1).clamp(0, 99);
                  setState(() => qtyMap[p.id] = newQty);
                  widget.onAddToCart(
                    p.id,
                    p.name,
                    p.category,
                    p.price,
                    p.image,
                    newQty,
                    null,
                    const [],
                    imageRectBuilder(),
                  );
                },
                backgroundColor: Colors.red,
                textColor: Colors.white,
                height: buttonHeight,
                isTablet: isTablet,
              ),
            ),
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  "$qty",
                  style: TextStyle(
                    fontSize: isTablet ? 18 : 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: _qtyInnerButton(
                label: "+",
                onTap: () {
                  final newQty = qty + 1;
                  setState(() => qtyMap[p.id] = newQty);
                  widget.onAddToCart(
                    p.id,
                    p.name,
                    p.category,
                    p.price,
                    p.image,
                    newQty,
                    null,
                    const [],
                    imageRectBuilder(),
                  );
                },
                backgroundColor: kGreen,
                textColor: Colors.white,
                height: buttonHeight,
                isTablet: isTablet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyInnerButton({
    required String label,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color textColor,
    required double height,
    required bool isTablet,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: isTablet ? 18 : 16,
          ),
        ),
      ),
    );
  }

  Widget _buildDots(int count, bool isTablet) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: currentIndex == i ? (isTablet ? 24 : 18) : 8,
          height: 8,
          decoration: BoxDecoration(
            color: currentIndex == i
                ? const Color.fromARGB(255, 255, 255, 255)
                : const Color.fromARGB(255, 214, 199, 151),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
