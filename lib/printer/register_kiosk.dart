import 'dart:async';

import 'package:api_selfxo_project/api/admin_api.dart';
import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/background_image/background_image.dart';
import 'package:api_selfxo_project/core/kiosk_bootstrap.dart';
import 'package:api_selfxo_project/core/order_utils.dart';
import 'package:api_selfxo_project/core/receipt_print_mode.dart';
import 'package:api_selfxo_project/printer/epson_usb_printer_service.dart';
import 'package:api_selfxo_project/printer/printer_s.dart';
import 'package:api_selfxo_project/screens/payment_success.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RegisterKioskScreen extends StatefulWidget {
  const RegisterKioskScreen({super.key});

  @override
  State<RegisterKioskScreen> createState() => _RegisterKioskScreenState();
}

class _RegisterKioskScreenState extends State<RegisterKioskScreen> {
  final PrinterService _printerService = PrinterService();
  final EpsonUSBPrinterService _usbService = EpsonUSBPrinterService();
  final TextEditingController _kioskNameCtrl = TextEditingController();
  final TextEditingController _scannerCtrl = TextEditingController();
  final FocusNode _kioskNameFocusNode = FocusNode(
    debugLabel: "setup-kiosk-name",
  );
  final FocusNode _scannerFocusNode = FocusNode(
    debugLabel: "setup-scanner-test",
  );
  final StringBuffer _globalScanBuffer = StringBuffer();

  bool isLoading = true;
  bool _savingKioskName = false;
  bool _finishing = false;
  bool _active = true;
  bool _scannerWorking = false;
  bool _scannerPrintRunning = false;
  int _queuedScannerPrintJobs = 0;

  Timer? _scannerIdleTimer;
  Timer? _scannerRefocusTimer;
  Timer? _globalScanIdleTimer;
  String _scannerStatus = "Scan any barcode/QR to test scanner.";
  String? _lastScannerValue;
  late final KeyEventCallback _globalKeyHandler;

  static const Set<String> _dummyPrintScanTokens = {
    "DUMMYPRINT",
    "TESTPRINT",
    "PRINTTEST",
    "SELFXTESTPRINT",
    "SELFXDUMMYPRINT",
  };

  String restaurantName = "Restaurant";
  String? restaurantAddress;
  Map<String, dynamic>? _settingsData;

