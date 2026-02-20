import 'package:flutter/services.dart';

class KioskPower {
  static const MethodChannel _channel = MethodChannel('com.selfx/kiosk_power');

  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {
      // Ignore failures; some OEMs block this action.
    }
  }
}
