import 'dart:convert';

import 'package:api_selfxo_project/api/dio_client.dart';
import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/core/image_url.dart';
import 'package:api_selfxo_project/services/session_manager.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerOrderHistoryItem {
  final String orderId;
  final String restaurantName;
  final String orderType;
  final String status;
  final DateTime orderedAt;
  final String displayDateTime;
  final String restaurantTimezone;
  final String paymentMethod;
  final String transactionId;
  final double totalAmount;
  final List<Map<String, dynamic>> items;

  const CustomerOrderHistoryItem({
    required this.orderId,
    required this.restaurantName,
    required this.orderType,
    required this.status,
    required this.orderedAt,
    this.displayDateTime = "",
    this.restaurantTimezone = "",
    this.paymentMethod = "",
    this.transactionId = "",
    required this.totalAmount,
    required this.items,
  });

  int get itemCount => items.fold<int>(0, (sum, item) {
        final rawQuantity = item["quantity"] ?? item["qty"] ?? item["count"];
        final quantity = rawQuantity is num
            ? rawQuantity.toInt()
            : int.tryParse(rawQuantity?.toString() ?? "");
        final name = (item["name"] ?? item["item_name"] ?? item["itemName"])
                ?.toString()
                .trim() ??
            "";
        return sum +
            ((quantity == null || quantity <= 0) && name.isNotEmpty
                ? 1
                : quantity ?? 0);
      });

  Map<String, dynamic> toJson() {
    return {
      "order_id": orderId,
      "restaurant_name": restaurantName,
      "order_type": orderType,
      "status": status,
      "ordered_at": orderedAt.toIso8601String(),
      "date_time_formatted": displayDateTime,
      "restaurant_timezone": restaurantTimezone,
      "payment_method": paymentMethod,
      "transaction_id": transactionId,
      "total_amount": totalAmount,
      "items": items,
    };
  }

  CustomerOrderHistoryItem copyWith({
    String? orderId,
    String? restaurantName,
    String? orderType,
    String? status,
    DateTime? orderedAt,
    String? displayDateTime,
    String? restaurantTimezone,
    String? paymentMethod,
    String? transactionId,
    double? totalAmount,
    List<Map<String, dynamic>>? items,
  }) {
    return CustomerOrderHistoryItem(
      orderId: orderId ?? this.orderId,
      restaurantName: restaurantName ?? this.restaurantName,
      orderType: orderType ?? this.orderType,
      status: status ?? this.status,
      orderedAt: orderedAt ?? this.orderedAt,
      displayDateTime: displayDateTime ?? this.displayDateTime,
      restaurantTimezone: restaurantTimezone ?? this.restaurantTimezone,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      transactionId: transactionId ?? this.transactionId,
      totalAmount: totalAmount ?? this.totalAmount,
      items: items ?? this.items,
    );
  }

  factory CustomerOrderHistoryItem.fromJson(Map<String, dynamic> json) {
    final rawItems = _findItemsList(json);
    final restaurantName = _readRestaurantName(json);
    final status = _readPaymentStatus(json);
    return CustomerOrderHistoryItem(
      orderId: _readString(json, const ["order_id", "id", "orderId"]),
      restaurantName: restaurantName.isEmpty ? "Restaurant" : restaurantName,
      orderType: _readString(json, const ["order_type", "orderType"]),
      status: status,
      orderedAt: DateTime.tryParse(
            _readString(json, const [
              "date_time",
              "dateTime",
              "ordered_at",
              "orderedAt",
              "created_at",
              "createdAt",
            ]),
          ) ??
          DateTime.now(),
      displayDateTime: _readString(json, const [
        "date_time_formatted",
        "dateTimeFormatted",
        "formatted_date_time",
        "formattedDateTime",
        "display_date_time",
        "displayDateTime",
      ]),
      restaurantTimezone: _readRestaurantTimezone(json),
      paymentMethod: _readPaymentMethod(json),
      transactionId: _readTransactionId(json),
      totalAmount: _readDouble(json, const [
        "total_amount",
        "totalAmount",
        "grand_total",
        "grandTotal",
        "payable_amount",
        "payableAmount",
        "final_amount",
        "finalAmount",
        "total",
        "amount",
      ]),
      items: rawItems.map(_normalizeOrderItem).toList(),
    );
  }

  static String _readString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is Map || value is List) continue;
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return "";
  }

  static String _readRestaurantName(Map<String, dynamic> json) {
    final direct = _readString(json, const [
      "restaurant_name",
      "restaurantName",
      "restaurant_title",
      "restaurantTitle",
    ]);
    if (direct.isNotEmpty) return direct;

    for (final key in const [
      "restaurant",
      "restaurant_data",
      "restaurantData"
    ]) {
      final value = json[key];
      if (value is Map) {
        final mapped = value.map((k, v) => MapEntry("$k", v));
        final name = _readString(mapped, const [
          "name",
          "restaurant_name",
          "restaurantName",
          "title",
        ]);
        if (name.isNotEmpty) return name;
      }
    }
    return "";
  }

  static String _readPaymentStatus(Map<String, dynamic> json) {
    if (_hasSettledPayment(json)) return "Paid";
    if (_containsPaidSignal(json)) return "Paid";

    final payment = _firstMap(json, const [
      "payment",
      "payment_data",
      "paymentData",
      "transaction",
      "transaction_data",
      "transactionData",
    ]);
    if (payment != null &&
        (_hasSettledPayment(payment) || _containsPaidSignal(payment))) {
      return "Paid";
    }

    final status = _readString(json, const [
      "payment_status",
      "paymentStatus",
      "payment_state",
      "paymentState",
      "status",
      "order_status",
      "orderStatus",
    ]);
    if (status.trim().isNotEmpty) return status;

    final nestedStatus = payment == null
        ? ""
        : _readString(payment, const [
            "payment_status",
            "paymentStatus",
            "status",
            "state",
            "transaction_status",
            "transactionStatus",
          ]);
    return nestedStatus.trim().isEmpty ? "Paid" : nestedStatus;
  }

  static String _readRestaurantTimezone(Map<String, dynamic> json) {
    final direct = _readString(json, const [
      "restaurant_timezone",
      "restaurantTimezone",
      "timezone",
    ]);
    if (direct.isNotEmpty) return direct;

    final restaurant = _firstMap(json, const [
      "restaurant",
      "restaurant_data",
      "restaurantData",
    ]);
    if (restaurant == null) return "";
    return _readString(restaurant, const ["timezone", "restaurant_timezone"]);
  }

  static String _readPaymentMethod(Map<String, dynamic> json) {
    final direct = _readString(json, const [
      "payment_method",
      "paymentMethod",
      "method",
      "mode",
    ]);
    if (direct.isNotEmpty) return direct;

    final latestPayment = _latestPaymentMap(json);
    if (latestPayment == null) return "";
    return _readString(latestPayment, const [
      "payment_method",
      "paymentMethod",
      "method",
      "mode",
    ]);
  }

  static String _readTransactionId(Map<String, dynamic> json) {
    final direct = _readString(json, const [
      "latest_transaction_id",
      "latestTransactionId",
      "transaction_id",
      "transactionId",
      "razorpay_payment_id",
      "payment_id",
      "paymentId",
    ]);
    if (direct.isNotEmpty) return direct;

    final latestPayment = _latestPaymentMap(json);
    if (latestPayment == null) return "";
    return _readString(latestPayment, const [
      "transaction_id",
      "transactionId",
      "razorpay_payment_id",
      "payment_id",
      "paymentId",
    ]);
  }

  static bool _hasSettledPayment(Map<String, dynamic> json) {
    if (_readTransactionId(json).isNotEmpty) return true;

    final paidAmount = _readDouble(json, const [
      "paid_amount",
      "paidAmount",
      "amount_paid",
      "amountPaid",
    ]);
    if (paidAmount > 0) return true;

    final payments = json["payments"];
    if (payments is List) {
      for (final payment in payments) {
        if (payment is! Map) continue;
        final mapped = payment.map((key, value) => MapEntry("$key", value));
        final transactionId = _readString(mapped, const [
          "transaction_id",
          "transactionId",
          "razorpay_payment_id",
          "payment_id",
          "paymentId",
        ]);
        final method = _readString(mapped, const [
          "payment_method",
          "paymentMethod",
          "method",
          "mode",
        ]);
        final amount = _readDouble(mapped, const ["amount", "paid_amount"]);
        if (transactionId.isNotEmpty || method.isNotEmpty || amount > 0) {
          return true;
        }
      }
    }
    return false;
  }

  static Map<String, dynamic>? _latestPaymentMap(Map<String, dynamic> json) {
    final payments = json["payments"];
    if (payments is! List || payments.isEmpty) return null;
    for (final payment in payments.reversed) {
      if (payment is Map) {
        return payment.map((key, value) => MapEntry("$key", value));
      }
    }
    return null;
  }

  static bool _containsPaidSignal(dynamic value, [int depth = 0]) {
    if (depth > 4 || value == null) return false;
    if (value is bool) return value;
    if (value is num) return value == 1;

    if (value is String) {
      final s = value.trim().toLowerCase();
      if (s.isEmpty) return false;
      return s == "paid" ||
          s == "success" ||
          s == "successful" ||
          s == "completed" ||
          s == "captured" ||
          s == "payment_success" ||
          s.contains("payment successful") ||
          s.contains("payment success");
    }

    if (value is List) {
      return value.any((entry) => _containsPaidSignal(entry, depth + 1));
    }

    if (value is Map) {
      const successKeys = [
        "paid",
        "is_paid",
        "isPaid",
        "payment_success",
        "paymentSuccess",
        "success",
        "is_success",
        "isSuccess",
        "captured",
        "payment_completed",
        "paymentCompleted",
      ];
      for (final key in successKeys) {
        if (value.containsKey(key) &&
            _containsPaidSignal(value[key], depth + 1)) {
          return true;
        }
      }

      const statusKeys = [
        "payment_status",
        "paymentStatus",
        "transaction_status",
        "transactionStatus",
        "status",
        "state",
      ];
      for (final key in statusKeys) {
        if (value.containsKey(key) &&
            _containsPaidSignal(value[key], depth + 1)) {
          return true;
        }
      }
    }
    return false;
  }

  static double _readDouble(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString().trim() ?? "");
      if (parsed != null) return parsed;
    }
    return 0;
  }

  static List<Map<String, dynamic>> _findItemsList(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        final raw = entry.value;
        if (raw is List &&
            (key.contains("item") ||
                key == "cart" ||
                key == "products" ||
                key == "order_details")) {
          return raw
              .whereType<Map>()
              .map((item) => item.map((k, v) => MapEntry("$k", v)))
              .toList();
        }
      }
      for (final entry in value.entries) {
        final nested = _findItemsList(entry.value);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const [];
  }

  static Map<String, dynamic> _normalizeOrderItem(Map<String, dynamic> item) {
    final nested = _firstMap(item, const [
      "item",
      "menu_item",
      "menuItem",
      "product",
      "product_data",
      "productData",
    ]);
    final pivot = _firstMap(item, const ["pivot", "order_item", "orderItem"]);
    final quantity = _readIntFromSources(
      [item, pivot, nested],
      const ["quantity", "qty", "count", "item_quantity", "itemQuantity"],
      fallback: 1,
    );
    var price = _readDoubleFromSources(
      [item, pivot, nested],
      const [
        "price",
        "unit_price",
        "unitPrice",
        "item_price",
        "itemPrice",
        "rate",
      ],
    );
    final amount = _readDoubleFromSources(
      [item, pivot],
      const [
        "amount",
        "total",
        "total_amount",
        "totalAmount",
        "line_total",
        "lineTotal",
        "subtotal",
      ],
    );
    if (price <= 0 && amount > 0) {
      price = amount / (quantity <= 0 ? 1 : quantity);
    }

    return {
      "id": _firstValue([item, nested], const ["id", "item_id", "itemId"]),
      "name": _readStringFromSources(
        [item, nested],
        const [
          "item_name",
          "itemName",
          "name",
          "title",
          "menu_item_name",
          "menuItemName",
          "product_name",
          "productName",
        ],
        fallback: "Item",
      ),
      "quantity": quantity <= 0 ? 1 : quantity,
      "price": price,
      "amount": amount > 0 ? amount : price * (quantity <= 0 ? 1 : quantity),
      "image": normalizeImageUrlValue(
        CustomerOrderHistoryItem._findImageValue(item),
      ),
    };
  }

  static Map<String, dynamic>? _firstMap(
    Map<String, dynamic> item,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = item[key];
      if (value is Map) {
        return value.map((k, v) => MapEntry("$k", v));
      }
    }
    return null;
  }

  static Object? _firstValue(
    List<Map<String, dynamic>?> sources,
    List<String> keys,
  ) {
    for (final source in sources) {
      if (source == null) continue;
      for (final key in keys) {
        final value = source[key];
        if (value != null && value.toString().trim().isNotEmpty) return value;
      }
    }
    return null;
  }

  static Object? _findImageValue(dynamic value, [int depth = 0]) {
    if (value == null || depth > 5) return null;
    const keys = [
      "item_photo_url",
      "item_photo",
      "image_url",
      "imageUrl",
      "item_image_url",
      "itemImageUrl",
      "image",
      "photo",
      "photo_url",
      "photoUrl",
      "item_image",
      "itemImage",
      "menu_item_image",
      "menuItemImage",
      "product_image",
      "productImage",
      "food_image",
      "foodImage",
      "thumbnail",
      "thumbnail_url",
      "thumbnailUrl",
      "thumb",
      "thumb_url",
      "thumbUrl",
      "picture",
      "logo_url",
      "logo",
    ];
    if (value is Map) {
      for (final key in keys) {
        final raw = value[key];
        if (raw != null && raw.toString().trim().isNotEmpty) return raw;
      }
      for (final entry in value.entries) {
        final found = _findImageValue(entry.value, depth + 1);
        if (found != null && found.toString().trim().isNotEmpty) return found;
      }
    }
    return null;
  }

  static String _readStringFromSources(
    List<Map<String, dynamic>?> sources,
    List<String> keys, {
    required String fallback,
  }) {
    final value = _firstValue(sources, keys)?.toString().trim() ?? "";
    return value.isEmpty ? fallback : value;
  }

  static int _readIntFromSources(
    List<Map<String, dynamic>?> sources,
    List<String> keys, {
    required int fallback,
  }) {
    final value = _firstValue(sources, keys);
    final parsed =
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? "");
    return parsed ?? fallback;
  }

  static double _readDoubleFromSources(
    List<Map<String, dynamic>?> sources,
    List<String> keys,
  ) {
    final value = _firstValue(sources, keys);
    return value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? "") ?? 0;
  }
}

