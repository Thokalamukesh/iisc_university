import 'dart:async';

import 'package:api_selfxo_project/api/admin_api.dart';
import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/api/web_api_config.dart';
import 'package:api_selfxo_project/core/kiosk_bootstrap.dart';
import 'package:api_selfxo_project/core/device_info.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:api_selfxo_project/core/order_utils.dart';
import 'package:api_selfxo_project/core/receipt_print_mode.dart';
import 'package:api_selfxo_project/printer/epson_usb_printer_service.dart';
import 'package:api_selfxo_project/printer/printer_s.dart';
import 'package:api_selfxo_project/screens/admin_dashboard_screens/adim_homescreen.dart';
import 'package:api_selfxo_project/screens/payment_success.dart';
import 'package:api_selfxo_project/screens/pin_screen.dart';
import 'package:api_selfxo_project/services/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RegisterKioskScreen extends StatefulWidget {
  const RegisterKioskScreen({super.key});

  @override
  State<RegisterKioskScreen> createState() => _RegisterKioskScreenState();
}

enum _ScanPaymentState {
  paid,
  unpaid,
  unverifiedServerError,
}

class _RegisterKioskScreenState extends State<RegisterKioskScreen> {
  final PrinterService _printerService = PrinterService();
  final EpsonUSBPrinterService _usbService = EpsonUSBPrinterService();
  final TextEditingController _restaurantIdCtrl = TextEditingController();
  final TextEditingController _kioskNameCtrl = TextEditingController();
  final TextEditingController _scannerCtrl = TextEditingController();
  final FocusNode _restaurantIdFocusNode = FocusNode(
    debugLabel: "setup-restaurant-id",
  );
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
  bool _showAdvancedScanner = false;
  bool _scannerPrintRunning = false;
  int _queuedScannerPrintJobs = 0;

  Timer? _scannerIdleTimer;
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

