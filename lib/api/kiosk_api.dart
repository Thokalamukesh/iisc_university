import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dio_client.dart';
import 'web_api_config.dart';

class KioskApi {
  static const String _webRestaurantsCacheKey = "web_restaurants_cache";
  static const bool _allowCrossOriginOnLocalhost = bool.fromEnvironment(
    "SELFX_WEB_ALLOW_CROSS_ORIGIN_ON_LOCALHOST",
    defaultValue: false,
  );

  // =========================================================
  // RESTAURANT + KIOSK SETTINGS
  // =========================================================
  Future<Response> getRestaurantData() async {
    final dio = await DioClient.getAuthedDio();
    return dio.get("kiosks/getRestaurantData");
  }

  Future<List<Map<String, dynamic>>> getAllRestaurantsWeb() async {
    if (!kIsWeb) return const [];

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
      kioskLog(
        'Using ${cached.length} cached restaurants',
        tag: 'WEB_RESTAURANTS',
      );
      return cached;
    }

    return const [];
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
      kioskLog(
        'Running on localhost; using same-origin restaurant endpoints only '
        '(set SELFX_WEB_ALLOW_CROSS_ORIGIN_ON_LOCALHOST=true to override).',
        tag: 'WEB_RESTAURANTS',
      );
      return candidates;
    }

    addCandidate(WebApiConfig.allRestaurantsUrl);
    final baseUri = Uri.tryParse(WebApiConfig.baseUrl);
    if (baseUri != null && baseUri.hasScheme && baseUri.hasAuthority) {
      addCandidate(baseUri.resolve("all-restaurants").toString());
    }
    addCandidate("/api/all-restaurants");
    addCandidate("api/all-restaurants");

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
    final dio = await DioClient.getAuthedDio();
    final res = await dio.get("kiosks/getProducts");
    return res;
  }

  // =========================================================
  // CREATE ORDER
  // =========================================================
  Future<Response> createOrder({
    required String orderType,
    required List<Map<String, dynamic>> orderItems,
  }) async {
    final dio = await DioClient.getAuthedDio();
    return dio.post(
      "kiosks/createOrder",
      data: {"orderType": orderType, "orderItemList": orderItems},
    );
  }

  // =========================================================
  // GENERATE QR
  // =========================================================
  Future<Response> generateQr({required int orderId}) async {
    final dio = await DioClient.getAuthedDio();
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString("device_id");

    return dio.get(
      "kiosks/orders/$orderId/generateQr",
      options: Options(
        headers: {
          if (deviceId != null && deviceId.isNotEmpty) "X-DEVICE-ID": deviceId,
        },
      ),
    );
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
