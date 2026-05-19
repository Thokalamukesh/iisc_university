import 'dart:async';

import 'package:api_selfxo_project/screens/block_screen.dart';
import 'package:api_selfxo_project/services/firebase_auth_service.dart';
import 'package:api_selfxo_project/services/pwa_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FoodOtpVerifyScreen extends StatefulWidget {
  final String mobileNumber;
  final FirebaseOtpSession otpSession;
  final String customerName; // optional — may be empty
  final WidgetBuilder? afterVerifiedBuilder;

  const FoodOtpVerifyScreen({
    super.key,
    required this.mobileNumber,
    required this.otpSession,
    this.customerName = '',
    this.afterVerifiedBuilder,
  });

  @override
  State<FoodOtpVerifyScreen> createState() => _FoodOtpVerifyScreenState();
}

class _FoodOtpVerifyScreenState extends State<FoodOtpVerifyScreen> {
  static const Color primary = Color(0xFF9F342C);
  static const Color bg = Color(0xFFF6F6F7);

  final TextEditingController otpController = TextEditingController();
  final FocusNode otpFocusNode = FocusNode();
  Timer? _timer;
  late FirebaseOtpSession _session;

  int _secondsLeft = 30;
  bool _verifying = false;
  bool _resending = false;
  bool _loginCompleted = false;
  String? _errorText;
  String? _statusText;

  String get _otp => otpController.text;

  String get _maskedMobile {
    final mobile = widget.mobileNumber.replaceAll(RegExp(r'\D'), '');
    if (mobile.length < 10) return widget.mobileNumber;
    return "+91 ${mobile.substring(0, 2)}XXXX${mobile.substring(6)}";
  }