  @override
  void initState() {
    super.initState();
    _globalKeyHandler = (event) {
      if (!mounted || !_active || event is! KeyDownEvent) {
        return false;
      }
      if (_scannerPrintRunning) {
        return false;
      }
      if (_kioskNameFocusNode.hasFocus || _scannerFocusNode.hasFocus) {
        return false;
      }
      return _captureGlobalScanKey(event);
    };
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScannerField();
    });
    _scannerRefocusTimer = Timer.periodic(const Duration(milliseconds: 800), (
      _,
    ) {
      if (!_active || !mounted) return;
      _focusScannerField();
    });
  }

  @override
  void dispose() {
    _active = false;
    _scannerIdleTimer?.cancel();
    _scannerRefocusTimer?.cancel();
    _globalScanIdleTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _kioskNameCtrl.dispose();
    _kioskNameFocusNode.dispose();
    _scannerCtrl.dispose();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  /* ================= LOGIC (UNCHANGED) ================= */

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString("kiosk_name");
      final res = await AdminApi().getSettings();
      final data = res.data ?? {};
      final settings =
          (data["settings"] as Map?)?.cast<String, dynamic>() ?? {};
      final restaurant =
          (data["restaurant"] as Map?)?.cast<String, dynamic>() ?? {};

      await ReceiptPrintMode.storeFromMap(settings);
      await ReceiptPrintMode.storeFromMap(restaurant);

      if (!mounted) return;
      setState(() {
        _settingsData = settings;
        restaurantName = restaurant["name"] ?? "Restaurant";
        restaurantAddress = restaurant["address"]?.toString();
        _kioskNameCtrl.text = (savedName != null && savedName.trim().isNotEmpty)
            ? savedName.trim()
            : "";
        isLoading = false;
      });
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedName = prefs.getString("kiosk_name");
        final res = await KioskApi().getRestaurantData();
        final raw = res.data ?? {};
        final restaurant =
            (raw["restaurant"] as Map?)?.cast<String, dynamic>() ??
                (raw as Map?)?.cast<String, dynamic>() ??
                {};
        final kioskSettings =
            (raw["kiosk_settings"] as Map?)?.cast<String, dynamic>();
        final branch = (raw["branch"] as Map?)?.cast<String, dynamic>();

        await ReceiptPrintMode.storeFromMap(kioskSettings);
        await ReceiptPrintMode.storeFromMap(restaurant);

        final mergedSettings = <String, dynamic>{};
        if (kioskSettings != null) {
          mergedSettings.addAll(kioskSettings);
        }
        final branchId = mergedSettings["branch_id"] ?? branch?["id"];
        if (branchId != null) mergedSettings["branch_id"] = branchId;
        final restaurantId = mergedSettings["restaurant_id"] ??
            restaurant["restaurant_id"] ??
            restaurant["id"];
        if (restaurantId != null) {
          mergedSettings["restaurant_id"] = restaurantId;
        }

        if (!mounted) return;
        setState(() {
          _settingsData =
              mergedSettings.isNotEmpty ? mergedSettings : kioskSettings;
          restaurantName = restaurant["name"] ?? "Restaurant";
          restaurantAddress = restaurant["address"]?.toString();
          _kioskNameCtrl.text =
              (savedName != null && savedName.trim().isNotEmpty)
                  ? savedName.trim()
                  : "";
          isLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          restaurantName = "Restaurant";
          restaurantAddress = null;
          _kioskNameCtrl.text = "";
          isLoading = false;
        });
      }
    }
  }

  Future<void> _saveKioskName() async {
    final name = _kioskNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnackBar("Enter device name", Colors.red);
      return;
    }
    if (_savingKioskName) return;

    setState(() => _savingKioskName = true);
    try {
      final body = <String, dynamic>{
        "name": name,
        "kiosk_name": name,
        "device_name": name,
      };
      if (_settingsData != null) {
        final branchId = _settingsData?["branch_id"];
        final printerId = _settingsData?["printer_id"];
        final deviceId = _settingsData?["device_id"];
        final restaurantId = _settingsData?["restaurant_id"];
        if (branchId != null) body["branch_id"] = branchId;
        if (printerId != null) body["printer_id"] = printerId;
        if (deviceId != null) body["device_id"] = deviceId;
        if (restaurantId != null) body["restaurant_id"] = restaurantId;
      }
      await AdminApi().updateSettings(body);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("kiosk_name", name);
      _showSnackBar("Device name updated", Colors.green);
      if (mounted) {
        setState(() {
          _settingsData ??= {};
          _settingsData?["name"] = name;
          _settingsData?["kiosk_name"] = name;
          _settingsData?["device_name"] = name;
        });
      }
      OrderUtils.notifyInfoUpdated();
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("kiosk_name", name);
      _showSnackBar("Saved locally.", const Color(0xFF1B8E3E));
      OrderUtils.notifyInfoUpdated();
    } finally {
      if (mounted) setState(() => _savingKioskName = false);
    }
  }

  Future<void> _runTestPrint() async {
    try {
      await _printerService.testPrint(
        restaurantName: restaurantName,
        address: restaurantAddress,
      );
      _showSnackBar("Test print started", Colors.blue);
    } on PlatformException catch (e) {
      if (e.code == "USB_PERMISSION_REQUIRED") {
        final printer = await _printerService.getSelectedUsbPrinter();
        if (printer == null) {
          _showSnackBar("No USB printer selected", Colors.red);
          return;
        }
        final requested = await _usbService.requestUsbPermission(printer);
        if (requested) {
          await Future.delayed(const Duration(milliseconds: 600));
          if (!_active || !mounted) return;
          await _printerService.testPrint(
            restaurantName: restaurantName,
            address: restaurantAddress,
          );
        } else {
          _showSnackBar("USB permission denied", Colors.red);
        }
      } else {
        _showSnackBar(e.message ?? e.toString(), Colors.red);
      }
    } catch (e) {
      _showSnackBar(e.toString(), Colors.red);
    }
  }

  Future<void> _setupUsbPrinter() async {
    try {
      final printers = await _printerService.getUsbPrinters();
      if (printers.isEmpty) {
        _showSnackBar("No USB printer found", Colors.red);
        return;
      }

      Map<String, dynamic>? selectedPrinter;
      if (printers.length == 1) {
        selectedPrinter = printers.first;
      } else {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text("Select USB Printer"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: printers.length,
                  itemBuilder: (_, index) {
                    final printer = printers[index];
                    final printerName =
                        printer["name"]?.toString().trim().isNotEmpty == true
                            ? printer["name"].toString().trim()
                            : (printer["productName"]
                                        ?.toString()
                                        .trim()
                                        .isNotEmpty ==
                                    true
                                ? printer["productName"].toString().trim()
                                : "USB Printer");
                    return ListTile(
                      leading: const Icon(Icons.print_rounded),
                      title: Text(printerName),
                      subtitle: Text(
                        "VID ${printer["vendorId"] ?? "-"}  PID ${printer["productId"] ?? "-"}",
                      ),
                      onTap: () {
                        selectedPrinter = printer;
                        Navigator.of(dialogContext).pop();
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text("Cancel"),
                ),
              ],
            );
          },
        );
      }

      if (selectedPrinter == null) return;

      try {
        await _printerService.saveSelectedUsbPrinter(selectedPrinter!);
      } on PlatformException catch (e) {
        if (e.code != "USB_PERMISSION_REQUIRED") rethrow;
        final requested =
            await _usbService.requestUsbPermissionWithUi(selectedPrinter!);
        if (!requested) {
          _showSnackBar("USB permission denied", Colors.red);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 600));
        await _printerService.saveSelectedUsbPrinter(selectedPrinter!);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("printer_type", "usb");

      final printerName =
          selectedPrinter!["name"]?.toString().trim().isNotEmpty == true
              ? selectedPrinter!["name"].toString().trim()
              : (selectedPrinter!["productName"]
                          ?.toString()
                          .trim()
                          .isNotEmpty ==
                      true
                  ? selectedPrinter!["productName"].toString().trim()
                  : "USB Printer");
      _showSnackBar("Printer configured: $printerName", Colors.green);
    } catch (e) {
      _showSnackBar(e.toString(), Colors.red);
    }
  }

  Future<void> _finishSetup() async {
    if (_finishing) return;
    final name = _kioskNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnackBar("Enter device name", Colors.red);
      return;
    }

    _finishing = true;
    try {
      if (_savingKioskName) {
        final end = DateTime.now().add(const Duration(seconds: 6));
        while (_savingKioskName && DateTime.now().isBefore(end)) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!_active || !mounted) return;
        }
      }
      if (!_savingKioskName) {
        await _saveKioskName();
      }
      if (_savingKioskName) {
        _showSnackBar("Please wait, saving...", Colors.orange);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool("kiosk_setup_done", true);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    } finally {
      _finishing = false;
    }
  }

  String _normalizeScannerInput(String raw) {
    return raw
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  String _normalizeDummyPrintToken(String raw) {
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  bool _isDummyPrintScan(String value) {
    final token = _normalizeDummyPrintToken(value);
    if (_dummyPrintScanTokens.contains(token)) return true;
    for (final expected in _dummyPrintScanTokens) {
      if (token.startsWith(expected) || token.endsWith(expected)) {
        return true;
      }
    }
    return false;
  }

  int? _extractOrderIdFromPaymentQr(String value) {
    final normalized = _normalizeScannerInput(value).toUpperCase();
    final match = RegExp(r'PRINT[_\-:]?ORDER[_\-:]?(\d{1,12})').firstMatch(
      normalized,
    );
    final parsed = int.tryParse(match?.group(1) ?? "");
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  bool _isPaidStatus(dynamic status) {
    if (status == true) return true;
    if (status is num) return status == 1;
    final s = status?.toString().trim().toLowerCase() ?? "";
    if (s.isEmpty) return false;
    if (s.contains("cancel") ||
        s.contains("refund") ||
        s.contains("failed") ||
        s.contains("void") ||
        s.contains("unpaid") ||
        s.contains("pending")) {
      return false;
    }
    return s.contains("paid") ||
        s.contains("completed") ||
        s.contains("success") ||
        s.contains("successful") ||
        s.contains("captured") ||
        s.contains("authorized");
  }

  bool _containsPaidState(dynamic value, int depth) {
    if (value == null || depth <= 0) return false;
    if (value is Map) {
      for (final key in const [
        "status",
        "payment_status",
        "paymentStatus",
        "order_status",
        "orderStatus",
        "state",
        "payment_state",
        "paymentState",
        "paid",
        "is_paid",
        "isPaid",
        "success",
        "is_success",
        "isSuccess",
        "result",
        "message",
      ]) {
        if (value.containsKey(key) && _isPaidStatus(value[key])) {
          return true;
        }
      }
      for (final nestedKey in const [
        "data",
        "order",
        "payment",
        "response",
        "result",
        "payload",
      ]) {
        if (value.containsKey(nestedKey) &&
            _containsPaidState(value[nestedKey], depth - 1)) {
          return true;
        }
      }
      for (final entry in value.entries) {
        if (_containsPaidState(entry.value, depth - 1)) {
          return true;
        }
      }
    } else if (value is List) {
      for (final item in value) {
        if (_containsPaidState(item, depth - 1)) return true;
      }
    } else if (_isPaidStatus(value)) {
      return true;
    }
    return false;
  }

  Future<T> _withKioskTokenRecovery<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      final message = e.toString().toLowerCase();
      final tokenMissing = message.contains("kiosk token missing") ||
          message.contains("auth_token") ||
          message.contains("unauthorized");
      if (!tokenMissing) rethrow;
      await DeviceBootstrap.ensureDeviceReady();
      return action();
    }
  }

  Future<void> _runScannerTriggeredOrderPrint({
    required int orderId,
    required String scannedValue,
  }) async {
    if (!mounted || _scannerPrintRunning) return;
    setState(() {
      _scannerPrintRunning = true;
      _scannerStatus = 'Payment QR "$scannedValue" detected. Checking payment...';
    });
    try {
      final paymentRes = await _withKioskTokenRecovery(
        () => KioskApi().checkPayment(orderId),
      );
      final isPaid = _containsPaidState(paymentRes.data, 5);
      if (!isPaid) {
        if (!mounted) return;
        setState(() {
          _scannerStatus = "Order #$orderId is not paid yet.";
        });
        _showSnackBar("Order #$orderId is not paid yet.", Colors.orange.shade800);
        return;
      }

      if (!mounted) return;
      setState(() {
        _scannerStatus = "Payment verified for order #$orderId. Printing...";
      });

      await _withKioskTokenRecovery(
        () => PaymentSuccessDialog.printReceiptUsingTabletFlow(
          cart: const [],
          orderNumber: orderId,
          restaurantName: restaurantName,
        ),
      );

      if (!mounted) return;
      setState(() {
        _scannerStatus = "Order #$orderId printed successfully.";
      });
      _showSnackBar("Order #$orderId printed successfully.", Colors.green.shade700);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scannerStatus = "Print failed for order #$orderId.";
      });
      _showSnackBar("Print failed for order #$orderId: $e", Colors.red.shade700);
    } finally {
      if (mounted) {
        setState(() {
          _scannerPrintRunning = false;
        });
      }
    }
  }

  Future<void> _runScannerTriggeredTestPrint(String scannedValue) async {
    if (!mounted) return;
    setState(() {
      _queuedScannerPrintJobs++;
      _scannerStatus =
          'Dummy scan "$scannedValue" matched. Queued prints: $_queuedScannerPrintJobs';
    });
    if (_scannerPrintRunning) return;
    setState(() {
      _scannerPrintRunning = true;
    });
    try {
      while (mounted && _queuedScannerPrintJobs > 0) {
        setState(() {
          _queuedScannerPrintJobs--;
          _scannerStatus =
              'Printing test receipt... Remaining queue: $_queuedScannerPrintJobs';
        });
        await _runTestPrint();
        if (!mounted) return;
        setState(() {
          _scannerStatus = _queuedScannerPrintJobs > 0
              ? 'Print sent. Next queued print starting... ($_queuedScannerPrintJobs left)'
              : 'All queued scan prints sent successfully.';
        });
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    } finally {
      if (mounted) {
        setState(() {
          _scannerPrintRunning = false;
        });
      }
    }
  }

  void _consumeScannerInput(String raw) {
    final value = _normalizeScannerInput(raw);
    if (value.isEmpty) {
      if (!mounted) return;
      setState(() {
        _scannerWorking = false;
        _scannerStatus = "No scanner data captured. Try scanning again.";
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _scannerWorking = true;
      _lastScannerValue = value;
      _scannerStatus = 'Scanner working. Last read: "$value"';
    });

    if (_isDummyPrintScan(value)) {
      unawaited(_runScannerTriggeredTestPrint(value));
      return;
    }
    final orderId = _extractOrderIdFromPaymentQr(value);
    if (orderId != null) {
      unawaited(
        _runScannerTriggeredOrderPrint(orderId: orderId, scannedValue: value),
      );
      return;
    }
    setState(() {
      _scannerStatus =
          'Unsupported scan "$value". Use SELFX_TEST_PRINT or payment QR PRINT_ORDER_<id>.';
    });
  }

  void _handleScannerChanged(String value) {
    _scannerIdleTimer?.cancel();
    _scannerIdleTimer = Timer(const Duration(milliseconds: 450), () {
      final captured = _scannerCtrl.text;
      _scannerCtrl.clear();
      _consumeScannerInput(captured);
    });
  }

  void _handleScannerSubmitted(String value) {
    _scannerIdleTimer?.cancel();
    _scannerCtrl.clear();
    _consumeScannerInput(value);
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  bool _isControlCharacter(String value) {
    final code = value.codeUnitAt(0);
    return code < 32 || code == 127;
  }

  bool _captureGlobalScanKey(KeyDownEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      final captured = _globalScanBuffer.toString();
      _globalScanBuffer.clear();
      if (captured.trim().isEmpty) return false;
      _consumeScannerInput(captured);
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_globalScanBuffer.isNotEmpty) {
        final current = _globalScanBuffer.toString();
        _globalScanBuffer
          ..clear()
          ..write(current.substring(0, current.length - 1));
      }
      _scheduleGlobalScanIdleFlush();
      return _globalScanBuffer.isNotEmpty;
    }

    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        !_isControlCharacter(character)) {
      _globalScanBuffer.write(character);
      _scheduleGlobalScanIdleFlush();
      return true;
    }

    return false;
  }

  void _scheduleGlobalScanIdleFlush() {
    _globalScanIdleTimer?.cancel();
    _globalScanIdleTimer = Timer(const Duration(milliseconds: 450), () {
      final captured = _globalScanBuffer.toString();
      _globalScanBuffer.clear();
      if (captured.trim().isEmpty) return;
      _consumeScannerInput(captured);
    });
  }

  void _focusScannerField() {
    if (_kioskNameFocusNode.hasFocus) return;
    if (!_scannerFocusNode.canRequestFocus) return;
    if (_scannerFocusNode.hasFocus) return;
    _scannerFocusNode.requestFocus();
  }

  /* ================= UI ================= */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF9F342C),
        elevation: 0,

        // 👈 Increase leading width so logo can grow
        leadingWidth: 90,

        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: Image.asset(
              "assets/self.png",
              height: 44, // 👈 visible, not cramped
              fit: BoxFit.contain,
            ),
          ),
        ),

        title: const Text(
          "Initial Setup",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                _sectionTitle("Restaurant Info"),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurantName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (restaurantAddress != null &&
                          restaurantAddress!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          restaurantAddress!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle("Device Setup"),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Device Name",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _kioskNameCtrl,
                        focusNode: _kioskNameFocusNode,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: "Enter device name",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _savingKioskName ? null : _saveKioskName,
                          icon: _savingKioskName
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.save_rounded,
                                  color: Colors.white,
                                ),
                          label: const Text(
                            "Save Device Name",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF9F342C),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle("Scanner Setup"),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Test Scanner",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Tap the field below and scan a barcode/QR. If value appears, scanner is connected.\n"
                        "For direct auto-print queue, scan dummy code: SELFX_TEST_PRINT\n"
                        "Each dummy scan = one print.",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _scannerCtrl,
                        focusNode: _scannerFocusNode,
                        onChanged: _handleScannerChanged,
                        onSubmitted: _handleScannerSubmitted,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          hintText: "Scan here",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _scannerWorking
                              ? const Color(0xFFE7F6EB)
                              : const Color(0xFFFFF5E7),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _scannerWorking
                                ? const Color(0xFF1B8E3E)
                                : const Color(0xFFB8832E),
                          ),
                        ),
                        child: Text(
                          _scannerStatus,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _scannerWorking
                                ? const Color(0xFF1B8E3E)
                                : const Color(0xFF9A6A1D),
                          ),
                        ),
                      ),
                      if (_lastScannerValue != null &&
                          _lastScannerValue!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          "Last scanner value: $_lastScannerValue",
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle("Printer Setup"),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Configure + Test Printer",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "First select/connect USB printer, then run test print.",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _setupUsbPrinter,
                          icon: const Icon(Icons.usb_rounded),
                          label: const Text(
                            "Setup USB Printer",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _runTestPrint,
                          icon: const Icon(
                            Icons.print_rounded,
                            color: Colors.white,
                          ),
                          label: const Text(
                            "Run Test Print",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF9F342C),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _finishing ? null : _finishSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B8E3E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _finishing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "Continue",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
