import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:api_selfxo_project/services/auth_service.dart';
import 'dio_client.dart';
import 'web_api_config.dart';

class KioskApi {
  static const String _webRestaurantsCacheKey = "web_restaurants_cache";
  static const Duration _webRestaurantsMemoryTtl = Duration(minutes: 3);
  static const Duration _webRestaurantsFailureBackoff = Duration(seconds: 5);
  static const bool _allowCrossOriginOnLocalhost = bool.fromEnvironment(
    "SELFX_WEB_ALLOW_CROSS_ORIGIN_ON_LOCALHOST",
    defaultValue: false,
  );
  static Future<List<Map<String, dynamic>>>? _webRestaurantsInFlight;
  static bool _localhostPolicyLogged = false;
  static List<Map<String, dynamic>>? _webRestaurantsMemoryCache;
  static DateTime? _webRestaurantsMemoryCachedAt;
  static DateTime? _webRestaurantsLastFailureAt;

  // =========================================================
  // RESTAURANT + KIOSK SETTINGS
  // =========================================================
  Future<Response> getRestaurantData() async {
    final dio = await DioClient.getAuthedDio();
    return dio.get("kiosks/getRestaurantData");
  }

  Future<List<Map<String, dynamic>>> getAllRestaurantsWeb({
    bool forceRefresh = false,
  }) async {
    if (!kIsWeb) return const [];
    final now = DateTime.now();
    final memory = _webRestaurantsMemoryCache;
    final memoryCachedAt = _webRestaurantsMemoryCachedAt;
    final memoryFresh = memory != null &&
        memory.isNotEmpty &&
        memoryCachedAt != null &&
        now.difference(memoryCachedAt) <= _webRestaurantsMemoryTtl;
    if (!forceRefresh && memoryFresh) {
      return memory;
    }

    final lastFailureAt = _webRestaurantsLastFailureAt;
    if (!forceRefresh &&
        lastFailureAt != null &&
        now.difference(lastFailureAt) < _webRestaurantsFailureBackoff) {
      final cached = await _readCachedRestaurants();
      if (cached.isNotEmpty) {
        _setWebRestaurantsMemoryCache(cached);
        return cached;
      }
      return const [];
    }

    final pending = _webRestaurantsInFlight;
    if (pending != null) {
      return pending;
    }

    final future = _loadAllRestaurantsWeb();
    _webRestaurantsInFlight = future;
    try {
      final list = await future;
      if (list.isNotEmpty) {
        _setWebRestaurantsMemoryCache(list);
      }
      return list;
    } finally {
      if (identical(_webRestaurantsInFlight, future)) {
        _webRestaurantsInFlight = null;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAllRestaurantsWeb() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 18),
        sendTimeout: null,
        headers: const {
          "Accept": "application/json",
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final candidates = _restaurantEndpointCandidates();
    for (final endpoint in candidates) {
      try {
        kioskLog(
          'Loading web restaurants from $endpoint',
          tag: 'WEB_RESTAURANTS',
        );
        final initial = await dio.get(endpoint);
        final statusCode = initial.statusCode ?? 0;
        if (statusCode >= 400) {
          kioskLog(
            'Endpoint $endpoint returned $statusCode; trying next',
            tag: 'WEB_RESTAURANTS',
          );
          continue;
        }

        final direct = _extractRestaurantList(initial.data);
        if (direct.isNotEmpty) {
          _webRestaurantsLastFailureAt = null;
          await _cacheRestaurants(direct);
          kioskLog(
            'Loaded ${direct.length} restaurants directly from JSON',
            tag: 'WEB_RESTAURANTS',
          );
          return direct;
        }

        final fallbackUrl = _deriveRestaurantApiUrl(
          configuredUrl: endpoint,
          responseData: initial.data,
        );
        if (fallbackUrl == null || fallbackUrl == endpoint) continue;

        kioskLog(
          'Falling back to restaurant API $fallbackUrl',
          tag: 'WEB_RESTAURANTS',
        );
        final fallback = await dio.get(fallbackUrl);
        final fallbackStatus = fallback.statusCode ?? 0;
        if (fallbackStatus >= 400) {
          kioskLog(
            'Fallback $fallbackUrl returned $fallbackStatus',
            tag: 'WEB_RESTAURANTS',
          );
          continue;
        }
        final list = _extractRestaurantList(fallback.data);
        if (list.isNotEmpty) {
          _webRestaurantsLastFailureAt = null;
          await _cacheRestaurants(list);
          kioskLog(
            'Loaded ${list.length} restaurants from fallback JSON',
            tag: 'WEB_RESTAURANTS',
          );
          return list;
        }
      } catch (e, stackTrace) {
        kioskLogError(
          'Restaurant endpoint failed [$endpoint]: $e',
          tag: 'WEB_RESTAURANTS',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    final cached = await _readCachedRestaurants();
    if (cached.isNotEmpty) {
      _webRestaurantsLastFailureAt = null;
      kioskLog(
        'Using ${cached.length} cached restaurants',
        tag: 'WEB_RESTAURANTS',
      );
      return cached;
    }

    _webRestaurantsLastFailureAt = DateTime.now();
    return const [];
  }

  void _setWebRestaurantsMemoryCache(List<Map<String, dynamic>> restaurants) {
    _webRestaurantsMemoryCache = List<Map<String, dynamic>>.from(restaurants);
    _webRestaurantsMemoryCachedAt = DateTime.now();
  }

  List<Map<String, dynamic>> _extractRestaurantList(dynamic raw) {
    final rawList = raw is List
        ? raw
        : raw is Map
            ? (raw["data"] ?? raw["restaurants"] ?? raw["items"])
            : null;
    if (rawList is! List) return const [];

    return rawList
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry("$key", value)))
        .toList();
  }

  String? _deriveRestaurantApiUrl({
    required String configuredUrl,
    required dynamic responseData,
  }) {
    final configuredUri = Uri.tryParse(configuredUrl);
    if (configuredUri == null || responseData is! String) return null;

    final html = responseData;
    final match = RegExp(
      r"""fetch\(\s*['"]([^'"]+)['"]\s*\)""",
      caseSensitive: false,
    ).firstMatch(html);
    final path = match?.group(1)?.trim();
    if (path == null || path.isEmpty) return null;

    return configuredUri.resolve(path).toString();
  }

  List<String> _restaurantEndpointCandidates() {
    final seen = <String>{};
    final candidates = <String>[];
    final webBaseUri = Uri.base;
    final restrictCrossOrigin =
        _isLocalDevHost(webBaseUri.host) && !_allowCrossOriginOnLocalhost;

    void addCandidate(
      String? raw, {
      bool allowCrossOrigin = true,
    }) {
      final value = raw?.trim();
      if (value == null || value.isEmpty) return;
      final parsed = Uri.tryParse(value);
      if (parsed == null) return;
      final uri = parsed.hasScheme ? parsed : webBaseUri.resolve(value);
      if (!uri.hasScheme || !uri.hasAuthority) return;
      if (!allowCrossOrigin && !_isSameOrigin(uri, webBaseUri)) return;
      final normalized = uri.toString();
      if (seen.add(normalized)) {
        candidates.add(normalized);
      }
    }

    if (restrictCrossOrigin) {
      addCandidate("/api/all-restaurants", allowCrossOrigin: false);
      addCandidate("api/all-restaurants", allowCrossOrigin: false);
      addCandidate(WebApiConfig.allRestaurantsUrl, allowCrossOrigin: false);
      final localConfigured = Uri.tryParse(WebApiConfig.baseUrl);
      if (localConfigured != null &&
          localConfigured.hasScheme &&
          localConfigured.hasAuthority) {
        addCandidate(
          localConfigured.resolve("all-restaurants").toString(),
          allowCrossOrigin: false,
        );
      }
      // Keep same-origin first for local proxy setups, but also try
      // known remote endpoints as fallback to avoid empty restaurant lists
      // when localhost proxy is unavailable.
      addCandidate(WebApiConfig.allRestaurantsUrl);
      final baseUri = Uri.tryParse(WebApiConfig.baseUrl);
      if (baseUri != null && baseUri.hasScheme && baseUri.hasAuthority) {
        addCandidate(baseUri.resolve("all-restaurants").toString());
      }
      addCandidate("https://gitam.sirixo.com/api/all-restaurants");
      addCandidate("https://selfpos.sirixo.com/api/all-restaurants");
      if (!_localhostPolicyLogged) {
        _localhostPolicyLogged = true;
        kioskLog(
          'Running on localhost; trying same-origin restaurant endpoints first, '
          'then remote fallback endpoints.',
          tag: 'WEB_RESTAURANTS',
        );
      }
      return candidates;
    }

    addCandidate(WebApiConfig.allRestaurantsUrl);
    final baseUri = Uri.tryParse(WebApiConfig.baseUrl);
    if (baseUri != null && baseUri.hasScheme && baseUri.hasAuthority) {
      addCandidate(baseUri.resolve("all-restaurants").toString());
    }
    addCandidate("/api/all-restaurants");
    addCandidate("api/all-restaurants");
    addCandidate("https://gitam.sirixo.com/api/all-restaurants");
    addCandidate("https://selfpos.sirixo.com/api/all-restaurants");

    return candidates;
  }

  bool _isLocalDevHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == "localhost" ||
        normalized == "127.0.0.1" ||
        normalized == "::1" ||
        normalized == "[::1]";
  }

  bool _isSameOrigin(Uri a, Uri b) {
    return a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        _effectivePort(a) == _effectivePort(b);
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    if (uri.scheme == "https") return 443;
    if (uri.scheme == "http") return 80;
    return -1;
  }

  Future<void> _cacheRestaurants(List<Map<String, dynamic>> restaurants) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_webRestaurantsCacheKey, jsonEncode(restaurants));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _readCachedRestaurants() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webRestaurantsCacheKey);
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

