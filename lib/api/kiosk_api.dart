import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:api_selfxo_project/services/auth_service.dart';
import 'package:api_selfxo_project/services/restaurant_api_service.dart';
import 'package:api_selfxo_project/services/session_manager.dart';
import 'dio_client.dart';

class KioskApi {
  static const String _webRestaurantsCacheKey = "web_restaurants_cache";
  static const String _productsCacheKey = "kiosk_products_cache";
  static const int _defaultWebRestaurantsBranchId = 4;
  static const Duration _webRestaurantsMemoryTtl = Duration(minutes: 3);
  static const Duration _webRestaurantsFailureBackoff = Duration(seconds: 5);
  static const Duration _productsCacheTtl = Duration(minutes: 8);
  static Future<List<Map<String, dynamic>>>? _webRestaurantsInFlight;
  static int? _webRestaurantsInFlightBranchId;
  static List<Map<String, dynamic>>? _webRestaurantsMemoryCache;
  static int? _webRestaurantsMemoryBranchId;
  static DateTime? _webRestaurantsMemoryCachedAt;
  static DateTime? _webRestaurantsLastFailureAt;
  static Future<Response>? _productsInFlight;
  static String? _productsInFlightRestaurantKey;
  static Response? _productsMemoryCache;
  static String? _productsMemoryRestaurantKey;
  static DateTime? _productsMemoryCachedAt;

