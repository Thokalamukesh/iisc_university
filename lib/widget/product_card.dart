import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:api_selfxo_project/core/image_url.dart';
import 'package:api_selfxo_project/widget/app_network_image.dart';

class ProductCardRef extends StatefulWidget {
  final int id;
  final String name;
  final String category;
  final int price;
  final String imagePath;
  final bool isVeg;
  final List<Map<String, dynamic>> variations;
  final List<Map<String, dynamic>> modifiers;
  final int qty;

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
  ) onAddToCart;

  final int? imageCacheWidth;
  final int? imageCacheHeight;

  const ProductCardRef({
    super.key,
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.imagePath,
    required this.isVeg,
    required this.qty,
    required this.onAddToCart,
    this.imageCacheWidth,
    this.imageCacheHeight,
    this.variations = const [],
    this.modifiers = const [],
  });

  @override
  State<ProductCardRef> createState() => _ProductCardRefState();
}

class _ProductCardRefState extends State<ProductCardRef> {
  static const Color _orderRed = Color(0xFFD90012);
  static const Color _plusGreen = Color(0xFF2F8F46);

  late int qty;
  BuildContext? _imageContext;
  Map<String, dynamic>? _lastVariation;
  List<Map<String, dynamic>> _lastModifiers = [];

  @override
  void initState() {
    super.initState();
    qty = widget.qty;
  }

