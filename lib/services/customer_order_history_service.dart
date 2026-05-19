import 'dart:convert';

import 'package:api_selfxo_project/api/dio_client.dart';
import 'package:api_selfxo_project/services/session_manager.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerOrderHistoryItem {
  final String orderId;
  final String restaurantName;
  final String orderType;
  final String status;
  final DateTime orderedAt;
  final double totalAmount;
  final List<Map<String, dynamic>> items;

  const CustomerOrderHistoryItem({
    required this.orderId,
    required this.restaurantName,
    required this.orderType,
    required this.status,
    required this.orderedAt,
    required this.totalAmount,
    required this.items,
  });

  int get itemCount => items.fold<int>(
        0,
        (sum, item) =>
            sum + (int.tryParse(item["quantity"]?.toString() ?? "") ?? 0),
      );

  Map<String, dynamic> toJson() {
    return {
      "order_id": orderId,
      "restaurant_name": restaurantName,
      "order_type": orderType,
      "status": status,
      "ordered_at": orderedAt.toIso8601String(),
      "total_amount": totalAmount,
      "items": items,
    };
  }

  factory CustomerOrderHistoryItem.fromJson(Map<String, dynamic> json) {
    final rawItems =
        json["items"] ?? json["order_items"] ?? json["orderItemList"];
    return CustomerOrderHistoryItem(
      orderId: _readString(json, const ["order_id", "id", "orderId"]),
      restaurantName: _readString(
        json,
        const ["restaurant_name", "restaurantName", "restaurant"],
      ).trim().isEmpty
          ? "Restaurant"
          : _readString(
              json,
              const ["restaurant_name", "restaurantName", "restaurant"],
            ),
      orderType: _readString(json, const ["order_type", "orderType"]),
      status:
          _readString(json, const ["status", "payment_status"]).trim().isEmpty
              ? "Paid"
              : _readString(json, const ["status", "payment_status"]),
      orderedAt: DateTime.tryParse(
            _readString(json, const ["ordered_at", "created_at", "createdAt"]),
          ) ??
          DateTime.now(),
      totalAmount: double.tryParse(
              _readString(json, const ["total_amount", "total", "amount"])) ??
          0,
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((item) => item.map((key, value) => MapEntry("$key", value)))
              .toList()
          : const [],
    );
  }

  static String _readString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return "";
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
    final mobile = _currentMobile(prefs);
    if (mobile.isEmpty) return;

    final order = CustomerOrderHistoryItem(
      orderId: orderId.toString(),
      restaurantName: restaurantName,
      orderType: orderType,
      status: "Paid",
      orderedAt: DateTime.now(),
      totalAmount: totalAmount,
      items: cart.map(_normalizeCartItem).toList(),
    );

    final orders = await _loadLocalForMobile(prefs, mobile);
    orders.removeWhere((item) => item.orderId == order.orderId);
    orders.insert(0, order);
    await prefs.setString(
      _localKey(mobile),
      jsonEncode(orders.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<CustomerOrderHistoryItem>> loadOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final mobile = _currentMobile(prefs);
    if (mobile.isEmpty) return const [];

    final remote = await _loadRemoteOrders(prefs);
    final local = await _loadLocalForMobile(prefs, mobile);
    return _mergeOrders(remote, local);
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

  Future<List<CustomerOrderHistoryItem>> _loadLocalForMobile(
    SharedPreferences prefs,
    String mobile,
  ) async {
    final raw = prefs.getString(_localKey(mobile));
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
        0;
    return {
      "id": item["id"],
      "name": item["name"] ?? item["item_name"],
      "quantity": quantity,
      "price": item["price"] ?? item["itemPrice"],
      "image": item["image"] ?? item["item_photo_url"],
    };
  }

  String _currentMobile(SharedPreferences prefs) {
    return prefs.getString("customer_mobile")?.trim() ?? "";
  }

  String _localKey(String mobile) {
    final safeMobile = mobile.replaceAll(RegExp(r"[^0-9+]"), "_");
    return "customer_order_history_$safeMobile";
  }
}
