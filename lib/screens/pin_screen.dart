import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/admin_api.dart';
import '../screens/admin_dashboard_screens/adim_homescreen.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';

class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final TextEditingController _pinCtrl = TextEditingController();

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

      // 🔥 MUST BE BACKEND DEVICE ID
      final deviceId = prefs.getString("device_uuid");


      if (deviceId == null || deviceId.isEmpty) {
        throw Exception("Kiosk not registered");
      }

      final res = await AdminApi().login(deviceId: deviceId, pin: pin);

      // ✅ SAFE TOKEN EXTRACTION
      final token = res.data?["token"];
      if (token == null || token.toString().isEmpty) {
        throw Exception("Admin token missing");
      }

      // 🔐 SAVE ADMIN TOKEN
      await prefs.setString("admin_token", token.toString());

      if (!mounted) return;

      // ✅ CLOSE PIN DIALOG
      Navigator.of(context, rootNavigator: true).pop();

      // ✅ GO TO ADMIN HOME
      Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
      );
    } catch (e) {
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