  @override
  void didUpdateWidget(covariant ProductCardRef oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.qty != widget.qty) qty = widget.qty;
  }

  bool get _needsCustomization =>
      widget.variations.isNotEmpty || widget.modifiers.isNotEmpty;

  int _calculateFinalPrice(Map<String, dynamic> result) {
    int total = widget.price;
    final variation = result["variation"];
    if (variation != null && variation is Map) {
      total += (variation["price"] ?? 0) as int;
    }
    final modifiers = result["modifiers"];
    if (modifiers != null && modifiers is List) {
      for (final m in modifiers) {
        if (m is Map) total += (m["price"] ?? 0) as int;
      }
    }
    return total;
  }

  void _addDirect() {
    final newQty = qty + 1;
    setState(() => qty = newQty);
    widget.onAddToCart(
      widget.id,
      widget.name,
      widget.category,
      widget.price,
      widget.imagePath,
      newQty,
      null,
      const [],
      _imageRect(),
    );
  }

  void _remove() {
    final newQty = qty - 1;
    final updatedQty = newQty < 0 ? 0 : newQty;
    if (updatedQty == 0) {
      _lastVariation = null;
      _lastModifiers = [];
    }
    setState(() => qty = updatedQty);

    final variation = _needsCustomization ? _lastVariation : null;
    final modifiers =
        _needsCustomization ? _lastModifiers : const <Map<String, dynamic>>[];
    widget.onAddToCart(
      widget.id,
      widget.name,
      widget.category,
      widget.price,
      widget.imagePath,
      updatedQty,
      variation,
      modifiers,
      _imageRect(),
    );
  }

  Rect? _imageRect() {
    final ctx = _imageContext;
    if (ctx == null) return null;
    final render = ctx.findRenderObject();
    if (render is! RenderBox || !render.attached) return null;
    final topLeft = render.localToGlobal(Offset.zero);
    return topLeft & render.size;
  }

  @override
  Widget build(BuildContext context) {
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    final bool isCompactWebCard = kIsWeb && !isTablet;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: isCompactWebCard ? 1.42 : 1.2,
              child: _imageSection(),
            ),
            Expanded(child: _infoSection()),
            Padding(
              padding: EdgeInsets.fromLTRB(
                isCompactWebCard ? 8 : 10,
                0,
                isCompactWebCard ? 8 : 10,
                isCompactWebCard ? 6 : 8,
              ),
              child: qty == 0 ? _addButton() : _counter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageSection() {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = widget.imageCacheWidth ?? (220 * dpr).round();
    final cacheHeight = widget.imageCacheHeight ?? (220 * dpr).round();
    final imageUrl = normalizeImageUrl(widget.imagePath);

    return Builder(
      builder: (ctx) {
        _imageContext = ctx;
        return Stack(
          children: [
            Positioned.fill(
              child: Container(
                key: ValueKey("product-image-${widget.id}"),
                color: Colors.grey.shade100,
                child: imageUrl.isNotEmpty
                    ? AppNetworkImage(
                        url: imageUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        gaplessPlayback: true,
                        cacheWidth: cacheWidth,
                        cacheHeight: cacheHeight,
                        fallback: const Center(
                          child: Icon(Icons.fastfood, size: 30),
                        ),
                      )
                    : const Center(child: Icon(Icons.fastfood, size: 30)),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: widget.isVeg ? Colors.green : Colors.red,
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  Icons.circle,
                  size: 6,
                  color: widget.isVeg ? Colors.green : Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoSection() {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final isCompactWebCard = kIsWeb && !isTablet;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortInfoArea = constraints.maxHeight < 46;
        final nameSize = shortInfoArea
            ? (isTablet ? 13.5 : 12.0)
            : (isTablet ? 15.0 : (isCompactWebCard ? 12.0 : 13.0));
        final priceSize = shortInfoArea
            ? (isTablet ? 13.5 : 12.5)
            : (isTablet ? 15.0 : (isCompactWebCard ? 13.0 : 14.0));

        final content = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: nameSize,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              "₹${widget.price}",
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: priceSize,
                fontWeight: FontWeight.bold,
                color: const Color.fromARGB(255, 0, 0, 0),
                height: 1.0,
              ),
            ),
            if (_needsCustomization) ...[
              const SizedBox(height: 1),
              Text(
                "Variants Available",
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: shortInfoArea ? 8 : (isCompactWebCard ? 8.5 : 10),
                  color: Colors.orange,
                  height: 1.0,
                ),
              ),
            ],
          ],
        );

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCompactWebCard ? 8 : 10,
            vertical: isCompactWebCard ? 1 : 2,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: constraints.maxWidth -
                  (isCompactWebCard ? 16 : 20).clamp(0, constraints.maxWidth),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _addButton() {
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    final bool isCompactWebCard = kIsWeb && !isTablet;
    return SizedBox(
      height: isCompactWebCard ? 28 : 32,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              _needsCustomization ? _openCustomizationSheet() : _addDirect(),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF2337), _orderRed, Color(0xFFB90010)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: _orderRed.withOpacity(0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 8,
                  right: 8,
                  top: 2,
                  child: Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add,
                        size: isCompactWebCard ? 15 : 18,
                        color: Colors.white,
                      ),
                      SizedBox(width: isCompactWebCard ? 4 : 6),
                      Text(
                        "Add",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: isCompactWebCard ? 12 : 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _counter() {
    final bool isTablet = MediaQuery.of(context).size.width > 600;
    final bool isCompactWebCard = kIsWeb && !isTablet;
    final double buttonHeight = isCompactWebCard ? 28 : 32;
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
                onTap: _remove,
                isTablet: isTablet,
                backgroundColor: Colors.red,
                textColor: Colors.white,
                height: buttonHeight,
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                alignment: Alignment.center,
                child: Text(
                  "$qty",
                  style: TextStyle(
                    fontSize: isTablet ? 16 : (isCompactWebCard ? 12 : 14),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: _qtyInnerButton(
                label: "+",
                onTap:
                    _needsCustomization ? _openCustomizationSheet : _addDirect,
                isTablet: isTablet,
                isPrimary: true,
                height: buttonHeight,
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
    required bool isTablet,
    bool isPrimary = false,
    Color? textColor,
    Color? backgroundColor,
    double? height,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: height ?? (isTablet ? 32 : 28),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor ?? (isPrimary ? _plusGreen : Colors.white),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isPrimary ? Colors.white : (textColor ?? Colors.black87),
            fontSize: isTablet ? 18 : (kIsWeb ? 14 : 16),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _openCustomizationSheet() async {
    final Map<String, dynamic>? result =
        await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _CustomizationSheet(
          name: widget.name,
          imageUrl: widget.imagePath,
          variations: widget.variations,
          modifiers: widget.modifiers,
          onCancel: () => Navigator.pop(context),
          onAdd: (data) => Navigator.pop(context, data),
        ),
      ),
    );

    if (result != null) {
      final int addedQty = (result["qty"] as num?)?.toInt() ?? 1;
      final int newTotalQty = qty + addedQty;
      final int finalPrice = _calculateFinalPrice(result);
      final variation = result["variation"] as Map<String, dynamic>?;
      final modifiers = List<Map<String, dynamic>>.from(
        result["modifiers"] ?? [],
      );

      setState(() {
        qty = newTotalQty;
        _lastVariation = variation;
        _lastModifiers = modifiers;
      });

      widget.onAddToCart(
        widget.id,
        widget.name,
        widget.category,
        finalPrice,
        widget.imagePath,
        newTotalQty,
        variation,
        modifiers,
        _imageRect(),
      );
    }
  }
}

class _CustomizationSheet extends StatefulWidget {
  final String name;
  final String imageUrl;
  final List<Map<String, dynamic>> variations;
  final List<Map<String, dynamic>> modifiers;
  final VoidCallback onCancel;
  final Function(Map<String, dynamic>) onAdd;

  const _CustomizationSheet({
    required this.name,
    required this.imageUrl,
    required this.variations,
    required this.modifiers,
    required this.onCancel,
    required this.onAdd,
  });

  @override
  State<_CustomizationSheet> createState() => _CustomizationSheetState();
}

class _CustomizationSheetState extends State<_CustomizationSheet> {
  int? selectedVariation;
  final Set<int> selectedModifiers = {};
  int quantity = 1;

  static const Color kPrimary = Color(0xFF1B8E3E);
  static const Color kAccent = Color(0xFFFFA726);

  String _safeText(dynamic value) {
    if (value == null) return "";
    if (value is String) return value;
    if (value is Map) return value["name"] ?? value["label"] ?? "Option";
    return value.toString();
  }

  bool get canAdd => widget.variations.isEmpty || selectedVariation != null;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: double.infinity,
          minHeight: MediaQuery.of(context).size.height * 0.5,
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF9FAFB),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            0,
            12,
            0,
            MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: _buildHeader(),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.variations.isNotEmpty) ...[
                                  _sectionTitle(
                                    "Choose Size",
                                    Icons.straighten_rounded,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: widget.variations
                                        .map(
                                          (v) => _buildVariationTile(
                                            v,
                                            isTablet,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                if (widget.modifiers.isNotEmpty) ...[
                                  _sectionTitle(
                                    "Add Toppings",
                                    Icons.tune_rounded,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: widget.modifiers
                                        .map(
                                          (m) => _buildModifierTile(
                                            m,
                                            isTablet,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                              ],
                            ),
                          ),
                        ),
                        _buildActions(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final int cache = (80 * dpr).round().clamp(1, 512);
    final imageUrl = normalizeImageUrl(widget.imageUrl);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: imageUrl.isNotEmpty
              ? AppNetworkImage(
                  url: imageUrl,
                  width: 80, // Slightly smaller for header
                  height: 80,
                  fit: BoxFit.cover,
                  cacheWidth: cache,
                  cacheHeight: cache,
                  fallback: const Icon(Icons.fastfood, size: 50),
                )
              : const Icon(Icons.fastfood, size: 50),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _qtyButton(
                    Icons.remove,
                    quantity > 1 ? () => setState(() => quantity--) : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      "$quantity",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _qtyButton(Icons.add, () => setState(() => quantity++)),
                ],
              ),
            ],
          ),
        ),
        IconButton(onPressed: widget.onCancel, icon: const Icon(Icons.close)),
      ],
    );
  }

  Widget _buildVariationTile(Map<String, dynamic> v, bool isTablet) {
    final bool selected = selectedVariation == v["id"];
    final String label = _safeText(v["variation"] ?? v["name"]);
    final String priceText = "₹${v["price"] ?? 0}";

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => selectedVariation = v["id"] as int),
      child: Container(
        width: isTablet ? 180 : 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kPrimary.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? kPrimary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: kPrimary.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? kPrimary : Colors.grey.shade500,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: isTablet ? 14 : 13,
                      color: selected ? kPrimary : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    priceText,
                    style: TextStyle(
                      fontSize: isTablet ? 12 : 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? kPrimary : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModifierTile(Map<String, dynamic> m, bool isTablet) {
    final id = m["id"];
    final selected = selectedModifiers.contains(id);
    final String label = _safeText(m["name"]);
    final String priceText = m["price"] != null ? "₹${m["price"]}" : "₹0";

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        setState(() {
          selected ? selectedModifiers.remove(id) : selectedModifiers.add(id);
        });
      },
      child: Container(
        width: isTablet ? 180 : 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kAccent.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? kAccent : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: kAccent.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? kAccent : Colors.grey.shade500,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: isTablet ? 14 : 13,
                      color: selected ? kAccent : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    priceText,
                    style: TextStyle(
                      fontSize: isTablet ? 12 : 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? kAccent : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF9F342C),
                side: const BorderSide(color: Color(0xFF9F342C), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text(
                "CANCEL",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              onPressed: canAdd
                  ? () {
                      widget.onAdd({
                        "variation": selectedVariation == null
                            ? null
                            : widget.variations.firstWhere(
                                (v) => v["id"] == selectedVariation,
                              ),
                        "modifiers": widget.modifiers
                            .where((m) => selectedModifiers.contains(m["id"]))
                            .map(
                              (m) => {
                                "id": m["id"],
                                "name": m["name"],
                                "price": m["price"] ?? 0,
                              },
                            )
                            .toList(),
                        "qty": quantity,
                      });
                    }
                  : null,
              icon: const Icon(
                Icons.shopping_cart_rounded,
                size: 18,
                color: Colors.white,
              ),
              label: const FittedBox(
                child: Text(
                  "ADD TO CART",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null ? Colors.grey : Colors.black,
        ),
      ),
    );
  }
}

///
///
///
/// cz\ategori