  // =========================================================
  // PRODUCTS
  // =========================================================
  Future<Response> getProducts() async {
    try {
      final dio = await DioClient.getAuthedDio();
      final res = await dio.get("kiosks/getProducts");
      return res;
    } catch (e) {
      if (kIsWeb) {
        final recovered = await _recoverWebKioskAuthToken();
        if (recovered) {
          final dio = await DioClient.getAuthedDio();
          final res = await dio.get("kiosks/getProducts");
          return res;
        }
      }
      rethrow;
    }
  }

  Future<bool> _recoverWebKioskAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restaurantId = prefs.getString("restaurant_id")?.trim() ?? "";
      if (restaurantId.isEmpty) return false;
      kioskLog(
        "auth token missing while loading menu; trying background kiosk auth recovery",
        tag: 'WEB_RESTAURANTS',
      );
      return await AuthService().initializeKiosk(force: false);
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
      final body = <String, dynamic>{
        "orderType": orderType,
        "orderItemList": orderItems,
        if (restaurantId.isNotEmpty) "restaurant_id": restaurantId,
        if (deviceId.isNotEmpty) "device_id": deviceId,
      };
      kioskLog(
        "createOrder orderType=$orderType items=${orderItems.length} "
        "restaurant_id=${restaurantId.isEmpty ? "-" : restaurantId} "
        "device_id=${deviceId.isEmpty ? "-" : deviceId}",
        tag: "ORDER_CREATE",
      );
      return dio.post("kiosks/createOrder", data: body);
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
