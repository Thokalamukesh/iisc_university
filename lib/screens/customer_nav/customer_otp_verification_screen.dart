import 'dart:async';

import 'package:api_selfxo_project/screens/customer_nav/customer_auth_layout.dart';
import 'package:api_selfxo_project/services/firebase_auth_service.dart';
import 'package:api_selfxo_project/services/pwa_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _snackGreen = Color(0xFF2E7D32);

class CustomerOtpVerificationScreen extends StatefulWidget {
  final String mobileNumber;
  final FirebaseOtpSession otpSession;

  const CustomerOtpVerificationScreen({
    super.key,
    required this.mobileNumber,
    required this.otpSession,
  });

  @override
  State<CustomerOtpVerificationScreen> createState() =>
      _CustomerOtpVerificationScreenState();
}

class _CustomerOtpVerificationScreenState
    extends State<CustomerOtpVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  Timer? _timer;
  int _secondsLeft = 30;
  bool _verifying = false;
  bool _resending = false;
  late FirebaseOtpSession _otpSession;

  String get _otp => _otpController.text;

  String get _maskedMobile {
    final mobile = widget.mobileNumber;
    if (mobile.length < 4) return mobile;
    return "${mobile.substring(0, 2)}XXXX${mobile.substring(mobile.length - 4)}";
  }

  @override
  void initState() {
    super.initState();
    _otpSession = widget.otpSession;
    _otpFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    _otpFocusNode.dispose();
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

  Future<void> _resendOtp() async {
    if (_resending) return;
    setState(() => _resending = true);
    _otpController.clear();
    try {
      await PwaAuthService.instance.checkRateLimit(widget.mobileNumber);
      _otpSession =
          await FirebaseAuthService.instance.sendOtp(widget.mobileNumber);
      _otpFocusNode.requestFocus();
      _startTimer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("OTP resent"),
          backgroundColor: _snackGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_otpErrorMessage(e)),
          backgroundColor: _snackGreen,
        ),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_verifying) return;

    if (_otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter the 6-digit OTP"),
          backgroundColor: _snackGreen,
        ),
      );
      return;
    }

    setState(() => _verifying = true);
    try {
      // Step 1: Verify OTP with Firebase → get ID token
      final firebaseIdToken = await FirebaseAuthService.instance.verifyOtp(
        session: _otpSession,
        otp: _otp,
      );

      // Step 2: Exchange Firebase ID token for Sanctum token
      final firebaseUid = FirebaseAuthService.instance.currentUid ?? '';
      await PwaAuthService.instance.login(
        firebaseIdToken: firebaseIdToken,
        firebaseUid: firebaseUid,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_otpErrorMessage(e)),
          backgroundColor: _snackGreen,
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Mobile number verified"),
        backgroundColor: _snackGreen,
      ),
    );
    Navigator.of(context).pop(true);
  }

  String _otpErrorMessage(Object error) {
    final message = error.toString().replaceFirst("Exception: ", "").trim();
    if (message.isEmpty) return "Unable to verify OTP. Please try again.";
    return message;
  }

  void _handleOtpChanged(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final limitedDigits = digits.length > 6 ? digits.substring(0, 6) : digits;

    if (_otpController.text == limitedDigits) {
      setState(() {});
      if (limitedDigits.length == 6) {
        FocusScope.of(context).unfocus();
        _verifyOtp();
      }
      return;
    }

    _otpController.value = TextEditingValue(
      text: limitedDigits,
      selection: TextSelection.collapsed(offset: limitedDigits.length),
    );
    setState(() {});

    if (_otp.length == 6) {
      FocusScope.of(context).unfocus();
      _verifyOtp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerAuthLayout(
      title: "Verify your mobile number",
      subtitle: "Enter the 6-digit code sent to +91 $_maskedMobile.",
      icon: Icons.password_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E2E7)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.phone_android_rounded,
                    color: CustomerAuthLayout.brandColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "OTP sent",
                        style: TextStyle(
                          color: CustomerAuthLayout.textColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "+91 $_maskedMobile",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CustomerAuthLayout.mutedTextColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text("Edit"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Enter code",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: CustomerAuthLayout.textColor,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final boxSize =
                  ((constraints.maxWidth - 50) / 6).clamp(42.0, 56.0);

              return AutofillGroup(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _otpFocusNode.requestFocus(),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _hiddenOtpField(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          6,
                          (index) => _otpBox(index, boxSize),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _verifying ? null : _verifyOtp,
              icon: _verifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(
                _verifying ? "Verifying" : "Verify OTP",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: CustomerAuthLayout.brandColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: CustomerAuthLayout.brandColor,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: _secondsLeft == 0 && !_resending ? _resendOtp : null,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                _resending
                    ? "Resending OTP"
                    : _secondsLeft == 0
                        ? "Resend OTP"
                        : "Resend OTP in ${_secondsLeft}s",
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: CustomerAuthLayout.mutedTextColor,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "This keeps your order history and account access secure. This site is protected by reCAPTCHA.",
                  style: TextStyle(
                    color: CustomerAuthLayout.mutedTextColor,
                    height: 1.35,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
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
        controller: _otpController,
        focusNode: _otpFocusNode,
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
        onSubmitted: (_) => _verifyOtp(),
      ),
    );
  }

  Widget _otpBox(int index, double size) {
    final value = index < _otp.length ? _otp[index] : "";
    final isFocused = _otpFocusNode.hasFocus && _otp.length == index;

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFocused
                ? CustomerAuthLayout.brandColor
                : const Color(0xFFE2E2E7),
            width: isFocused ? 1.4 : 1,
          ),
        ),
        child: Text(
          value,
          style: const TextStyle(
            color: CustomerAuthLayout.textColor,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
