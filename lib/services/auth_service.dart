import 'package:api_selfxo_project/api/dio_client.dart';
import 'package:api_selfxo_project/core/device_info.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';

class AuthService {
  static const bool _enableAuthLogs = false;

  void _log(String message) {
    if (_enableAuthLogs) {
    }
  }

  Future<bool> initializeKiosk({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final restaurantId = prefs.getString("restaurant_id");
      if (restaurantId == null || restaurantId.isEmpty) {
        _log("❌ Restaurant ID missing");
        return false;
      }

      // 🔥 IMPORTANT CHANGE IS HERE
      final deviceId = await DeviceInfoUtil.getDeviceId(
        restaurantId: restaurantId,
      );

      if (force) {
        _log("🧹 Force mode → clearing old kiosk token");
        await prefs.remove("auth_token");
      }

      if (!force) {
        final token = prefs.getString("auth_token");
        if (token != null && token.isNotEmpty) {
          _log("✅ Using existing kiosk token");
          return true;
        }
      }

      final dio = DioClient.getDio();

      try {
        _log("🔄 Registering kiosk for restaurant: $restaurantId");

        final res = await dio.post(
          "kiosks/register",
          data: {
            "device_id": deviceId,
            "name": "Kiosk Device",
            "restaurant_id": restaurantId,
          },
        );

        final token = res.data?["token"];
        if (token == null || token.toString().isEmpty) {
          _log("❌ Token missing in register response");
          return false;
        }

        await prefs.setString("auth_token", token.toString());
        _log("✅ Kiosk registered & token saved");
        return true;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final msgRaw = e.response?.data?.toString() ?? e.message ?? "";
        final msg = msgRaw.toLowerCase();


        final bool looksDuplicate =
            msg.contains("duplicate") ||
            msg.contains("already exists") ||
            msg.contains("already taken") ||
            msg.contains("device id") ||
            msg.contains("device_id") ||
            msg.contains("kiosks_device_id_unique") ||
            status == 409 ||
            status == 422;

        if (looksDuplicate) {
          _log("⚠️ Device already exists → fetching token");
          return await _fetchExistingToken(deviceId);
        }

        _log("❌ Register failed: ${e.response?.data}");
        return false;
      }
    } catch (e) {
      _log("❌ INIT ERROR: $e");
      return false;
    }
  }

  Future<bool> _fetchExistingToken(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dio = DioClient.getDio();

      final res = await dio.get("kiosks/getToken/$deviceId");
      final token = res.data?["token"];

      if (token == null || token.toString().isEmpty) {
        _log("❌ Failed to fetch existing token");
        return false;
      }

      await prefs.setString("auth_token", token.toString());
      _log("✅ Existing kiosk token refreshed");
      return true;
    } catch (e) {
      _log("❌ TOKEN FETCH ERROR: $e");
      return false;
    }
  }
}
