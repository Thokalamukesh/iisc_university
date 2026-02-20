import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';

Future<void> loadDeviceInfo() async {
  final deviceInfo = DeviceInfoPlugin();

  if (kIsWeb) {
    final webInfo = await deviceInfo.webBrowserInfo;
    return;
  }

  final androidInfo = await deviceInfo.androidInfo;
}
