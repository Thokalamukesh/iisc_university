import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceInfoUtil {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<String> getDeviceId({required String restaurantId}) async {
    try {
      String baseId = "unknown_device";

      if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;
        baseId = android.id ?? "unknown_android";
      } else if (Platform.isIOS) {
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
