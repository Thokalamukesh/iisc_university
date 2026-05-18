import 'package:api_selfxo_project/api/dio_client.dart';
import 'package:api_selfxo_project/api/web_api_config.dart';
import 'package:api_selfxo_project/core/device_info.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const bool _enableAuthLogs = true;
  static String? _lastFailureReason;
  static Future<bool>? _inFlightInitialize;

  static String? get lastFailureReason => _lastFailureReason;

  void _setFailure(String message) {
    _lastFailureReason = message;
    _log(message);
  }

  void _log(String message) {
    if (_enableAuthLogs) {
      kioskLog(message, tag: "AUTH");
    }
  }

  bool _looksDuplicateError(DioException e) {
    final status = e.response?.statusCode;
    final msgRaw = e.response?.data?.toString() ?? e.message ?? "";
    final msg = msgRaw.toLowerCase();
    return msg.contains("duplicate") ||
        msg.contains("already exists") ||
        msg.contains("already taken") ||
        msg.contains("device id") ||
        msg.contains("device_id") ||
        msg.contains("kiosks_device_id_unique") ||
        status == 409 ||
        status == 422;
  }

  bool _isInvalidDeviceCandidate(String value) {
    final id = value.trim().toLowerCase();
    if (id.isEmpty) return true;
    return id == "unknown_device" ||
        id == "unknown_ios" ||
        id.startsWith("unknown_device_") ||
        id.startsWith("unknown_ios_");
  }

  String _registeredDeviceKey(String deviceId) {
    return "kiosk_registered_device_$deviceId";
  }

  bool _isWebGeneratedDeviceId(String deviceId) {
    final id = deviceId.trim().toLowerCase();
    return id.startsWith("web_") || id.startsWith("web_base_");
  }

  bool _shouldProbeExistingToken(SharedPreferences prefs, String deviceId) {
    if (!_isWebGeneratedDeviceId(deviceId)) return true;
    return prefs.getBool(_registeredDeviceKey(deviceId)) ?? false;
  }

  Future<List<String>> _candidateDeviceIds({
    required SharedPreferences prefs,
    required String restaurantId,
  }) async {
    final scoped = await DeviceInfoUtil.getDeviceId(restaurantId: restaurantId);
    final base = await DeviceInfoUtil.getBaseDeviceId();
    final stored = prefs.getString("device_uuid")?.trim() ?? "";
    final candidates = <String>[
      scoped.trim(),
      if (base.trim().isNotEmpty) base.trim(),
      if (stored.isNotEmpty) stored,
    ];
    final deduped = <String>[];
    for (final id in candidates) {
      if (_isInvalidDeviceCandidate(id)) continue;
      if (!deduped.contains(id)) deduped.add(id);
    }
    return deduped;
  }

  Future<Map<String, String>?> _findRestaurantByAnyId(String value) async {
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
      "https://gitam.sirixo.com/api/all-restaurants",
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
          final name = (mapped["name"] ?? "").trim();
          if (needle == id || needle == hash) {
            return {
              "id": mapped["id"]?.trim() ?? "",
              "hash": mapped["hash"]?.trim() ?? "",
              "name": name,
            };
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<String>> _resolveRegistrationRestaurantKeys({
    required SharedPreferences prefs,
    required String restaurantId,
  }) async {
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
      // Try id first for current backend path, then hash fallback.
      addKey(id);
      addKey(hash);
      break;
    }

    // The kiosk register endpoint accepts restaurant slugs/hashes more reliably
    // than numeric ids on the web backend, so try hash-like keys first and keep
    // numeric ids as fallback.
    keys.sort((a, b) {
      final aIsNumeric = RegExp(r'^\d+$').hasMatch(a);
      final bIsNumeric = RegExp(r'^\d+$').hasMatch(b);
      if (aIsNumeric == bIsNumeric) return 0;
      return aIsNumeric ? 1 : -1;
    });
    return keys;
  }

  Future<bool> initializeKiosk({bool force = false}) {
    final running = _inFlightInitialize;
    if (running != null) {
      _log("initializeKiosk already running; waiting for existing attempt");
      return running;
    }

    final future = _initializeKiosk(force: force);
    _inFlightInitialize = future;
    future.whenComplete(() {
      if (identical(_inFlightInitialize, future)) {
        _inFlightInitialize = null;
      }
    });
    return future;
  }

  Future<bool> _initializeKiosk({required bool force}) async {
    try {
      _lastFailureReason = null;
      final prefs = await SharedPreferences.getInstance();

      final restaurantId = prefs.getString("restaurant_id");
      if (restaurantId == null || restaurantId.isEmpty) {
        _setFailure("Restaurant ID missing");
        return false;
      }
      final registrationRestaurantKeys =
          await _resolveRegistrationRestaurantKeys(
        prefs: prefs,
        restaurantId: restaurantId,
      );
      if (registrationRestaurantKeys.isEmpty) {
        _setFailure("Restaurant key resolution failed");
        return false;
      }
      final scopedTokenKey = _scopedAuthTokenKey(registrationRestaurantKeys);
      _log("initializeKiosk(force: $force) restaurant_id=$restaurantId");
      _log(
        "register payload restaurant_keys=$registrationRestaurantKeys "
        "(original=$restaurantId)",
      );
      final deviceIds = await _candidateDeviceIds(
        prefs: prefs,
        restaurantId: restaurantId,
      );
      if (deviceIds.isEmpty) {
        _setFailure("Device ID resolution failed");
        return false;
      }
      _log("resolved candidate device_ids=$deviceIds");
      await prefs.setString("device_uuid", deviceIds.first);
      await prefs.setString("device_id", deviceIds.first);

      if (force) {
        _log("🧹 Force mode → clearing old kiosk token");
        await prefs.remove("auth_token");
      }

      final scopedToken = prefs.getString(scopedTokenKey)?.trim() ?? "";
      if (scopedToken.isNotEmpty) {
        await prefs.setString("auth_token", scopedToken);
        _log("✅ Using scoped cached kiosk token");
        return true;
      }

      final token = prefs.getString("auth_token")?.trim() ?? "";
      if (!force && token.isNotEmpty) {
        await prefs.setString(scopedTokenKey, token);
        _log("✅ Using existing kiosk token");
        return true;
      }

      final dio = DioClient.getDio();

      for (final deviceId in deviceIds) {
        if (!_shouldProbeExistingToken(prefs, deviceId)) {
          _log("Skipping getToken probe for new web device_id=$deviceId");
          continue;
        }
        final tokenRecovered = await _fetchExistingToken(deviceId);
        if (tokenRecovered) {
          await prefs.setString("device_uuid", deviceId);
          await prefs.setString("device_id", deviceId);
          return true;
        }
      }

      String? lastError;
      for (final deviceId in deviceIds) {
        for (final registrationRestaurantId in registrationRestaurantKeys) {
          try {
            _log(
              "🔄 Registering kiosk for restaurant: $registrationRestaurantId "
              "with device_id=$deviceId",
            );

            final res = await dio.post(
              "kiosks/register",
              data: {
                "device_id": deviceId,
                "name": "Kiosk Device",
                "restaurant_id": registrationRestaurantId,
              },
            );
            _log(
              "register response status=${res.statusCode} body=${res.data}",
            );

            final token = res.data?["token"];
            if (token == null || token.toString().isEmpty) {
              lastError =
                  "Token missing in register response for device_id=$deviceId";
              continue;
            }

            await prefs.setString("auth_token", token.toString());
            await prefs.setString(scopedTokenKey, token.toString());
            await prefs.setString("device_uuid", deviceId);
            await prefs.setString("device_id", deviceId);
            await prefs.setBool(_registeredDeviceKey(deviceId), true);
            _lastFailureReason = null;
            _log("✅ Kiosk registered & token saved");
            return true;
          } on DioException catch (e) {
            final status = e.response?.statusCode;
            final msgRaw = e.response?.data?.toString() ?? e.message ?? "";
            _log(
              "register exception status=$status path=${e.requestOptions.path} "
              "device_id=$deviceId restaurant_key=$registrationRestaurantId "
              "message=${e.message} body=$msgRaw",
            );

            if (_looksDuplicateError(e)) {
              _log(
                "⚠️ Device already exists for device_id=$deviceId → fetching token",
              );
              final recovered = await _fetchExistingToken(deviceId);
              if (recovered) {
                await prefs.setString("device_uuid", deviceId);
                await prefs.setString("device_id", deviceId);
                return true;
              }
            }
            lastError =
                "Register failed for device_id=$deviceId restaurant_key="
                "$registrationRestaurantId: $msgRaw";
            // If backend says selected key is invalid, let next key try.
            final bodyText = msgRaw.toLowerCase();
            final keyLooksInvalid =
                bodyText.contains("branches") && bodyText.contains("on null");
            if (keyLooksInvalid) {
              continue;
            }
          } catch (e) {
            lastError =
                "Register failed for device_id=$deviceId restaurant_key="
                "$registrationRestaurantId: $e";
            continue;
          }
        }
      }
      _setFailure(lastError ?? "Register failed");
      return false;
    } catch (e) {
      _setFailure("INIT ERROR: $e");
      return false;
    }
  }

  Future<bool> _fetchExistingToken(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dio = DioClient.getDio();
      final timer = Stopwatch()..start();
      _log("fetch existing token for device_id=$deviceId");

      final res = await dio.get("kiosks/getToken/$deviceId");
      timer.stop();
      _log(
        "getToken response status=${res.statusCode} "
        "duration=${timer.elapsedMilliseconds}ms body=${res.data}",
      );
      if (res.statusCode == 404) {
        _log("No existing kiosk token for device_id=$deviceId");
        return false;
      }
      final token = res.data?["token"];

      if (token == null || token.toString().isEmpty) {
        _log("Existing token response did not include token");
        return false;
      }

      await prefs.setString("auth_token", token.toString());
      final scopedKey = _scopedAuthTokenKeyFromPrefs(prefs);
      if (scopedKey != null) {
        await prefs.setString(scopedKey, token.toString());
      }
      await prefs.setBool(_registeredDeviceKey(deviceId), true);
      _lastFailureReason = null;
      _log("✅ Existing kiosk token refreshed");
      return true;
    } catch (e) {
      _setFailure("TOKEN FETCH ERROR: $e");
      return false;
    }
  }

  String _scopedAuthTokenKey(List<String> restaurantKeys) {
    final key = restaurantKeys.first.trim().toLowerCase();
    final safeKey = key.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return "auth_token_restaurant_$safeKey";
  }

  String? _scopedAuthTokenKeyFromPrefs(SharedPreferences prefs) {
    final hash = prefs.getString("restaurant_hash")?.trim();
    final id = prefs.getString("restaurant_id")?.trim();
    final key = (hash != null && hash.isNotEmpty) ? hash : id;
    if (key == null || key.isEmpty) return null;
    return _scopedAuthTokenKey([key]);
  }
}
