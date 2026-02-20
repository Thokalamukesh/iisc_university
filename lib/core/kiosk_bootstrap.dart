import 'package:shared_preferences/shared_preferences.dart';
import '../api/dio_client.dart';
import 'device_info.dart';

class DeviceBootstrap {
  static Future<void> ensureDeviceReady() async {
    final prefs = await SharedPreferences.getInstance();

    // =========================================================
    // 1️⃣ DEVICE ID
    // =========================================================
    String? deviceId = prefs.getString("device_uuid");
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = await DeviceInfoUtil.getDeviceId(restaurantId: '');
      await prefs.setString("device_uuid", deviceId);
    }

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
    try {
      final res = await dio.get("kiosks/getToken/$deviceId");
      final token = res.data?["token"];

      if (token != null && token.toString().isNotEmpty) {
        await prefs.setString("auth_token", token.toString());
        return;
      }
    } catch (_) {
      // ignore → register
    }

    // =========================================================
    // 4️⃣ REGISTER DEVICE
    // =========================================================
    final restaurantId = prefs.getString("restaurant_id");
    if (restaurantId == null || restaurantId.isEmpty) {
      throw Exception("RESTAURANT_NOT_CONFIGURED");
    }

    final registerRes = await dio.post(
      "kiosks/register", // ✅ FIXED
      data: {
        "device_id": deviceId,
        "name": "Kiosk Device",
        "restaurant_id": restaurantId,
      },
    );

    final token = registerRes.data?["token"];
    if (token == null || token.toString().isEmpty) {
      throw Exception("DEVICE_REGISTRATION_FAILED");
    }

    await prefs.setString("auth_token", token.toString());
  }
}