  @override
  void initState() {
    super.initState();
    _session = widget.otpSession;
    otpFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    otpController.dispose();
    otpFocusNode.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsLeft = 0);
        return;
      }
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  Future<void> _verifyOtp([String? value]) async {
    if (_verifying) return;
    final otp = (value ?? _otp).replaceAll(RegExp(r'\D'), '');
    debugPrint("[OTP] Verify tapped. otp_length=${otp.length}");
    if (otp.length != 6) {
      setState(() => _errorText = "Enter a valid 6-digit OTP");
      return;
    }

    setState(() {
      _verifying = true;
      _errorText = null;
      _statusText = "Verifying OTP...";
    });

    try {
      // Step 1: Verify OTP with Firebase → get Firebase ID token
      debugPrint("[OTP] Verifying with Firebase...");
      final firebaseIdToken = await FirebaseAuthService.instance.verifyOtp(
        session: _session,
        otp: otp,
      );
      debugPrint("[OTP] Firebase verify completed. Token length=${firebaseIdToken.length}");

      if (!mounted) return;
      setState(() => _statusText = "Logging in...");

      // Step 2: Exchange Firebase ID token for Sanctum token via Laravel
      final firebaseUid = FirebaseAuthService.instance.currentUid ?? '';
      debugPrint("[OTP] Calling Laravel login API...");
      await PwaAuthService.instance.login(
        firebaseIdToken: firebaseIdToken,
        firebaseUid: firebaseUid,
        customerName: widget.customerName,
      );
      debugPrint("[OTP] Laravel login completed. Sanctum token stored.");

      // Step 3: Navigate to dashboard
      await _finishLogin();
    } catch (e) {
      debugPrint("[OTP] Verify failed: $e");
      if (!mounted) return;
      setState(() {
        _errorText = _readableError(e);
        _verifying = false;
        _statusText = null;
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_resending || _secondsLeft > 0) return;
    debugPrint("[OTP] Resend tapped for ${widget.mobileNumber}");
    setState(() {
      _resending = true;
      _errorText = null;
      _statusText = "Resending OTP...";
    });

    try {
      // Rate limit check first
      await PwaAuthService.instance.checkRateLimit(widget.mobileNumber);

      // Resend via Firebase
      _session = await FirebaseAuthService.instance.sendOtp(
        widget.mobileNumber,
      );
      otpController.clear();
      otpFocusNode.requestFocus();
      _startTimer();
      debugPrint("[OTP] Resend completed.");
      if (!mounted) return;
      setState(() => _statusText = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("OTP resent")),
      );
    } catch (e) {
      debugPrint("[OTP] Resend failed: $e");
      if (!mounted) return;
      setState(() {
        _errorText = _readableError(e);
        _statusText = null;
      });
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _finishLogin() async {
    if (_loginCompleted) return;
    _loginCompleted = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Login successful")),
    );
    final destination = widget.afterVerifiedBuilder?.call(context) ??
        const CustomerBlockScreen();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (_) => false,
    );
  }

  String _readableError(Object error) {
    final message = error.toString().replaceFirst("Exception: ", "").trim();
    if (message.isEmpty) return "Unable to verify OTP. Please try again.";
    return message;
  }

  void _handleOtpChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 6 ? digits.substring(0, 6) : digits;

    if (otpController.text == limitedDigits) {
      setState(() => _errorText = null);
      if (limitedDigits.length == 6) {
        FocusScope.of(context).unfocus();
        _verifyOtp(limitedDigits);
      }
      return;
    }

    otpController.value = TextEditingValue(
      text: limitedDigits,
      selection: TextSelection.collapsed(offset: limitedDigits.length),
    );
    setState(() => _errorText = null);

    if (limitedDigits.length == 6) {
      FocusScope.of(context).unfocus();
      _verifyOtp(limitedDigits);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: Column(
                  children: [
                    _topSection(),
                    Transform.translate(
                      offset: const Offset(0, -34),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _otpCard(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _topSection() {
    return Container(
      width: double.infinity,
      height: 230,
      padding: const EdgeInsets.fromLTRB(14, 12, 22, 48),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, Color(0xFFC5443A), Color(0xFFE9B89C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      child: Stack(
        children: [
          IconButton(
            onPressed: _verifying ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8, top: 68),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Verify OTP",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Code sent to $_maskedMobile",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _otpCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFEDECEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Enter 6-digit code",
              style: TextStyle(
                color: Color(0xFF151518),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            _otpInput(),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (_statusText != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusText!,
                    style: const TextStyle(
                      color: Color(0xFF395B2E),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _verifying ? null : () => _verifyOtp(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  disabledBackgroundColor: primary.withOpacity(.65),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _verifying
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Verify OTP",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _secondsLeft == 0 && !_resending ? _resendOtp : null,
              child: Text(
                _resending
                    ? "Resending OTP"
                    : _secondsLeft == 0
                        ? "Resend OTP"
                        : "Resend OTP in ${_secondsLeft}s",
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _otpInput() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => otpFocusNode.requestFocus(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          _hiddenOtpField(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, _otpBox),
          ),
        ],
      ),
    );
  }

  Widget _hiddenOtpField() {
    return SizedBox(
      width: 1,
      height: 1,
      child: TextField(
        controller: otpController,
        focusNode: otpFocusNode,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        textInputAction: TextInputAction.done,
        enableSuggestions: false,
        autocorrect: false,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        style: const TextStyle(color: Colors.transparent, fontSize: 1),
        cursorColor: Colors.transparent,
        decoration: const InputDecoration(
          border: InputBorder.none,
          counterText: "",
          isCollapsed: true,
        ),
        onChanged: _handleOtpChanged,
        onSubmitted: _verifyOtp,
      ),
    );
  }

  Widget _otpBox(int index) {
    final value = index < _otp.length ? _otp[index] : "";
    final isFocused = otpFocusNode.hasFocus && _otp.length == index;

    return SizedBox(
      width: 48,
      height: 56,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused ? primary : const Color(0xFFE7E7EA),
            width: isFocused ? 1.4 : 1.2,
          ),
        ),
        child: Text(
          value,
          style: const TextStyle(
            color: Color(0xFF151518),
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