class CustomerOrderHistoryService {
  CustomerOrderHistoryService._();

  static final CustomerOrderHistoryService instance =
      CustomerOrderHistoryService._();

  Future<void> savePaidOrder({
    required int orderId,
    required String restaurantName,
    required String orderType,
    required double totalAmount,
    required List<Map<String, dynamic>> cart,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final ownerKey = await _currentHistoryOwnerKey(prefs);
    if (ownerKey.isEmpty) return;

    final order = CustomerOrderHistoryItem(
      orderId: orderId.toString(),
      restaurantName: restaurantName,
      orderType: orderType,
      status: "Paid",
      orderedAt: DateTime.now(),
      totalAmount: totalAmount,
      items: cart.map(_normalizeCartItem).toList(),
    );

    final orders = await _loadLocalForOwner(prefs, ownerKey);
    orders.removeWhere((item) => item.orderId == order.orderId);
    orders.insert(0, order);
    await prefs.setString(
      _localKey(ownerKey),
      jsonEncode(orders.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<CustomerOrderHistoryItem>> loadOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final ownerKey = await _currentHistoryOwnerKey(prefs);
    if (ownerKey.isEmpty) return const [];

    final remote = await _loadRemoteOrders(prefs);
    final local = await _loadLocalForOwner(prefs, ownerKey);
    final merged = _mergeOrders(remote, local);
    final productImageIndex = await _loadProductImageIndex(prefs);
    return _enrichMissingItemImages(merged, productImageIndex);
  }

  Future<List<CustomerOrderHistoryItem>> _loadRemoteOrders(
    SharedPreferences prefs,
  ) async {
    final sanctumToken = await SessionManager.instance.getSanctumToken();
    if (sanctumToken == null || sanctumToken.isEmpty) return const [];

    try {
      final dio = DioClient.getDio();
      final res = await dio.get(
        "pwa/customer/orders",
        options: Options(headers: {"Authorization": "Bearer $sanctumToken"}),
      );
      final payload = res.data;
      final rawOrders =
          payload is Map ? (payload["data"] ?? payload["orders"]) : payload;
      if (rawOrders is! List) return const [];
      return rawOrders
          .whereType<Map>()
          .map((order) => CustomerOrderHistoryItem.fromJson(
                order.map((key, value) => MapEntry("$key", value)),
              ))
          .where((order) => order.orderId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<CustomerOrderHistoryItem>> _loadLocalForOwner(
    SharedPreferences prefs,
    String ownerKey,
  ) async {
    final raw = prefs.getString(_localKey(ownerKey));
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((order) => CustomerOrderHistoryItem.fromJson(
                order.map((key, value) => MapEntry("$key", value)),
              ))
          .where((order) => order.orderId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<CustomerOrderHistoryItem> _mergeOrders(
    List<CustomerOrderHistoryItem> remote,
    List<CustomerOrderHistoryItem> local,
  ) {
    final byId = <String, CustomerOrderHistoryItem>{};
    for (final order in [...remote, ...local]) {
      byId[order.orderId] = order;
    }
    final orders = byId.values.toList()
      ..sort((a, b) => b.orderedAt.compareTo(a.orderedAt));
    return orders;
  }

  Map<String, dynamic> _normalizeCartItem(Map<String, dynamic> item) {
    final quantity = int.tryParse(item["qty"]?.toString() ?? "") ??
        int.tryParse(item["quantity"]?.toString() ?? "") ??
        1;
    return {
      "id": item["id"],
      "name": item["name"] ?? item["item_name"],
      "quantity": quantity,
      "price": item["price"] ?? item["itemPrice"],
      "amount": item["amount"] ??
          item["total"] ??
          item["totalAmount"] ??
          item["price"] ??
          item["itemPrice"],
      "image": normalizeImageUrlValue(
        CustomerOrderHistoryItem._findImageValue(item),
      ),
    };
  }

  Future<Map<String, String>> _loadProductImageIndex(
    SharedPreferences prefs,
  ) async {
    final restaurantKey = _currentRestaurantCacheKey(prefs);
    final raw = prefs.getString(_productsScopedCacheKey(restaurantKey));
    if (raw == null || raw.trim().isEmpty) {
      try {
        final res = await KioskApi().getProducts();
        final index = <String, String>{};
        _indexProductImages(res.data, index);
        return index;
      } catch (_) {
        return const {};
      }
    }

    try {
      final decoded = jsonDecode(raw);
      final data = decoded is Map ? decoded["data"] : decoded;
      final index = <String, String>{};
      _indexProductImages(data, index);
      return index;
    } catch (_) {
      return const {};
    }
  }

  List<CustomerOrderHistoryItem> _enrichMissingItemImages(
    List<CustomerOrderHistoryItem> orders,
    Map<String, String> productImageIndex,
  ) {
    if (productImageIndex.isEmpty) return orders;

    return orders.map((order) {
      var changed = false;
      final enrichedItems = order.items.map((item) {
        final currentImage = item["image"]?.toString().trim() ?? "";
        if (currentImage.isNotEmpty) return item;

        final id = item["id"]?.toString().trim() ?? "";
        final name = item["name"]?.toString().trim() ?? "";
        final image = (id.isNotEmpty ? productImageIndex["id:$id"] : null) ??
            (name.isNotEmpty
                ? productImageIndex["name:${_normalizeLookupName(name)}"]
                : null);
        if (image == null || image.trim().isEmpty) return item;

        changed = true;
        return {
          ...item,
          "image": image,
        };
      }).toList();

      return changed ? order.copyWith(items: enrichedItems) : order;
    }).toList();
  }

  void _indexProductImages(dynamic value, Map<String, String> index,
      [int depth = 0]) {
    if (value == null || depth > 7) return;

    if (value is List) {
      for (final entry in value) {
        _indexProductImages(entry, index, depth + 1);
      }
      return;
    }

    if (value is! Map) return;
    final mapped = value.map((key, value) => MapEntry("$key", value));
    final nested = CustomerOrderHistoryItem._firstMap(mapped, const [
      "item",
      "menu_item",
      "menuItem",
      "product",
      "product_data",
      "productData",
    ]);
    final image = normalizeImageUrlValue(
      CustomerOrderHistoryItem._findImageValue(mapped),
    );
    final hasChildItems = mapped["items"] is List || mapped["products"] is List;
    final hasProductIdentity = nested != null ||
        mapped.containsKey("item_id") ||
        mapped.containsKey("itemId") ||
        mapped.containsKey("item_name") ||
        mapped.containsKey("itemName") ||
        mapped.containsKey("product_id") ||
        mapped.containsKey("productId") ||
        mapped.containsKey("product_name") ||
        mapped.containsKey("productName") ||
        (mapped.containsKey("name") && !hasChildItems);
    if (image.isNotEmpty && hasProductIdentity) {
      final id = CustomerOrderHistoryItem._firstValue(
        [mapped, nested],
        const ["id", "item_id", "itemId", "product_id", "productId"],
      )?.toString().trim();
      final name = CustomerOrderHistoryItem._readStringFromSources(
        [mapped, nested],
        const [
          "item_name",
          "itemName",
          "name",
          "title",
          "menu_item_name",
          "menuItemName",
          "product_name",
          "productName",
        ],
        fallback: "",
      );
      if (id != null && id.isNotEmpty) {
        index.putIfAbsent("id:$id", () => image);
      }
      if (name.trim().isNotEmpty) {
        index.putIfAbsent(
          "name:${_normalizeLookupName(name)}",
          () => image,
        );
      }
    }

    for (final entry in mapped.entries) {
      _indexProductImages(entry.value, index, depth + 1);
    }
  }

  String _currentRestaurantCacheKey(SharedPreferences prefs) {
    final hash = prefs.getString("restaurant_hash")?.trim() ?? "";
    final id = prefs.getString("restaurant_id")?.trim() ?? "";
    if (hash.isNotEmpty) return hash;
    if (id.isNotEmpty) return id;
    return "default";
  }

  String _productsScopedCacheKey(String restaurantKey) {
    final safeKey = restaurantKey
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return "kiosk_products_cache_$safeKey";
  }

  static String _normalizeLookupName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<String> _currentHistoryOwnerKey(SharedPreferences prefs) async {
    final mobile = prefs.getString("customer_mobile")?.trim() ?? "";
    if (mobile.isNotEmpty) return "mobile_$mobile";

    final isGuest = await SessionManager.instance.isGuestSession();
    if (!isGuest) return "";

    final guestId = await SessionManager.instance.getOrCreateGuestId();
    return "guest_$guestId";
  }

  String _localKey(String ownerKey) {
    final safeOwnerKey = ownerKey.replaceAll(RegExp(r"[^0-9A-Za-z_+]"), "_");
    return "customer_order_history_$safeOwnerKey";
  }
}
