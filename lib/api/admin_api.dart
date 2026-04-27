import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dio_client.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';

class AdminApi {
  Future<Map<String, dynamic>> _resolveScope() async {
    final prefs = await SharedPreferences.getInstance();
    final scope = <String, dynamic>{};

    final restaurantId = prefs.getString("restaurant_id")?.trim() ?? "";
    if (restaurantId.isNotEmpty) {
      scope["restaurant_id"] = restaurantId;
    }

    return scope;
  }

  Map<String, dynamic> _mergeScopeIntoBody(
    Map<String, dynamic> body,
    Map<String, dynamic> scope,
  ) {
    final merged = <String, dynamic>{...scope, ...body};
    return merged;
  }

  Future<Response> _requestWithAdminFallback(
    Future<Response> Function(Dio dio) request,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final localBypass = prefs.getBool("admin_local_bypass") ?? false;
    final adminToken = prefs.getString("admin_token")?.trim() ?? "";

    if (adminToken == "LOCAL_BYPASS_TOKEN") {
      await prefs.remove("admin_token");
    }

    if (!localBypass && adminToken.isNotEmpty && adminToken != "LOCAL_BYPASS_TOKEN") {
      try {
        final adminDio = await DioClient.getAdminDio();
        final response = await request(adminDio);
        final code = response.statusCode ?? 0;
        if (code == 401 || code == 403) {
          kioskLog('admin token rejected ($code), trying kiosk token',
              tag: 'ADMIN_API');
        } else {
          return response;
        }
      } on DioException catch (e) {
        kioskLogError(
          'admin token request failed: ${e.message}',
          tag: 'ADMIN_API',
          error: e,
          stackTrace: e.stackTrace,
        );
      } catch (e) {
        kioskLogError('admin token request failed: $e',
            tag: 'ADMIN_API', error: e);
      }
    } else {
      kioskLog(
        localBypass
            ? 'local admin bypass active; skipping admin-token request'
            : 'admin token missing; skipping admin-token request',
        tag: 'ADMIN_API',
      );
    }

    try {
      final kioskDio = await DioClient.getAuthedDio();
      kioskLog('trying kiosk token fallback', tag: 'ADMIN_API');
      return request(kioskDio);
    } on DioException catch (e) {
      kioskLogError(
        'kiosk token fallback failed: ${e.message}',
        tag: 'ADMIN_API',
        error: e,
        stackTrace: e.stackTrace,
      );
    } catch (e) {
      kioskLogError('kiosk token fallback failed: $e',
          tag: 'ADMIN_API', error: e);
    }

    kioskLog('trying unauthenticated fallback', tag: 'ADMIN_API');
    final plainDio = DioClient.getDio();
    try {
      return await request(plainDio);
    } on DioException catch (e) {
      kioskLogError(
        'unauthenticated fallback failed: ${e.message}',
        tag: 'ADMIN_API',
        error: e,
        stackTrace: e.stackTrace,
      );
      rethrow;
    } catch (e) {
      kioskLogError('unauthenticated fallback failed: $e',
          tag: 'ADMIN_API', error: e);
      rethrow;
    }
  }

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
    final scope = await _resolveScope();
    return _requestWithAdminFallback(
      (dio) => dio.get(
        "admin/items",
        queryParameters: scope.isEmpty ? null : scope,
      ),
    );
  }

  Future<Response> getCategories() async {
    final scope = await _resolveScope();
    return _requestWithAdminFallback(
      (dio) => dio.get(
        "admin/categories",
        queryParameters: scope.isEmpty ? null : scope,
      ),
    );
  }

  Future<Response> getOrders(Map<String, dynamic> body) async {
    final scope = await _resolveScope();
    final payload = _mergeScopeIntoBody(body, scope);
    return _requestWithAdminFallback(
      (dio) => dio.post("admin/orders", data: payload),
    );
  }

  Future<Response> getOrder(String id) async {
    final scope = await _resolveScope();
    return _requestWithAdminFallback(
      (dio) => dio.get(
        "admin/order/$id",
        queryParameters: scope.isEmpty ? null : scope,
      ),
    );
  }

  Future<Response> getSettings() async {
    final scope = await _resolveScope();
    return _requestWithAdminFallback(
      (dio) => dio.get(
        "admin/settings",
        queryParameters: scope.isEmpty ? null : scope,
      ),
    );
  }

  Future<Response> updateSettings(Map<String, dynamic> body) async {
    final scope = await _resolveScope();
    final payload = _mergeScopeIntoBody(body, scope);
    return _requestWithAdminFallback(
      (dio) => dio.put("admin/updateSettings", data: payload),
    );
  }

  Future<Response> updateCategory(String id, Map<String, dynamic> body) async {
    final scope = await _resolveScope();
    final payload = _mergeScopeIntoBody(body, scope);
    return _requestWithAdminFallback(
      (dio) => dio.put("admin/category/update/$id", data: payload),
    );
  }

  Future<Response> createCategory(Map<String, dynamic> body) async {
    final scope = await _resolveScope();
    final payload = _mergeScopeIntoBody(body, scope);
    return _requestWithAdminFallback(
      (dio) => dio.post("admin/category/create", data: payload),
    );
  }

  Future<Response> updateItem(String id, Map<String, dynamic> body) async {
    final scope = await _resolveScope();
    final payload = _mergeScopeIntoBody(body, scope);
    return _requestWithAdminFallback(
      (dio) => dio.put("admin/item/update/$id", data: payload),
    );
  }

  Future<Response> cancelOrder(String id) async {
    final scope = await _resolveScope();
    final payload = _mergeScopeIntoBody({
      "status": "cancelled",
      "order_status": "cancelled",
      "payment_status": "cancelled",
    }, scope);
    return _requestWithAdminFallback(
      (dio) => dio.put(
        "admin/order/update/$id",
        data: payload,
      ),
    );
  }

  Future<Response> createItem(Map<String, dynamic> body) async {
    final scope = await _resolveScope();
    final payload = _mergeScopeIntoBody(body, scope);
    return _requestWithAdminFallback(
      (dio) => dio.post("admin/item/create", data: payload),
    );
  }

  Future<Response> getOrderSummary({
    required String date,
    int? branchId,
    int? restaurantId,
  }) async {
    final scope = await _resolveScope();
    return _requestWithAdminFallback((dio) async {
      final params = <String, dynamic>{
        "date": date,
        "from_date": date,
        "to_date": date,
        if (branchId != null) "branch_id": branchId,
        if (restaurantId != null) "restaurant_id": restaurantId else ...{
          if (scope["restaurant_id"] != null)
            "restaurant_id": scope["restaurant_id"],
        },
      };
      final res = await dio.get("admin/order-summary", queryParameters: params);
      if (res.statusCode != null && res.statusCode! >= 400) {
        return dio.post("admin/order-summary", data: params);
      }
      return res;
    });
  }
}
