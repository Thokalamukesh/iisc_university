import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceInfoUtil {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const Uuid _uuid = Uuid();
  static const String _fallbackBaseDeviceIdKey = "fallback_base_device_id";

  static String _normalizedRestaurantPart(String restaurantId) {
    final cleaned =
        restaurantId.trim().toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "_");
    return cleaned.isEmpty ? "default" : cleaned;
  }

  static Future<String> _readOrCreateFallbackBaseId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_fallbackBaseDeviceIdKey)?.trim() ?? "";
    if (existing.isNotEmpty) return existing;
    final generated = "local_${_uuid.v4()}";
    await prefs.setString(_fallbackBaseDeviceIdKey, generated);
    return generated;
  }

  static Future<String> _resolveBaseDeviceId() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      const key = "web_base_device_id";
      final existing = prefs.getString(key)?.trim() ?? "";
      if (existing.isNotEmpty) return existing;
      final generated = "web_base_${_uuid.v4()}";
      await prefs.setString(key, generated);
      return generated;
    }
    String baseId = "";
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = await _deviceInfo.androidInfo;
      baseId = android.id.trim();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = await _deviceInfo.iosInfo;
      baseId = (ios.identifierForVendor ?? "").trim();
    }
    if (baseId.isEmpty ||
        baseId.toLowerCase() == "unknown_device" ||
        baseId.toLowerCase() == "unknown_ios") {
      return _readOrCreateFallbackBaseId();
    }
    return baseId;
  }

  static Future<String> getBaseDeviceId() async {
    try {
      return await _resolveBaseDeviceId();
    } catch (_) {
      return _readOrCreateFallbackBaseId();
    }
  }

  static Future<String> getDeviceId({required String restaurantId}) async {
    try {
      final normalizedRestaurantId = _normalizedRestaurantPart(restaurantId);
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final key = "web_device_id_$normalizedRestaurantId";
        final saved = prefs.getString(key)?.trim() ?? "";
        if (saved.isNotEmpty) {
          await prefs.setString("device_uuid", saved);
          await prefs.setString("device_id", saved);
          return saved;
        }

        final generated = "web_${normalizedRestaurantId}_${_uuid.v4()}";
        await prefs.setString(key, generated);
        await prefs.setString("device_uuid", generated);
        await prefs.setString("device_id", generated);
        return generated;
      }

      final baseId = await _resolveBaseDeviceId();
      return "${baseId}_$normalizedRestaurantId";
    } catch (_) {
      final fallback = await _readOrCreateFallbackBaseId();
      final normalizedRestaurantId = _normalizedRestaurantPart(restaurantId);
      return "${fallback}_$normalizedRestaurantId";
    }
  }
}
