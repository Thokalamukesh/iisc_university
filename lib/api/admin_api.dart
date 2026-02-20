import 'package:dio/dio.dart';
import 'dio_client.dart';

class AdminApi {
  // =========================================================
  // 🔓 ADMIN LOGIN (NO TOKEN)
  // =========================================================
  Future<Response> login({
    required String deviceId,
    required String pin,
  }) async {
    final dio = DioClient.getDio();

    return dio.post(
      "admin/authenticate",
      data: {"device_id": deviceId, "password": pin},
    );
  }

  // =========================================================
  // 🔐 ADMIN AUTH APIs (ADMIN TOKEN REQUIRED)
  // =========================================================

  Future<Response> getItems() async {
    final dio = await DioClient.getAdminDio();
    return dio.get("admin/items");
  }

  Future<Response> getCategories() async {
    final dio = await DioClient.getAdminDio();
    return dio.get("admin/categories");
  }

  Future<Response> getOrders(Map<String, dynamic> body) async {
    final dio = await DioClient.getAdminDio();
    return dio.post("admin/orders", data: body);
  }

  Future<Response> getOrder(String id) async {
    final dio = await DioClient.getAdminDio();
    return dio.get("admin/order/$id");
  }

  Future<Response> getSettings() async {
    final dio = await DioClient.getAdminDio();
    return dio.get("admin/settings");
  }

  Future<Response> updateSettings(Map<String, dynamic> body) async {
    try {
      final dio = await DioClient.getAdminDio();
      return dio.put("admin/updateSettings", data: body);
    } catch (_) {
      final dio = await DioClient.getAuthedDio();
      return dio.put("admin/updateSettings", data: body);
    }
  }

  Future<Response> updateCategory(String id, Map<String, dynamic> body) async {
    final dio = await DioClient.getAdminDio();
    return dio.put("admin/category/update/$id", data: body);
  }

  Future<Response> createCategory(Map<String, dynamic> body) async {
    final dio = await DioClient.getAdminDio();
    return dio.post("admin/category/create", data: body);
  }

  Future<Response> updateItem(String id, Map<String, dynamic> body) async {
    final dio = await DioClient.getAdminDio();
    return dio.put("admin/item/update/$id", data: body);
  }

  Future<Response> cancelOrder(String id) async {
    final dio = await DioClient.getAdminDio();
    return dio.put(
      "admin/order/update/$id",
      data: {
        "status": "cancelled",
        "order_status": "cancelled",
        "payment_status": "cancelled",
      },
    );
  }

  Future<Response> createItem(Map<String, dynamic> body) async {
    final dio = await DioClient.getAdminDio();
    return dio.post("admin/item/create", data: body);
  }

  Future<Response> getOrderSummary({
    required String date,
    int? branchId,
    int? restaurantId,
  }) async {
    final dio = await DioClient.getAdminDio();
    final params = <String, dynamic>{
      "date": date,
      "from_date": date,
      "to_date": date,
      if (branchId != null) "branch_id": branchId,
      if (restaurantId != null) "restaurant_id": restaurantId,
    };

    final res = await dio.get("admin/order-summary", queryParameters: params);
    if (res.statusCode != null && res.statusCode! >= 400) {
      return dio.post("admin/order-summary", data: params);
    }
    return res;
  }
}
