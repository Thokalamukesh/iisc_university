import 'package:shared_preferences/shared_preferences.dart';
import '../api/dio_client.dart';
import 'device_info.dart';

class DeviceUtils {
  static Future<void> ensureDeviceReady() async {
    final prefs = await SharedPreferences.getInstance();
    final dio = DioClient.getDio();

    // 🔥 FIRST: get restaurantId
    final restaurantId = prefs.getString("restaurant_id");
    if (restaurantId == null || restaurantId.isEmpty) {
      throw Exception("RESTAURANT_NOT_CONFIGURED");
    }
    final registrationRestaurantId =
        (prefs.getString("restaurant_hash")?.trim().isNotEmpty ?? false)
            ? prefs.getString("restaurant_hash")!.trim()
            : restaurantId;

    // 🔥 SECOND: generate restaurant-specific deviceId
    final deviceId =
        await DeviceInfoUtil.getDeviceId(restaurantId: restaurantId);

    // ===============================
    // 1️⃣ TRY EXISTING TOKEN FOR THIS DEVICE
    // ===============================
    try {
      final res = await dio.get("kiosks/getToken/$deviceId");
      final token = res.data?["token"];

      if (token != null && token.toString().isNotEmpty) {
        await prefs.setString("auth_token", token.toString());
        return;
      }
    } catch (_) {
      // ignore and register below
    }

    // ===============================
    // 2️⃣ REGISTER DEVICE (BINDS RESTAURANT)
    // ===============================
    final registerRes = await dio.post(
      "kiosks/register",
      data: {
        "device_id": deviceId,
        "name": "Flutter Kiosk",
        "restaurant_id": registrationRestaurantId,
      },
    );

    final token = registerRes.data?["token"];
    if (token == null || token.toString().isEmpty) {
      throw Exception("DEVICE_REGISTRATION_FAILED");
    }

    await prefs.setString("auth_token", token.toString());
  }
}
