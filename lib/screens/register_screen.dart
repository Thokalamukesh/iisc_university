import 'dart:convert';

import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/printer/epson_usb_printer_service.dart'; // Ensure this matches your file name
import 'package:api_selfxo_project/background_image/background_image.dart';
import 'package:api_selfxo_project/printer/register_kiosk.dart';
import 'package:api_selfxo_project/core/connectivity_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';

class UserIdScreen extends StatefulWidget {
  const UserIdScreen({super.key});

  @override
  State<UserIdScreen> createState() => _UserIdScreenState();
}

class _UserIdScreenState extends State<UserIdScreen> {
  final TextEditingController controller = TextEditingController();
  final EpsonUSBPrinterService _usbPrinterService = EpsonUSBPrinterService();

  bool loading = false;
  bool hasError = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  // ================= MAIN SUBMIT FLOW =================
  Future<void> _submit() async {
    if (loading) return;
    final restaurantId = controller.text.trim().toLowerCase();
    if (restaurantId.isEmpty) {
      _showError("Please enter a Restaurant ID");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("restaurant_id", restaurantId);

    if (!ConnectivityService.instance.isOnline.value) {
      _showError("No internet connection");
      return;
    }

    setState(() {
      loading = true;
      hasError = false;
    });

    try {
      // 1. Initialize Auth / Kiosk Registration
      final ok = await AuthService().initializeKiosk(force: true);
      if (!ok) throw Exception("Registration failed");

      // 2. Validate with Backend
      final res = await KioskApi().getRestaurantData();
      final data = res.data?["restaurant"];
      final gst =
          data?["gst_number"] ??
          data?["gstin"] ??
          data?["tax_id"] ??
          data?["taxId"] ??
          data?["gst_no"] ??
          data?["gst"];
      if (gst != null && gst.toString().trim().isNotEmpty) {
        await prefs.setString("gst_number", gst.toString().trim());
      }

      if (!mounted) return;

      // 3. 🔥 PRINTER SELECTION (USB)
      // This happens BEFORE moving to Welcome Screen
      await _handleUSBPrinterSelection();

      // 4. Initial setup (only first install)
      final setupDone = prefs.getBool("kiosk_setup_done") ?? false;
      if (!mounted) return;
      if (!setupDone) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RegisterKioskScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        );
      }
    } catch (e) {
      setState(() => hasError = true);
      _showError("Registration failed. Check ID and Internet.");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ================= PRINTER SELECTION DIALOG =================
  Future<void> _handleUSBPrinterSelection() async {
    try {
      // Get the list of connected USB printers from our Native Service
      final List<Map<String, dynamic>> printers = await _usbPrinterService
          .getPrinterList();

      if (printers.isEmpty) {
        // No USB printer found? We can show a warning or skip
        await _showNoPrinterDialog();
        return;
      }

      Map<String, dynamic>? selectedPrinter;

      // Show selection dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text("USB Printer Detected"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select the Epson printer for this Kiosk:"),
              const SizedBox(height: 16),
              SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: printers.length,
                  itemBuilder: (context, index) {
                    final p = printers[index];
                    return Card(
                      color: Colors.grey.shade100,
                      child: ListTile(
                        leading: const Icon(Icons.usb, color: Colors.blue),
                        title: Text(
                          p["name"] ?? p["productName"] ?? "USB Printer",
                        ),
                        subtitle: Text(
                          "Device: ${p["deviceId"] ?? "-"} • VID: ${p["vendorId"] ?? "-"} • PID: ${p["productId"] ?? "-"}",
                        ),
                        onTap: () {
                          selectedPrinter = p;
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

      if (selectedPrinter != null) {
        final prefs = await SharedPreferences.getInstance();
        // Save the printer type as USB
        await prefs.setString("printer_type", "usb");
        // Save the full USB printer config for reconnect
        await prefs.setString(
          "selected_usb_printer",
          jsonEncode(selectedPrinter),
        );
        await _usbPrinterService.setSelectedPrinter(selectedPrinter!);
        await _usbPrinterService.scanAndConnect();

        _showSuccessSnackBar(
          "Printer Configured: ${selectedPrinter!["name"] ?? selectedPrinter!["productName"] ?? "USB Printer"}",
        );
      }
    } catch (e) {
    }
  }

  Future<void> _showNoPrinterDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("No Printer Found"),
        content: const Text(
          "Ensure your Epson USB printer is plugged in and turned on. You can configure this later in Settings.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // ================= UI HELPERS =================
  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green.shade800),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF9F342C),
        elevation: 0,
        leadingWidth: 120,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image.asset(
              "assets/self.png",
              height: isTablet ? 46 : 36,
              fit: BoxFit.contain,
            ),
          ),
        ),
        title: const Text(
          "Kiosk",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            color: Color.fromARGB(255, 255, 255, 255),
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Welcome to SELFX Kiosk",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isTablet ? 32 : 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Please Register kiosk with your Restaurant",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isTablet ? 18 : 14,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: controller,
                  textAlign: TextAlign.center,

                  // ✅ THIS controls the typed text size
                  style: const TextStyle(
                    fontSize: 24, // increase as needed
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),

                  decoration: InputDecoration(
                    hintText: "Enter Restaurant ID",
                    hintStyle: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                      fontSize: 20,
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF9F342C)),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(
                        color: Color(0xFF9F342C),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),
                SizedBox(
                  width: isTablet ? 260 : 220,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9F342C),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: loading ? null : _submit,
                    child: loading
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text(
                            "Register",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 24,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
