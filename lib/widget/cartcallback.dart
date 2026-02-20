import 'package:flutter/widgets.dart';

typedef AddToCartCallback =
    void Function(
      int id,
      String name,
      String image,
      int qty,
      int? variationId,
      List<int> modifierIds,
      Rect? imageRect,
    );