  // =========================================================
  // RESTAURANT + KIOSK SETTINGS
  // =========================================================
  Future<Response> getRestaurantData() async {
    final timer = Stopwatch()..start();
    final dio = await DioClient.getAuthedDio();
    try {
      return await dio.get("kiosks/getRestaurantData");
    } finally {
      timer.stop();
      kioskLog(
        "getRestaurantData duration=${timer.elapsedMilliseconds}ms",
        tag: "RESTAURANT_API",
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAllRestaurantsWeb({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final branchId = await _currentWebRestaurantsBranchId();
    final memory = _webRestaurantsMemoryCache;
    final memoryCachedAt = _webRestaurantsMemoryCachedAt;
    final memoryFresh = memory != null &&
        memory.isNotEmpty &&
        _webRestaurantsMemoryBranchId == branchId &&
        memoryCachedAt != null &&
        now.difference(memoryCachedAt) <= _webRestaurantsMemoryTtl;
    if (!forceRefresh && memoryFresh) {
      return memory;
    }

    final lastFailureAt = _webRestaurantsLastFailureAt;
    if (!forceRefresh &&
        lastFailureAt != null &&
        now.difference(lastFailureAt) < _webRestaurantsFailureBackoff) {
      final cached = await _readCachedRestaurants(branchId);
      if (cached.isNotEmpty) {
        _setWebRestaurantsMemoryCache(cached, branchId);
        return cached;
      }
      throw const RestaurantApiException(
        type: RestaurantApiErrorType.unknown,
        message: "Restaurant service is temporarily unavailable.",
      );
    }

    final pending = _webRestaurantsInFlight;
    if (pending != null && _webRestaurantsInFlightBranchId == branchId) {
      kioskLog(
        'Using in-flight restaurant request',
        tag: 'WEB_RESTAURANTS',
      );
      return pending;
    }

    final future = _loadAllRestaurantsWeb(
      forceRefresh: forceRefresh,
      branchId: branchId,
    );
    _webRestaurantsInFlight = future;
    _webRestaurantsInFlightBranchId = branchId;
    try {
      final list = await future;
      if (list.isNotEmpty) {
        _setWebRestaurantsMemoryCache(list, branchId);
      }
      return list;
    } finally {
      if (identical(_webRestaurantsInFlight, future)) {
        _webRestaurantsInFlight = null;
        _webRestaurantsInFlightBranchId = null;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAllRestaurantsWeb({
    required bool forceRefresh,
    required int branchId,
  }) async {
    try {
      final list = await RestaurantApiService.instance.fetchRestaurants();
      _webRestaurantsLastFailureAt = null;
      await _cacheRestaurants(list, branchId);
      return list;
    } catch (e, stackTrace) {
      kioskLogError(
        'Restaurant live load failed: $e',
        tag: 'WEB_RESTAURANTS',
        error: e,
        stackTrace: stackTrace,
      );

      if (!forceRefresh) {
        final cached = await _readCachedRestaurants(branchId);
        if (cached.isNotEmpty) {
          _webRestaurantsLastFailureAt = null;
          kioskLog(
            'Using ${cached.length} cached restaurants after live load failure',
            tag: 'WEB_RESTAURANTS',
          );
          return cached;
        }
      }

      _webRestaurantsLastFailureAt = DateTime.now();
      rethrow;
    }
  }

  void _setWebRestaurantsMemoryCache(
      List<Map<String, dynamic>> restaurants, int branchId) {
    _webRestaurantsMemoryCache = List<Map<String, dynamic>>.from(restaurants);
    _webRestaurantsMemoryBranchId = branchId;
    _webRestaurantsMemoryCachedAt = DateTime.now();
  }

  Future<void> _cacheRestaurants(
      List<Map<String, dynamic>> restaurants, int branchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _webRestaurantsScopedCacheKey(branchId),
        jsonEncode(restaurants),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _readCachedRestaurants(
      int branchId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webRestaurantsScopedCacheKey(branchId));
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry("$key", value)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<int> _currentWebRestaurantsBranchId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt("branch_id") ??
        int.tryParse(prefs.getString("branch_id")?.trim() ?? "") ??
        _defaultWebRestaurantsBranchId;
  }

  String _webRestaurantsScopedCacheKey(int branchId) {
    return "${_webRestaurantsCacheKey}_branch_$branchId";
  }

  // =========================================================
  // PRODUCTS
  // =========================================================
  Future<Response> getProducts({bool forceRefresh = false}) async {
    final restaurantKey = await _currentRestaurantCacheKey();
    final memoryFresh = _productsMemoryCache != null &&
        _productsMemoryRestaurantKey == restaurantKey &&
        _productsMemoryCachedAt != null &&
        DateTime.now().difference(_productsMemoryCachedAt!) <=
            _productsCacheTtl;
    if (!forceRefresh && memoryFresh) {
      kioskLog(
        "getProducts memory cache hit restaurant=$restaurantKey",
        tag: "PRODUCTS_API",
      );
      return _productsMemoryCache!;
    }

    if (!forceRefresh) {
      final diskCache = await _readCachedProducts(restaurantKey);
      if (diskCache != null) {
        _setProductsMemoryCache(diskCache, restaurantKey);
        kioskLog(
          "getProducts disk cache hit restaurant=$restaurantKey",
          tag: "PRODUCTS_API",
        );
        unawaited(getProducts(forceRefresh: true));
        return diskCache;
      }
    }

    final pending = _productsInFlight;
    if (pending != null && _productsInFlightRestaurantKey == restaurantKey) {
      kioskLog(
        "getProducts using in-flight request restaurant=$restaurantKey",
        tag: "PRODUCTS_API",
      );
      return pending;
    }

    final future = _loadProductsFromNetwork(restaurantKey);
    _productsInFlight = future;
    _productsInFlightRestaurantKey = restaurantKey;
    try {
      return await future;
    } finally {
      if (identical(_productsInFlight, future)) {
        _productsInFlight = null;
        _productsInFlightRestaurantKey = null;
      }
    }
  }

  Future<void> warmProductsCache() async {
    try {
      await getProducts(forceRefresh: false);
    } catch (e) {
      kioskLog("warmProductsCache skipped: $e", tag: "PRODUCTS_API");
    }
  }

  Future<Response> _loadProductsFromNetwork(String restaurantKey) async {
    final timer = Stopwatch()..start();
    try {
      final dio = await DioClient.getAuthedDio();
      final res = await dio.get("kiosks/getProducts");
      if (res.statusCode == 401 || res.statusCode == 403) {
        final recovered = await _recoverWebKioskAuthToken();
        if (recovered) {
          final retryDio = await DioClient.getAuthedDio();
          final retryRes = await retryDio.get("kiosks/getProducts");
          await _cacheProducts(retryRes, restaurantKey);
          return retryRes;
        }
      }
      await _cacheProducts(res, restaurantKey);
      return res;
    } catch (e) {
      if (kIsWeb) {
        final recovered = await _recoverWebKioskAuthToken();
        if (recovered) {
          final dio = await DioClient.getAuthedDio();
          final res = await dio.get("kiosks/getProducts");
          await _cacheProducts(res, restaurantKey);
          return res;
        }
      }
      final cached = await _readCachedProducts(restaurantKey);
      if (cached != null) return cached;
      rethrow;
    } finally {
      timer.stop();
      kioskLog(
        "getProducts network duration=${timer.elapsedMilliseconds}ms "
        "restaurant=$restaurantKey",
        tag: "PRODUCTS_API",
      );
    }
  }

  Future<void> _cacheProducts(Response response, String restaurantKey) async {
    final statusCode = response.statusCode ?? 0;
    final data = response.data;
    if (statusCode >= 400 || data == null) return;
    _setProductsMemoryCache(response, restaurantKey);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _productsScopedCacheKey(restaurantKey),
        jsonEncode({
          "cached_at": DateTime.now().millisecondsSinceEpoch,
          "data": data,
        }),
      );
    } catch (_) {}
  }

  Future<Response?> _readCachedProducts(String restaurantKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_productsScopedCacheKey(restaurantKey));
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final cachedAtMs =
          int.tryParse(decoded["cached_at"]?.toString() ?? "") ?? 0;
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
      if (DateTime.now().difference(cachedAt) > _productsCacheTtl) {
        return null;
      }
      return Response(
        requestOptions: RequestOptions(path: "kiosks/getProducts"),
        statusCode: 200,
        data: decoded["data"],
      );
    } catch (_) {
      return null;
    }
  }

  void _setProductsMemoryCache(Response response, String restaurantKey) {
    _productsMemoryCache = response;
    _productsMemoryRestaurantKey = restaurantKey;
    _productsMemoryCachedAt = DateTime.now();
  }

  Future<String> _currentRestaurantCacheKey() async {
    final prefs = await SharedPreferences.getInstance();
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
    return "${_productsCacheKey}_$safeKey";
  }

  Future<bool> _recoverWebKioskAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restaurantId = prefs.getString("restaurant_id")?.trim() ?? "";
      if (restaurantId.isEmpty) return false;
      kioskLog(
        "auth token missing or invalid while loading menu; forcing background kiosk auth recovery",
        tag: 'WEB_RESTAURANTS',
      );
      return await AuthService().initializeKiosk(force: true);
    } catch (_) {
      return false;
    }
  }

  // =========================================================
  // CREATE ORDER
  // =========================================================
  Future<Response> createOrder({
    required String orderType,
    required List<Map<String, dynamic>> orderItems,
  }) async {
    Future<Response> callCreateOrder() async {
      final dio = await DioClient.getAuthedDio();
      final prefs = await SharedPreferences.getInstance();
      final restaurantId = prefs.getString("restaurant_id")?.trim() ?? "";
      final deviceId = prefs.getString("device_id")?.trim() ?? "";
      final customerMobile = prefs.getString("customer_mobile")?.trim() ?? "";
      final customerFirebaseUid =
          prefs.getString("customer_firebase_uid")?.trim() ?? "";
      final customerFirebaseToken =
          prefs.getString("customer_firebase_token")?.trim() ?? "";
      final customerBlockName =
          prefs.getString("customer_block_name")?.trim() ?? "";
      final branchId = prefs.getInt("branch_id");
      int? pwaCustomerId;
      if (await SessionManager.instance.hasSession()) {
        final customer = await SessionManager.instance.getCustomer();
        final rawId = customer?['id'];
        if (rawId != null) {
          final parsed = int.tryParse(rawId.toString());
          if (parsed != null && parsed > 0) {
            pwaCustomerId = parsed;
          }
        }
      }
      final body = <String, dynamic>{
        "orderType": orderType,
        "orderItemList": orderItems,
        if (restaurantId.isNotEmpty) "restaurant_id": restaurantId,
        if (deviceId.isNotEmpty) "device_id": deviceId,
        if (customerMobile.isNotEmpty) "customer_mobile": customerMobile,
        if (customerFirebaseUid.isNotEmpty)
          "customer_firebase_uid": customerFirebaseUid,
        if (customerBlockName.isNotEmpty)
          "customer_block_name": customerBlockName,
        if (branchId != null) "branch_id": branchId,
        if (pwaCustomerId != null) "pwa_customer_id": pwaCustomerId,
      };
      kioskLog(
        "createOrder orderType=$orderType items=${orderItems.length} "
        "restaurant_id=${restaurantId.isEmpty ? "-" : restaurantId} "
        "device_id=${deviceId.isEmpty ? "-" : deviceId} "
        "customer_mobile=${customerMobile.isEmpty ? "-" : customerMobile} "
        "pwa_customer_id=${pwaCustomerId ?? "-"}",
        tag: "ORDER_CREATE",
      );
      return dio.post(
        "kiosks/createOrder",
        data: body,
        options: customerFirebaseToken.isEmpty
            ? null
            : Options(headers: {"X-Firebase-Id-Token": customerFirebaseToken}),
      );
    }

    try {
      return await callCreateOrder();
    } on DioException catch (e, st) {
      kioskLogError(
        "createOrder failed status=${e.response?.statusCode ?? 0} "
        "body=${e.response?.data}",
        tag: "ORDER_CREATE",
        error: e,
        stackTrace: st,
      );
      if (kIsWeb &&
          (e.response?.statusCode == 401 || e.response?.statusCode == 403)) {
        final recovered = await _recoverWebKioskAuthToken();
        if (recovered) {
          return await callCreateOrder();
        }
      }
      rethrow;
    }
  }

  // =========================================================
  // GENERATE QR
  // =========================================================
  Future<Response> generateQr({required int orderId}) async {
    final dio = await DioClient.getAuthedDio();
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString("device_id")?.trim() ?? "";
    final restaurantId = prefs.getString("restaurant_id")?.trim() ?? "";
    final path = "kiosks/orders/$orderId/generateQr";

    Future<Response> callGetWithDeviceHeader(String? xDeviceId) {
      return dio.get(
        path,
        queryParameters: {
          if (restaurantId.isNotEmpty) "restaurant_id": restaurantId,
          if (deviceId.isNotEmpty) "device_id": deviceId,
        },
        options: Options(
          headers: {
            if (xDeviceId != null && xDeviceId.trim().isNotEmpty)
              "X-DEVICE-ID": xDeviceId.trim(),
          },
        ),
      );
    }

    try {
      return await callGetWithDeviceHeader(deviceId);
    } on DioException catch (e, st) {
      final status = e.response?.statusCode ?? 0;
      final body = e.response?.data;
      kioskLogError(
        "generateQr failed status=$status order_id=$orderId "
        "device_id=$deviceId restaurant_id=$restaurantId body=$body",
        tag: "QR_GEN",
        error: e,
        stackTrace: st,
      );

      // Fallback 1: some environments fail when X-DEVICE-ID is present.
      if (deviceId.isNotEmpty && status >= 500) {
        try {
          kioskLog(
            "retry generateQr without X-DEVICE-ID order_id=$orderId",
            tag: "QR_GEN",
          );
          return await callGetWithDeviceHeader(null);
        } on DioException catch (retryE, retrySt) {
          kioskLogError(
            "generateQr retry(no-header) failed status="
            "${retryE.response?.statusCode ?? 0} order_id=$orderId "
            "restaurant_id=$restaurantId body=${retryE.response?.data}",
            tag: "QR_GEN",
            error: retryE,
            stackTrace: retrySt,
          );
        }
      }

      // Fallback 2: some backends expose QR generation as POST.
      if (status == 405 || status >= 500) {
        try {
          kioskLog(
            "retry generateQr via POST order_id=$orderId device_id=$deviceId",
            tag: "QR_GEN",
          );
          return await dio.post(
            path,
            data: {
              if (restaurantId.isNotEmpty) "restaurant_id": restaurantId,
              if (deviceId.isNotEmpty) "device_id": deviceId,
            },
            options: Options(
              headers: {
                if (deviceId.isNotEmpty) "X-DEVICE-ID": deviceId,
              },
            ),
          );
        } on DioException catch (postE, postSt) {
          kioskLogError(
            "generateQr retry(POST) failed status="
            "${postE.response?.statusCode ?? 0} order_id=$orderId "
            "restaurant_id=$restaurantId body=${postE.response?.data}",
            tag: "QR_GEN",
            error: postE,
            stackTrace: postSt,
          );
        }
      }

      rethrow;
    }
  }

  // =========================================================
  // CHECK PAYMENT
  // =========================================================
  Future<Response> checkPayment(int orderId) async {
    final dio = await DioClient.getAuthedDio();
    return dio.get("kiosks/orders/$orderId/checkPayment");
  }

  // =========================================================
  // GET ORDER DETAILS
  // =========================================================
  Future<Response> getOrderDetails(int orderId) async {
    final dio = await DioClient.getAuthedDio();
    return dio.get("kiosks/orders/$orderId");
  }

  // =========================================================
  // PRINTER (BACKEND + CAPACITOR)
  // =========================================================

  /// 🖨️ Get available printers (Angular + Capacitor side)
  /// Same as EpsonUSBPrinter.getPrinterList()
  Future<List<Map<String, dynamic>>> getPrinterList() async {
    final dio = await DioClient.getAuthedDio();
    final res = await dio.get("kiosks/printers");

    final List list = res.data["printers"] ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// 🖨️ Save selected printer for this kiosk
  /// Same as getSelectedPrinter() logic
  Future<void> saveSelectedPrinter(String productId) async {
    final dio = await DioClient.getAuthedDio();
    await dio.post("kiosks/printers/select", data: {"product_id": productId});
  }

  /// 🖨️ Get already selected printer (optional)
  Future<Map<String, dynamic>?> getSelectedPrinter() async {
    final dio = await DioClient.getAuthedDio();
    final res = await dio.get("kiosks/printers/selected");
    return res.data["printer"];
  }

  // =========================================================
  // DEVICE MONITORING
  // =========================================================

  /// Ping device (used for printer/device status)
  /// GET kiosks/ping/{deviceId}/default
  Future<Response> pingDevice() async {
    final dio = await DioClient.getAuthedDio();
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString("device_id") ?? "default_device";

    return dio.get("kiosks/ping/$deviceId/default");
  }

  // =========================================================
  // PRINT RECEIPT (BACKEND HANDLES PRINTER)
  // =========================================================

  /// 🔥 Print receipt
  /// Angular + Capacitor + Epson handles actual printing
  Future<Response> printReceipt(int orderId) async {
    final dio = await DioClient.getAuthedDio();
    return dio.get("kiosks/orders/printReceipt/$orderId");
  }

  // =========================================================
  // ORDER SUMMARY (CATEGORY SUMMARY)
  // =========================================================

  Future<Response> getOrderSummary({
    required String date,
    int? branchId,
    int? restaurantId,
  }) async {
    final dio = await DioClient.getAuthedDio();
    final params = <String, dynamic>{
      "date": date,
      "from_date": date,
      "to_date": date,
      if (branchId != null) "branch_id": branchId,
      if (restaurantId != null) "restaurant_id": restaurantId,
    };

    try {
      return await dio.post("kiosk/order-summary", data: params);
    } catch (_) {
      return dio.get("kiosk/order-summary", queryParameters: params);
    }
  }
}
