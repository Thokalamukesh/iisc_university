import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceInfoUtil {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const Uuid _uuid = Uuid();

  static Future<String> getDeviceId({required String restaurantId}) async {
    try {
      String baseId = "unknown_device";

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final key = "web_device_id_$restaurantId";
        final saved = prefs.getString(key)?.trim() ?? "";
        if (saved.isNotEmpty) {
          await prefs.setString("device_uuid", saved);
          await prefs.setString("device_id", saved);
          return saved;
        }

        final generated = "web_${restaurantId}_${_uuid.v4()}";
        await prefs.setString(key, generated);
        await prefs.setString("device_uuid", generated);
        await prefs.setString("device_id", generated);
        return generated;
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await _deviceInfo.androidInfo;
        baseId = android.id;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await _deviceInfo.iosInfo;
        baseId = ios.identifierForVendor ?? "unknown_ios";
      }

      // 🔥 PER-RESTAURANT DEVICE ID
      return "${baseId}_$restaurantId";
    } catch (_) {
      return "unknown_device_$restaurantId";
    }
  }
}
