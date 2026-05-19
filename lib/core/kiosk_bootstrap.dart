import 'package:shared_preferences/shared_preferences.dart';
import '../api/dio_client.dart';
import '../api/web_api_config.dart';
import 'device_info.dart';
import 'package:dio/dio.dart';

class DeviceBootstrap {
  static bool _isInvalidDeviceCandidate(String value) {
    final id = value.trim().toLowerCase();
    if (id.isEmpty) return true;
    return id == "unknown_device" ||
        id == "unknown_ios" ||
        id.startsWith("unknown_device_") ||
        id.startsWith("unknown_ios_");
  }

  static String _registeredDeviceKey(String deviceId) {
    return "kiosk_registered_device_$deviceId";
  }

  static bool _isWebGeneratedDeviceId(String deviceId) {
    final id = deviceId.trim().toLowerCase();
    return id.startsWith("web_") || id.startsWith("web_base_");
  }

  static bool _shouldProbeExistingToken(
    SharedPreferences prefs,
    String deviceId,
  ) {
    if (!_isWebGeneratedDeviceId(deviceId)) return true;
    return prefs.getBool(_registeredDeviceKey(deviceId)) ?? false;
  }

  static Future<Map<String, String>?> _findRestaurantByAnyId(
      String value) async {
    final needle = value.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
        headers: const {"Accept": "application/json"},
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final endpoints = <String>[
      WebApiConfig.allRestaurantsUrl,
      "http://127.0.0.1:8000/api/all-restaurants",
    ];
    for (final endpoint in endpoints) {
      final uri = Uri.tryParse(endpoint);
      final isDeprecatedRestaurantsEndpoint =
          uri?.host.toLowerCase() == "selfpos.sirixo.com" &&
              uri?.path.toLowerCase() == "/api/all-restaurants";
      if (isDeprecatedRestaurantsEndpoint) continue;
      try {
        final res = await dio.get(endpoint);
        if ((res.statusCode ?? 0) >= 400) continue;
        final data = res.data;
        final rawList = data is List
            ? data
            : (data is Map
                ? (data["data"] ?? data["restaurants"] ?? data["items"])
                : null);
        if (rawList is! List) continue;
        for (final item in rawList.whereType<Map>()) {
          final mapped = item.map((k, v) => MapEntry("$k", "$v"));
          final id = (mapped["id"] ?? "").trim().toLowerCase();
          final hash = (mapped["hash"] ?? "").trim().toLowerCase();
          if (needle == id || needle == hash) {
            return {
              "id": mapped["id"]?.trim() ?? "",
              "hash": mapped["hash"]?.trim() ?? "",
              "name": mapped["name"]?.trim() ?? "",
            };
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<List<String>> _resolveRegistrationRestaurantKeys(
    SharedPreferences prefs,
    String restaurantId,
  ) async {
    final keys = <String>[];
    void addKey(String? raw) {
      final value = raw?.trim() ?? "";
      if (value.isEmpty) return;
      if (!keys.contains(value)) keys.add(value);
    }

    final storedId = prefs.getString("restaurant_id")?.trim() ?? "";
    final storedHash = prefs.getString("restaurant_hash")?.trim() ?? "";
    final normalized = restaurantId.trim();
    addKey(storedId);
    addKey(storedHash);
    addKey(normalized);

    final lookupCandidates = <String>[
      if (storedHash.isNotEmpty) storedHash,
      if (normalized.isNotEmpty) normalized,
      if (storedId.isNotEmpty) storedId,
    ];
    for (final candidate in lookupCandidates) {
      final matched = await _findRestaurantByAnyId(candidate);
      if (matched == null) continue;
      final id = matched["id"]?.trim() ?? "";
      final hash = matched["hash"]?.trim() ?? "";
      final name = matched["name"]?.trim() ?? "";
      if (id.isNotEmpty) await prefs.setString("restaurant_id", id);
      if (hash.isNotEmpty) await prefs.setString("restaurant_hash", hash);
      if (name.isNotEmpty) await prefs.setString("restaurant_name", name);
      addKey(id);
      addKey(hash);
      break;
    }

    keys.sort((a, b) {
      final aIsNumeric = RegExp(r'^\d+$').hasMatch(a);
      final bIsNumeric = RegExp(r'^\d+$').hasMatch(b);
      if (aIsNumeric == bIsNumeric) return 0;
      return aIsNumeric ? 1 : -1;
    });
    return keys;
  }

  static Future<void> ensureDeviceReady() async {
    final prefs = await SharedPreferences.getInstance();
    final restaurantId = await _ensureRestaurantId(prefs);
    if (restaurantId == null || restaurantId.isEmpty) {
      throw Exception("RESTAURANT_NOT_CONFIGURED");
    }
    final registrationRestaurantKeys = await _resolveRegistrationRestaurantKeys(
      prefs,
      restaurantId,
    );
    if (registrationRestaurantKeys.isEmpty) {
      throw Exception("RESTAURANT_KEY_RESOLUTION_FAILED");
    }

    // =========================================================
    // 1️⃣ DEVICE ID
    // =========================================================
    final resolvedDeviceId = await DeviceInfoUtil.getDeviceId(
      restaurantId: restaurantId,
    );
    final resolvedBaseDeviceId = await DeviceInfoUtil.getBaseDeviceId();
    final storedDeviceId = prefs.getString("device_uuid")?.trim() ?? "";
    final candidateDeviceIds = <String>[
      resolvedDeviceId.trim(),
      if (resolvedBaseDeviceId.trim().isNotEmpty) resolvedBaseDeviceId.trim(),
      if (storedDeviceId.isNotEmpty) storedDeviceId,
    ];
    final uniqueDeviceIds = <String>[];
    for (final id in candidateDeviceIds) {
      if (_isInvalidDeviceCandidate(id)) continue;
      if (!uniqueDeviceIds.contains(id)) uniqueDeviceIds.add(id);
    }
    if (uniqueDeviceIds.isEmpty) {
      throw Exception("DEVICE_ID_RESOLUTION_FAILED");
    }
    await prefs.setString("device_uuid", uniqueDeviceIds.first);
    await prefs.setString("device_id", uniqueDeviceIds.first);

    // =========================================================
    // 2️⃣ TOKEN EXISTS → DONE
    // =========================================================
    final existingToken = prefs.getString("auth_token");
    if (existingToken != null && existingToken.isNotEmpty) {
      return;
    }

    final dio = DioClient.getDio();

    // =========================================================
    // 3️⃣ TRY GET TOKEN
    // =========================================================
    for (final deviceId in uniqueDeviceIds) {
      if (!_shouldProbeExistingToken(prefs, deviceId)) {
        continue;
      }
      try {
        final res = await dio.get("kiosks/getToken/$deviceId");
        final token = res.data?["token"];
        if (token != null && token.toString().isNotEmpty) {
          await prefs.setString("auth_token", token.toString());
          await prefs.setString("device_uuid", deviceId);
          await prefs.setString("device_id", deviceId);
          await prefs.setBool(_registeredDeviceKey(deviceId), true);
          return;
        }
      } catch (_) {
        // ignore and try next candidate
      }
    }

    // =========================================================
    // 4️⃣ REGISTER DEVICE
    // =========================================================
    Object? lastRegisterError;
    for (final deviceId in uniqueDeviceIds) {
      for (final registrationRestaurantId in registrationRestaurantKeys) {
        try {
          final registerRes = await dio.post(
            "kiosks/register",
            data: {
              "device_id": deviceId,
              "name": "Kiosk Device",
              "restaurant_id": registrationRestaurantId,
            },
          );

          final token = registerRes.data?["token"];
          if (token == null || token.toString().isEmpty) {
            lastRegisterError = Exception(
              "TOKEN_MISSING_FOR_DEVICE_${deviceId}_$registrationRestaurantId",
            );
            continue;
          }
          await prefs.setString("auth_token", token.toString());
          await prefs.setString("device_uuid", deviceId);
          await prefs.setString("device_id", deviceId);
          await prefs.setBool(_registeredDeviceKey(deviceId), true);
          return;
        } catch (e) {
          lastRegisterError = e;
          continue;
        }
      }
    }
    throw Exception("DEVICE_REGISTRATION_FAILED: $lastRegisterError");
  }

  static Future<String?> _ensureRestaurantId(SharedPreferences prefs) async {
    final storedId = prefs.getString("restaurant_id")?.trim() ?? "";
    final storedName = prefs.getString("restaurant_name")?.trim() ?? "";
    final storedHash = prefs.getString("restaurant_hash")?.trim() ?? "";

    if (storedId.isNotEmpty && RegExp(r'^\d+$').hasMatch(storedId)) {
      return storedId;
    }

    final restaurants = await _fetchPublicRestaurants();
    if (restaurants.isEmpty) {
      return storedId.isNotEmpty ? storedId : null;
    }

    final selected = _selectRestaurant(
      restaurants: restaurants,
      storedId: storedId,
      storedHash: storedHash,
      storedName: storedName,
    );
    if (selected == null) {
      return storedId.isNotEmpty ? storedId : null;
    }

    final selectedId = selected["id"]?.toString().trim() ?? "";
    if (selectedId.isEmpty) {
      return storedId.isNotEmpty ? storedId : null;
    }

    await prefs.setString("restaurant_id", selectedId);
    final selectedName = selected["name"]?.toString().trim() ?? "";
    if (selectedName.isNotEmpty) {
      await prefs.setString("restaurant_name", selectedName);
    }
    final selectedHash = selected["hash"]?.toString().trim() ?? "";
    if (selectedHash.isNotEmpty) {
      await prefs.setString("restaurant_hash", selectedHash);
    }
    return selectedId;
  }

  static Map<String, dynamic>? _selectRestaurant({
    required List<Map<String, dynamic>> restaurants,
    required String storedId,
    required String storedHash,
    required String storedName,
  }) {
    final normalizedId = storedId.trim().toLowerCase();
    final normalizedHash = storedHash.trim().toLowerCase();
    final normalizedName = storedName.trim().toLowerCase();

    for (final restaurant in restaurants) {
      final id = restaurant["id"]?.toString().trim().toLowerCase() ?? "";
      final hash = restaurant["hash"]?.toString().trim().toLowerCase() ?? "";
      final name = restaurant["name"]?.toString().trim().toLowerCase() ?? "";
      if (normalizedId.isNotEmpty &&
          (normalizedId == id || normalizedId == hash)) {
        return restaurant;
      }
      if (normalizedHash.isNotEmpty && normalizedHash == hash) {
        return restaurant;
      }
      if (normalizedName.isNotEmpty && normalizedName == name) {
        return restaurant;
      }
    }

    if (restaurants.length == 1) {
      return restaurants.first;
    }

    return restaurants.first;
  }

  static Future<List<Map<String, dynamic>>> _fetchPublicRestaurants() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 14),
        headers: const {"Accept": "application/json"},
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final endpoints = <String>[
      WebApiConfig.allRestaurantsUrl,
      "http://127.0.0.1:8000/api/all-restaurants",
    ];

    for (final endpoint in endpoints) {
      final uri = Uri.tryParse(endpoint);
      final isDeprecatedRestaurantsEndpoint =
          uri?.host.toLowerCase() == "selfpos.sirixo.com" &&
              uri?.path.toLowerCase() == "/api/all-restaurants";
      if (isDeprecatedRestaurantsEndpoint) continue;
      try {
        final response = await dio.get(endpoint);
        if ((response.statusCode ?? 0) >= 400) continue;
        final list = _extractRestaurants(response.data);
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }

    return const [];
  }

  static List<Map<String, dynamic>> _extractRestaurants(dynamic raw) {
    final rawList = raw is List
        ? raw
        : (raw is Map
            ? (raw["data"] ?? raw["restaurants"] ?? raw["items"])
            : null);
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry("$key", value)))
        .toList();
  }
}