  Future<void> _persistRestaurantContext({
    required SharedPreferences prefs,
    Map<String, dynamic>? settings,
    Map<String, dynamic>? restaurant,
  }) async {
    final restaurantId = settings?["restaurant_id"] ??
        settings?["restaurantId"] ??
        restaurant?["restaurant_id"] ??
        restaurant?["restaurantId"] ??
        restaurant?["id"];
    if (restaurantId != null && restaurantId.toString().trim().isNotEmpty) {
      await prefs.setString("restaurant_id", restaurantId.toString().trim());
    }
    final name = restaurant?["name"]?.toString().trim();
    if (name != null && name.isNotEmpty) {
      await prefs.setString("restaurant_name", name);
    }
  }

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
      if (_isAnyTextInputFocused()) {
        return false;
      }
      return _captureGlobalScanKey(event);
    };
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
    _loadSettings();
  }

  @override
  void dispose() {
    _active = false;
    _scannerIdleTimer?.cancel();
    _globalScanIdleTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _restaurantIdCtrl.dispose();
    _restaurantIdFocusNode.dispose();
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
      final authToken = prefs.getString("auth_token")?.trim() ?? "";
      final adminToken = prefs.getString("admin_token")?.trim() ?? "";
      if (authToken.isEmpty && adminToken.isEmpty) {
        if (!mounted) return;
        setState(() {
          _settingsData = null;
          restaurantName =
              prefs.getString("restaurant_name")?.trim().isNotEmpty == true
                  ? prefs.getString("restaurant_name")!.trim()
                  : "Restaurant";
          restaurantAddress = null;
          _restaurantIdCtrl.text =
              prefs.getString("restaurant_id")?.trim() ?? "";
          _kioskNameCtrl.text =
              (savedName != null && savedName.trim().isNotEmpty)
                  ? savedName.trim()
                  : "";
          isLoading = false;
        });
        return;
      }
      final res = await AdminApi().getSettings();
      final data = res.data ?? {};
      final settings =
          (data["settings"] as Map?)?.cast<String, dynamic>() ?? {};
      final restaurant =
          (data["restaurant"] as Map?)?.cast<String, dynamic>() ?? {};
      await _persistRestaurantContext(
        prefs: prefs,
        settings: settings,
        restaurant: restaurant,
      );

      await ReceiptPrintMode.storeFromMap(settings);
      await ReceiptPrintMode.storeFromMap(restaurant);

      if (!mounted) return;
      setState(() {
        _settingsData = settings;
        restaurantName = restaurant["name"] ?? "Restaurant";
        restaurantAddress = restaurant["address"]?.toString();
        final initialRestaurantId = (settings["restaurant_id"] ??
                settings["restaurantId"] ??
                restaurant["restaurant_id"] ??
                restaurant["restaurantId"] ??
                restaurant["id"] ??
                prefs.getString("restaurant_id") ??
                "")
            .toString()
            .trim();
        _restaurantIdCtrl.text = initialRestaurantId;
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
        await _persistRestaurantContext(
          prefs: prefs,
          settings: kioskSettings,
          restaurant: restaurant,
        );

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
          final initialRestaurantId = (mergedSettings["restaurant_id"] ??
                  mergedSettings["restaurantId"] ??
                  restaurant["restaurant_id"] ??
                  restaurant["restaurantId"] ??
                  restaurant["id"] ??
                  prefs.getString("restaurant_id") ??
                  "")
              .toString()
              .trim();
          _restaurantIdCtrl.text = initialRestaurantId;
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
          _restaurantIdCtrl.text = "";
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
      final prefs = await SharedPreferences.getInstance();
      final hasAuthToken =
          (prefs.getString("auth_token")?.trim() ?? "").isNotEmpty;
      final hasAdminToken =
          (prefs.getString("admin_token")?.trim() ?? "").isNotEmpty;
      if (!hasAuthToken && !hasAdminToken) {
        await prefs.setString("kiosk_name", name);
        if (mounted) {
          setState(() {
            _settingsData ??= {};
            _settingsData?["name"] = name;
            _settingsData?["kiosk_name"] = name;
            _settingsData?["device_name"] = name;
          });
        }
        _showSnackBar("Saved locally.", const Color(0xFF1B8E3E));
        OrderUtils.notifyInfoUpdated();
        return;
      }

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
    final enteredRestaurantId = _restaurantIdCtrl.text.trim();
    kioskLog(
      '_finishSetup start name="$name" restaurant_id="$enteredRestaurantId"',
      tag: 'SETUP',
    );
    if (name.isEmpty) {
      _showSnackBar("Enter device name", Colors.red);
      return;
    }
    if (enteredRestaurantId.isEmpty) {
      _showSnackBar("Enter restaurant ID", Colors.red);
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(enteredRestaurantId)) {
      _showSnackBar("Restaurant ID must be numeric", Colors.red);
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
      final previousRestaurantId =
          prefs.getString("restaurant_id")?.trim() ?? "";
      final normalizedRestaurantId = enteredRestaurantId;
      final restaurantChanged = previousRestaurantId.isNotEmpty &&
          previousRestaurantId != normalizedRestaurantId;
      kioskLog(
        'previous_restaurant_id="$previousRestaurantId" changed=$restaurantChanged',
        tag: 'SETUP',
      );

      if (restaurantChanged) {
        await prefs.remove("auth_token");
        await prefs.remove("admin_token");
        await prefs.remove("device_uuid");
        await prefs.remove("branch_id");
      }

      await prefs.setString("restaurant_id", normalizedRestaurantId);
      _settingsData ??= {};
      _settingsData?["restaurant_id"] = normalizedRestaurantId;

      final restaurantExists =
          await _validateRestaurantIdExists(normalizedRestaurantId, true);
      kioskLog(
        'restaurant validation for $normalizedRestaurantId => $restaurantExists',
        tag: 'SETUP',
      );
      if (!restaurantExists) {
        _showSnackBar("Invalid restaurant ID. Please check and try again.",
            Colors.red.shade700);
        return;
      }

      final resolvedDeviceId = await DeviceInfoUtil.getDeviceId(
        restaurantId: normalizedRestaurantId,
      );
      await prefs.setString("device_uuid", resolvedDeviceId);
      await prefs.setString("device_id", resolvedDeviceId);
      kioskLog('resolved device_id=$resolvedDeviceId', tag: 'SETUP');

      final existingKioskToken = prefs.getString("auth_token")?.trim() ?? "";
      var initialized = false;
      try {
        initialized = await AuthService().initializeKiosk(
          force: restaurantChanged || existingKioskToken.isEmpty,
        );
        kioskLog(
          'initializeKiosk result=$initialized force=${restaurantChanged || existingKioskToken.isEmpty}',
          tag: 'SETUP',
        );
      } catch (_) {
        initialized = false;
        kioskLog('initializeKiosk threw exception', tag: 'SETUP');
      }
      Object? bootstrapError;
      if (!initialized) {
        try {
          await DeviceBootstrap.ensureDeviceReady();
          kioskLog('DeviceBootstrap.ensureDeviceReady success', tag: 'SETUP');
        } catch (e) {
          bootstrapError = e;
          kioskLogError(
            'DeviceBootstrap.ensureDeviceReady failed: $e',
            tag: 'SETUP',
            error: e,
          );
        }
      }

      final refreshedKioskToken = prefs.getString("auth_token")?.trim() ?? "";
      if (refreshedKioskToken.isEmpty) {
        final authReason = AuthService.lastFailureReason ?? "";
        final bootstrapReason = bootstrapError?.toString() ?? "";
        final details = [
          if (authReason.isNotEmpty) authReason,
          if (bootstrapReason.isNotEmpty &&
              !bootstrapReason.toLowerCase().contains(authReason.toLowerCase()))
            bootstrapReason,
        ].join(" | ");
        kioskLog(
          'kiosk token setup failed. authReason="$authReason" bootstrapReason="$bootstrapReason"',
          tag: 'SETUP',
        );

        _showSnackBar(
          details.isNotEmpty
              ? "Kiosk token setup failed (server issue). Continue with PIN 9999 for admin mode. Details: $details"
              : "Kiosk token setup failed (server issue). Continue with PIN 9999 for admin mode.",
          Colors.orange.shade700,
        );
        kioskLog(
          'continuing setup without kiosk token (temporary fallback mode)',
          tag: 'SETUP',
        );
      }

      await prefs.setBool("kiosk_setup_done", true);
      await prefs.setBool("admin_local_bypass", false);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PinScreen(),
      );
      if (!mounted) return;
      final refreshedToken = prefs.getString("admin_token")?.trim() ?? "";
      final localBypass = prefs.getBool("admin_local_bypass") ?? false;
      if (refreshedToken.isNotEmpty || localBypass) {
        kioskLog(
          refreshedToken.isNotEmpty
              ? 'admin token present -> opening admin home'
              : 'local admin bypass active -> opening admin home',
          tag: 'SETUP',
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
        );
      } else {
        kioskLog('admin token missing after pin dialog', tag: 'SETUP');
        _showSnackBar("PIN cancelled or invalid.", Colors.orange.shade700);
      }
    } finally {
      kioskLog('_finishSetup end', tag: 'SETUP');
      _finishing = false;
    }
  }

  Future<bool> _validateRestaurantIdExists(
    String id,
    bool persistMatch,
  ) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 12),
        headers: const {"Accept": "application/json"},
      ),
    );
    final endpoints = <String>[
      WebApiConfig.allRestaurantsUrl,
      "http://127.0.0.1:8000/api/all-restaurants",
    ];
    for (final endpoint in endpoints) {
      final uri = Uri.tryParse(endpoint);
      final isDeprecatedRestaurantsEndpoint =
          uri?.host.toLowerCase() == "selfpos.sirixo.com" &&
              uri?.path.toLowerCase() == "/api/all-restaurants";
      if (isDeprecatedRestaurantsEndpoint) continue;
      try {
        kioskLog('validating restaurant id via $endpoint', tag: 'SETUP');
        final res = await dio.get(endpoint);
        final data = res.data;
        final rawList = data is List
            ? data
            : (data is Map
                ? (data["data"] ?? data["restaurants"] ?? data["items"])
                : null);
        if (rawList is! List) continue;
        for (final item in rawList.whereType<Map>()) {
          final itemId = item["id"]?.toString().trim() ?? "";
          if (itemId != id) continue;
          if (persistMatch) {
            final prefs = await SharedPreferences.getInstance();
            final selectedName = item["name"]?.toString().trim() ?? "";
            if (selectedName.isNotEmpty) {
              await prefs.setString("restaurant_name", selectedName);
              if (mounted) {
                setState(() {
                  restaurantName = selectedName;
                });
              }
            }
            final selectedHash = item["hash"]?.toString().trim() ?? "";
            if (selectedHash.isNotEmpty) {
              await prefs.setString("restaurant_hash", selectedHash);
            }
          }
          return true;
        }
      } catch (e, stackTrace) {
        kioskLogError(
          'restaurant validation endpoint failed: $endpoint -> $e',
          tag: 'SETUP',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
    return false;
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

  String _norm(String? value) => (value ?? "").trim().toLowerCase();

  Future<void> _resolveRestaurantIdFromPublicApi(
      SharedPreferences prefs) async {
    final existing = prefs.getString("restaurant_id")?.trim() ?? "";
    final existingName = prefs.getString("restaurant_name")?.trim() ?? "";
    final existingHash = prefs.getString("restaurant_hash")?.trim() ?? "";
    if (existing.isNotEmpty && RegExp(r'^\d+$').hasMatch(existing)) return;

    final targetNames = <String>{
      _norm(restaurantName),
      _norm(existingName),
      _norm(_settingsData?["restaurant_name"]?.toString()),
      _norm(_settingsData?["name"]?.toString()),
    }..removeWhere((v) => v.isEmpty || v == "restaurant");
    final targetIds = <String>{
      existing.toLowerCase(),
      existingHash.toLowerCase(),
    }..removeWhere((v) => v.trim().isEmpty);

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 12),
        headers: const {"Accept": "application/json"},
      ),
    );

    final endpoints = <String>[
      WebApiConfig.allRestaurantsUrl,
      "http://127.0.0.1:8000/api/all-restaurants",
    ];

    for (final endpoint in endpoints) {
      final uri = Uri.tryParse(endpoint);
      final isDeprecatedRestaurantsEndpoint =
          uri?.host.toLowerCase() == "selfpos.sirixo.com" &&
              uri?.path.toLowerCase() == "/api/all-restaurants";
      if (isDeprecatedRestaurantsEndpoint) continue;
      try {
        final res = await dio.get(endpoint);
        final data = res.data;
        final rawList = data is List
            ? data
            : (data is Map
                ? (data["data"] ?? data["restaurants"] ?? data["items"])
                : null);
        if (rawList is! List || rawList.isEmpty) continue;

        Map<String, dynamic>? selected;
        for (final item in rawList.whereType<Map>()) {
          final mapped = item.map((k, v) => MapEntry("$k", v));
          final name = _norm(mapped["name"]?.toString());
          final id = _norm(mapped["id"]?.toString());
          final hash = _norm(mapped["hash"]?.toString());
          if (targetIds.contains(id) || targetIds.contains(hash)) {
            selected = mapped;
            break;
          }
          if (targetNames.contains(name)) {
            selected = mapped;
            break;
          }
        }

        if (selected == null && rawList.length == 1) {
          final only = rawList.first;
          if (only is Map) {
            selected = only.map((k, v) => MapEntry("$k", v));
          }
        }

        if (selected == null) continue;

        final selectedId = selected["id"]?.toString().trim() ?? "";
        if (selectedId.isEmpty) continue;

        await prefs.setString("restaurant_id", selectedId);
        final selectedName = selected["name"]?.toString().trim() ?? "";
        if (selectedName.isNotEmpty) {
          await prefs.setString("restaurant_name", selectedName);
        }
        final selectedHash = selected["hash"]?.toString().trim() ?? "";
        if (selectedHash.isNotEmpty) {
          await prefs.setString("restaurant_hash", selectedHash);
        }
        return;
      } catch (_) {}
    }
  }

  Future<T> _withKioskTokenRecovery<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      final message = e.toString().toLowerCase();
      final needsRecovery = message.contains("kiosk token missing") ||
          message.contains("auth_token") ||
          message.contains("restaurant_not_configured") ||
          message.contains("restaurant not configured") ||
          message.contains("unauthorized");
      if (!needsRecovery) rethrow;
      final prefs = await SharedPreferences.getInstance();
      await _persistRestaurantContext(
        prefs: prefs,
        settings: _settingsData,
        restaurant: <String, dynamic>{
          "name": restaurantName,
        },
      );
      await _resolveRestaurantIdFromPublicApi(prefs);
      await DeviceBootstrap.ensureDeviceReady();
      return action();
    }
  }

  bool _looksLikeServerErrorText(String message) {
    final m = message.toLowerCase();
    return m.contains("500") ||
        m.contains("server error") ||
        m.contains("internal server error");
  }

  Future<_ScanPaymentState> _resolveScanPaymentState(int orderId) async {
    var hadServerFailure = false;

    try {
      final paymentRes = await _withKioskTokenRecovery(
        () => KioskApi().checkPayment(orderId),
      );
      if (_containsPaidState(paymentRes.data, 5)) {
        return _ScanPaymentState.paid;
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code >= 500) {
        hadServerFailure = true;
      } else {
        rethrow;
      }
    } catch (e) {
      if (_looksLikeServerErrorText(e.toString())) {
        hadServerFailure = true;
      } else {
        rethrow;
      }
    }

    try {
      final detailsRes = await _withKioskTokenRecovery(
        () => KioskApi().getOrderDetails(orderId),
      );
      if (_containsPaidState(detailsRes.data, 6)) {
        return _ScanPaymentState.paid;
      }
      if (!hadServerFailure) {
        return _ScanPaymentState.unpaid;
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code >= 500) {
        hadServerFailure = true;
      } else {
        rethrow;
      }
    } catch (e) {
      if (_looksLikeServerErrorText(e.toString())) {
        hadServerFailure = true;
      } else {
        rethrow;
      }
    }

    return hadServerFailure
        ? _ScanPaymentState.unverifiedServerError
        : _ScanPaymentState.unpaid;
  }

  String _friendlyDioError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final path = e.requestOptions.path;
      final base = e.requestOptions.baseUrl;
      if (status != null) {
        return "HTTP $status ($base$path)";
      }
      return "$base$path: ${e.message ?? e.type.name}";
    }
    return e.toString();
  }

  Future<void> _runScannerTriggeredOrderPrint({
    required int orderId,
    required String scannedValue,
  }) async {
    if (!mounted || _scannerPrintRunning) return;
    setState(() {
      _scannerPrintRunning = true;
      _scannerStatus =
          'Payment QR "$scannedValue" detected. Checking payment...';
    });
    try {
      final paymentState = await _resolveScanPaymentState(orderId);
      if (paymentState == _ScanPaymentState.unpaid) {
        if (!mounted) return;
        setState(() {
          _scannerStatus = "Order #$orderId is not paid yet.";
        });
        _showSnackBar(
            "Order #$orderId is not paid yet.", Colors.orange.shade800);
        return;
      }

      if (!mounted) return;
      setState(() {
        _scannerStatus = paymentState == _ScanPaymentState.unverifiedServerError
            ? "Payment API temporary issue (500). Printing by scanned QR..."
            : "Payment verified for order #$orderId. Printing...";
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
      _showSnackBar(
          "Order #$orderId printed successfully.", Colors.green.shade700);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scannerStatus = "Print failed for order #$orderId.";
      });
      _showSnackBar("Print failed for order #$orderId: ${_friendlyDioError(e)}",
          Colors.red.shade700);
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

  bool _isAnyTextInputFocused() {
    if (_restaurantIdFocusNode.hasFocus ||
        _kioskNameFocusNode.hasFocus ||
        _scannerFocusNode.hasFocus) {
      return true;
    }
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    if (focusedContext.widget is EditableText) return true;
    return focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
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
    if (_isAnyTextInputFocused()) {
      return;
    }
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
        leadingWidth: 90,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: Image.asset(
              "assets/self.png",
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
        ),
        title: const Text(
          "Kiosk Setup",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              children: [
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Restaurant ID",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _restaurantIdCtrl,
                        focusNode: _restaurantIdFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                          signed: false,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: "Enter restaurant ID (e.g. 24)",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFF1B8E3E)),
                          SizedBox(width: 8),
                          Text(
                            "Restaurant Selected",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        restaurantName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
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
                const SizedBox(height: 16),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Complete these 3 quick steps",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _stepRow("1", "Enter device name and save"),
                      const SizedBox(height: 6),
                      _stepRow("2", "Setup USB printer and run test print"),
                      const SizedBox(height: 6),
                      _stepRow("3", "Scan test code to check scanner"),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Step 1: Device Name",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _kioskNameCtrl,
                        focusNode: _kioskNameFocusNode,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          fontSize: 18,
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
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Step 2: Printer Setup",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Connect/select USB printer and run test print.",
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
                const SizedBox(height: 24),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              "Step 3: Scanner Test",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              if (!mounted) return;
                              setState(() {
                                _showAdvancedScanner = !_showAdvancedScanner;
                              });
                              if (_showAdvancedScanner) {
                                _focusScannerField();
                              }
                            },
                            icon: Icon(
                              _showAdvancedScanner
                                  ? Icons.expand_less_rounded
                                  : Icons.tune_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _showAdvancedScanner ? "Hide" : "Advanced",
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Background scanner listener is active.\n"
                        "Scan-to-print after payment works even when this section is hidden.",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      if (_showAdvancedScanner) ...[
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
                      ] else ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F7FA),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFD8E0E8)),
                          ),
                          child: const Text(
                            "Scanner tools hidden. Tap Advanced to open manual scan test and last scan details.",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF516173),
                            ),
                          ),
                        ),
                      ],
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

  Widget _stepRow(String step, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF9F342C),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
