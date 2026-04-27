import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/admin_api.dart';
import '../core/kiosk_log.dart';
import '../screens/admin_dashboard_screens/adim_homescreen.dart';

class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final TextEditingController _pinCtrl = TextEditingController();
  static const String _localAdminPin = "9999";

  bool loading = false;
  String error = "";

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  // =========================================================
  // VERIFY ADMIN PIN
  // =========================================================
  Future<void> _verifyPin() async {
    final pin = _pinCtrl.text.trim();

    if (pin.length != 4) {
      setState(() => error = "Enter 4-digit PIN");
      return;
    }

    setState(() {
      loading = true;
      error = "";
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      if (pin == _localAdminPin) {
        kioskLog('local admin pin accepted (offline bypass)', tag: 'PIN');
        await prefs.setBool("admin_local_bypass", true);
        await prefs.remove("admin_token");
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        Navigator.of(context, rootNavigator: true).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
        );
        return;
      }

      // 🔥 MUST BE BACKEND DEVICE ID
      final deviceId = prefs.getString("device_uuid");
      kioskLog('verify pin with device_id=$deviceId', tag: 'PIN');


      if (deviceId == null || deviceId.isEmpty) {
        kioskLog('device_id missing in prefs', tag: 'PIN');
        throw Exception("Kiosk not registered");
      }

      final res = await AdminApi().login(deviceId: deviceId, pin: pin);
      kioskLog(
        'login response status=${res.statusCode} body=${res.data}',
        tag: 'PIN',
      );

      // ✅ SAFE TOKEN EXTRACTION
      final token = res.data?["token"];
      if (token == null || token.toString().isEmpty) {
        kioskLog('admin token missing in login response', tag: 'PIN');
        throw Exception("Admin token missing");
      }

      // 🔐 SAVE ADMIN TOKEN
      await prefs.setString("admin_token", token.toString());
      await prefs.setBool("admin_local_bypass", false);

      if (!mounted) return;

      // ✅ CLOSE PIN DIALOG
      Navigator.of(context, rootNavigator: true).pop();

      // ✅ GO TO ADMIN HOME
      Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      kioskLogError(
        'PIN login failed: status=$status path=${e.requestOptions.path} body=$body message=${e.message}',
        tag: 'PIN',
        error: e,
        stackTrace: e.stackTrace,
      );
      final serverMsg = body is Map
          ? (body["message"]?.toString().trim() ?? "")
          : "";
      if (mounted) {
        setState(() => error = serverMsg.isNotEmpty ? serverMsg : "Invalid PIN");
      }
    } catch (e) {
      kioskLogError('PIN verify error: $e', tag: 'PIN', error: e);
      setState(() => error = "Invalid PIN");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // =========================================================
  // UI
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF9F342C).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: Color(0xFF9F342C),
                size: 36,
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              "Admin Access",
              style: TextStyle(
                color: Colors.black87,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Enter 4-digit PIN to continue",
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),

            const SizedBox(height: 20),

            // 🔢 PIN INPUT
            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                color: Colors.black87,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                counterText: "",
                filled: true,
                fillColor: const Color(0xFFF4F4F4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFF9F342C), width: 2),
                ),
              ),
              onSubmitted: (_) => _verifyPin(),
            ),

            if (error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(error, style: const TextStyle(color: Colors.redAccent)),
            ],

            const SizedBox(height: 20),

            // 🔓 UNLOCK BUTTON
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: loading ? null : _verifyPin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9F342C),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.2,
                        ),
                      )
                    : const Text(
                        "Unlock",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 8),

            // ❌ CANCEL
            TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black54,
              ),
              child: const Text("Cancel"),
            ),
          ],
        ),
      ),
    );
  }
}
