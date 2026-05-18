import 'dart:async';

import 'package:api_selfxo_project/screens/admin_dashboard_screens/adim_homescreen.dart';
import 'package:api_selfxo_project/core/device_layout.dart';
import 'package:api_selfxo_project/screens/main_navigation.dart';
import 'package:api_selfxo_project/screens/payment_success.dart';
import 'package:api_selfxo_project/widget/pos_payment_success_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

class PickupQrScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final int orderId;
  final String? restaurantName;
  final String? orderType;

  const PickupQrScreen({
    super.key,
    required this.cart,
    required this.orderId,
    this.restaurantName,
    this.orderType,
  });

  @override
  State<PickupQrScreen> createState() => _PickupQrScreenState();
}

class _PickupQrScreenState extends State<PickupQrScreen> {
  static const Duration _screenTimeout = Duration(minutes: 2);

  final FocusNode _keyboardFocusNode =
      FocusNode(debugLabel: 'pickup-qr-keyboard');
  final FocusNode _scanInputFocusNode =
      FocusNode(debugLabel: 'pickup-qr-input');
  final TextEditingController _scanController = TextEditingController();
  final StringBuffer _scanBuffer = StringBuffer();

  Timer? _scanIdleTimer;
  Timer? _textIdleTimer;
  Timer? _focusKeepAliveTimer;
  Timer? _autoReturnTimer;
  Timer? _countdownTimer;
  late final KeyEventCallback _globalKeyHandler;

  bool _isPrinting = false;
  bool _isNavigating = false;
  String? _lastScan;
  String _statusText = "Scanner is ready. Scan pickup QR to print receipt.";
  String? _errorText;
  Duration _remaining = _screenTimeout;

  String get _pickupCode => "PRINT_ORDER_${widget.orderId}";

