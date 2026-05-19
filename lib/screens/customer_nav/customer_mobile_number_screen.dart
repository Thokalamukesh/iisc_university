import 'package:api_selfxo_project/screens/customer_nav/customer_auth_layout.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_otp_verification_screen.dart';
import 'package:api_selfxo_project/services/firebase_auth_service.dart';
import 'package:api_selfxo_project/services/pwa_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color _snackGreen = Color(0xFF2E7D32);

class CustomerMobileNumberScreen extends StatefulWidget {
  final WidgetBuilder? afterVerifiedBuilder;

  const CustomerMobileNumberScreen({
    super.key,
    this.afterVerifiedBuilder,
  });

  @override
  State<CustomerMobileNumberScreen> createState() =>
      _CustomerMobileNumberScreenState();
}

class _CustomerMobileNumberScreenState
    extends State<CustomerMobileNumberScreen> {
  final TextEditingController _mobileController = TextEditingController();
  String? _errorText;
  bool _sendingOtp = false;

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _continueToOtp() async {
    if (_sendingOtp) return;

    final mobile = _mobileController.text.trim();
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile)) {
      setState(() => _errorText = "Enter a valid 10-digit mobile number");
      return;
    }

    setState(() {
      _errorText = null;
      _sendingOtp = true;
    });

    FirebaseOtpSession otpSession;
    try {
      await PwaAuthService.instance.checkRateLimit(mobile);
      otpSession = await FirebaseAuthService.instance.sendOtp(mobile);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingOtp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_otpErrorMessage(e)),
          backgroundColor: _snackGreen,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _sendingOtp = false);

    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerOtpVerificationScreen(
          mobileNumber: mobile,
          otpSession: otpSession,
        ),
      ),
    );

    if (!mounted) return;
    if (verified == true) {
      final nextBuilder = widget.afterVerifiedBuilder;
      if (nextBuilder != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: nextBuilder),
        );
        return;
      }
      Navigator.of(context).pop(true);
    }
  }

  String _otpErrorMessage(Object error) {
    final message = error.toString().replaceFirst("Exception: ", "").trim();
    if (message.isEmpty) return "Unable to send OTP. Please try again.";
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return CustomerAuthLayout(
      title: "",
      subtitle: "",
      icon: Icons.phone_iphone_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Mobile number",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: CustomerAuthLayout.textColor,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E2E7)),
                ),
                child: const Center(
                  child: Text(
                    "+91",
                    style: TextStyle(
                      color: CustomerAuthLayout.textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: const TextStyle(
                    color: CustomerAuthLayout.textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: _inputDecoration(
                    hintText: "***** *****",
                    errorText: _errorText,
                  ),
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                  onSubmitted: (_) => _continueToOtp(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _sendingOtp ? null : _continueToOtp,
              icon: _sendingOtp
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sms_outlined),
              label: Text(
                _sendingOtp ? "Sending OTP" : "Get OTP",
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
          const SizedBox(height: 16),
          const Text(
            "By continuing, you agree to the Terms & Conditions",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CustomerAuthLayout.mutedTextColor,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hintText,
      errorText: errorText,
      filled: true,
      fillColor: const Color(0xFFF5F5F7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E2E7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: CustomerAuthLayout.brandColor,
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: CustomerAuthLayout.brandColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: CustomerAuthLayout.brandColor,
          width: 1.4,
        ),
      ),
    );
  }
}