  @override
  void initState() {
    super.initState();
    _globalKeyHandler = (event) {
      if (!mounted || _isPrinting || event is! KeyDownEvent) {
        return false;
      }
      _handleKeyEvent(event);
      return true;
    };
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
    _startAutoReturnTimers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScannerInput();
      _focusKeepAliveTimer =
          Timer.periodic(const Duration(milliseconds: 700), (_) {
        if (!mounted || _isPrinting) return;
        _focusScannerInput();
      });
    });
  }

  @override
  void dispose() {
    _scanIdleTimer?.cancel();
    _textIdleTimer?.cancel();
    _focusKeepAliveTimer?.cancel();
    _autoReturnTimer?.cancel();
    _countdownTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    _scanController.dispose();
    _scanInputFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _startAutoReturnTimers() {
    _autoReturnTimer?.cancel();
    _countdownTimer?.cancel();
    _remaining = _screenTimeout;
    _autoReturnTimer = Timer(_screenTimeout, _navigateHome);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final next = _remaining - const Duration(seconds: 1);
        _remaining = next.isNegative ? Duration.zero : next;
      });
    });
  }

  void _focusScannerInput() {
    if (_scanInputFocusNode.canRequestFocus) {
      _scanInputFocusNode.requestFocus();
      return;
    }
    if (_keyboardFocusNode.canRequestFocus) {
      _keyboardFocusNode.requestFocus();
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (_isPrinting || event is! KeyDownEvent) {
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      final captured = _scanBuffer.toString();
      _scanBuffer.clear();
      _consumeScan(captured, source: "keyboard-enter");
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_scanBuffer.isNotEmpty) {
        final current = _scanBuffer.toString();
        _scanBuffer
          ..clear()
          ..write(current.substring(0, current.length - 1));
      }
      _scheduleScanIdleFlush();
      return;
    }

    final character =
        event.character ?? _characterFromLogicalKey(event.logicalKey);
    if (character != null &&
        character.isNotEmpty &&
        !_isControlCharacter(character)) {
      _scanBuffer.write(character);
      _setStatus("Receiving scanner input...");
      _scheduleScanIdleFlush();
      return;
    }
  }

  String? _characterFromLogicalKey(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.length == 1) return label;
    return null;
  }

  bool _isControlCharacter(String value) {
    final code = value.codeUnitAt(0);
    return code < 32 || code == 127;
  }

  void _scheduleScanIdleFlush() {
    _scanIdleTimer?.cancel();
    _scanIdleTimer = Timer(const Duration(milliseconds: 450), () {
      final captured = _scanBuffer.toString();
      _scanBuffer.clear();
      _consumeScan(captured, source: "keyboard-idle");
    });
  }

  void _handleScannerTextChanged(String value) {
    if (_isPrinting) return;
    _textIdleTimer?.cancel();
    _textIdleTimer = Timer(const Duration(milliseconds: 550), () {
      final captured = _scanController.text;
      _scanController.clear();
      _consumeScan(captured, source: "input-idle");
    });
  }

  void _handleScannerSubmitted(String value) {
    if (_isPrinting) return;
    _textIdleTimer?.cancel();
    _scanController.clear();
    _consumeScan(value, source: "input-submit");
  }

  String _sanitizeScan(String raw) {
    return raw
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  bool _matchesPickupCode(String value) {
    final normalized = _sanitizeScan(value).toUpperCase();
    final expected = _pickupCode.toUpperCase();
    if (normalized == expected) return true;
    return normalized.contains(expected);
  }

  void _consumeScan(String raw, {required String source}) {
    final value = _sanitizeScan(raw);
    if (value.isEmpty) return;

    setState(() {
      _lastScan = value;
    });

    if (_matchesPickupCode(value)) {
      _setStatus('Scanner matched "$value". Printing receipt...');
      _printAfterScan(source: source);
      return;
    }

    setState(() {
      _errorText = 'Scanned "$value". Expected $_pickupCode.';
      _statusText = "Wrong QR scanned. Please scan this screen QR.";
    });
    _focusScannerInput();
  }

  Future<void> _printAfterScan({required String source}) async {
    if (_isPrinting || _isNavigating) return;
    setState(() {
      _isPrinting = true;
      _errorText = null;
      _statusText = "Printing receipt...";
    });

    try {
      final popupItems = _popupItemsFromCart(widget.cart);
      final popupTotal = _popupBillFromCart(widget.cart);
      final popupAmountText = popupTotal == null
          ? "-"
          : (popupTotal % 1 == 0
              ? "Rs ${popupTotal.toStringAsFixed(0)}"
              : "Rs ${popupTotal.toStringAsFixed(2)}");
      unawaited(
        showPosPaymentSuccessDialog(
          context,
          autoClose: const Duration(milliseconds: 1100),
          data: PosPaymentSuccessData(
            orderId: widget.orderId.toString(),
            amountPaid: popupAmountText,
            amountLabel: "Bill Amount",
            paymentMethod: "QR Scan",
            dateTimeText: DateTime.now()
                .toLocal()
                .toIso8601String()
                .replaceFirst('T', ' ')
                .split('.')
                .first,
            orderedItems: popupItems,
            title: "Scan Accepted",
            subtitle: "Receipt Printing",
          ),
        ),
      );
      await PaymentSuccessDialog.printReceiptUsingTabletFlow(
        cart: widget.cart,
        orderNumber: widget.orderId,
        restaurantName: widget.restaurantName,
        orderType: widget.orderType,
      );

      if (!mounted) return;
      setState(() {
        _isPrinting = false;
        _statusText = "Print successful. Opening success screen...";
      });
      _openPaymentSuccess(
          debugSource: 'pickup_qr $source scan=${_lastScan ?? ""}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPrinting = false;
        _errorText = "Print failed: $e";
        _statusText = "Printing failed. Retry printing.";
      });
      _focusScannerInput();
    }
  }

  List<String> _popupItemsFromCart(List<Map<String, dynamic>> cart) {
    final lines = <String>[];
    for (final item in cart) {
      final name = (item["name"] ?? item["item_name"] ?? "").toString().trim();
      if (name.isEmpty) continue;
      final qty =
          _numValue(item["qty"] ?? item["quantity"] ?? item["count"]) ?? 1;
      final price = _numValue(
            item["amount"] ??
                item["total"] ??
                item["price"] ??
                item["unit_price"] ??
                item["rate"],
          ) ??
          0;
      final qtyText = qty % 1 == 0 ? qty.toStringAsFixed(0) : qty.toString();
      final lineTotal = qty * price;
      final amountText = lineTotal % 1 == 0
          ? lineTotal.toStringAsFixed(0)
          : lineTotal.toStringAsFixed(2);
      lines.add("$qtyText x $name (Rs $amountText)");
      if (lines.length >= 6) break;
    }
    return lines;
  }

  num? _popupBillFromCart(List<Map<String, dynamic>> cart) {
    num total = 0;
    var hasValue = false;
    for (final item in cart) {
      final qty =
          _numValue(item["qty"] ?? item["quantity"] ?? item["count"]) ?? 1;
      final amount = _numValue(item["amount"] ?? item["total"]);
      if (amount != null) {
        total += amount;
        hasValue = true;
        continue;
      }
      final unit =
          _numValue(item["price"] ?? item["unit_price"] ?? item["rate"]);
      if (unit != null) {
        total += unit * qty;
        hasValue = true;
      }
    }
    return hasValue ? total : null;
  }

  num? _numValue(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }

  void _setStatus(String text) {
    if (!mounted) return;
    setState(() {
      _statusText = text;
    });
  }

  void _openPaymentSuccess({String? debugSource}) {
    if (!mounted || _isNavigating) return;
    _isNavigating = true;
    _autoReturnTimer?.cancel();
    _countdownTimer?.cancel();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessDialog(
          cart: widget.cart,
          orderNumber: widget.orderId,
          language: "en",
          restaurantName: widget.restaurantName,
          orderType: widget.orderType,
          autoPrint: false,
          debugSource: debugSource,
        ),
      ),
    );
  }

  void _navigateHome() {
    if (!mounted || _isNavigating) return;
    _isNavigating = true;
    final bool isTablet = !kIsWeb && isTabletContext(context);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => isTablet
            ? const AdminHomeScreen()
            : MainNavigation(orderType: widget.orderType ?? 'dine_in'),
      ),
      (_) => false,
    );
  }

  String _formatRemaining(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 720;
    final qrSize = isTablet ? 320.0 : 230.0;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Back is disabled on this screen"),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Scaffold(
        body: SafeArea(
          child: KeyboardListener(
            focusNode: _keyboardFocusNode,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _focusScannerInput,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0E1220),
                      Color(0xFF1E2A4A),
                      Color(0xFF25385F)
                    ],
                  ),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 780),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 38 : 24,
                          vertical: isTablet ? 34 : 24,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 26,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              "Payment Successful",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isTablet ? 36 : 28,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "Show this QR at counter for printing",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF334155),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: QrImageView(
                                  data: _pickupCode,
                                  size: qrSize,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SelectableText(
                              _pickupCode,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isTablet ? 22 : 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: isTablet ? 2.2 : 1.2,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Auto return in ${_formatRemaining(_remaining)}",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _statusText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _errorText == null
                                    ? const Color(0xFF166534)
                                    : const Color(0xFFB91C1C),
                              ),
                            ),
                            if (_lastScan != null && _lastScan!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Last scan: $_lastScan',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                            if (_errorText != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1F2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFFDA4AF)),
                                ),
                                child: Text(
                                  _errorText!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF9F1239),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed:
                                        _isPrinting ? null : _navigateHome,
                                    child: const Text("Cancel"),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: (_isPrinting ||
                                            _errorText == null)
                                        ? null
                                        : () =>
                                            _printAfterScan(source: "retry"),
                                    icon: _isPrinting
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.print_rounded),
                                    label: Text(
                                      _isPrinting
                                          ? "Printing..."
                                          : "Retry Print",
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F766E),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
