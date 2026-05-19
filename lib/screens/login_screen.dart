import 'package:api_selfxo_project/screens/otp_screen.dart';
import 'package:api_selfxo_project/services/firebase_auth_service.dart';
import 'package:api_selfxo_project/services/pwa_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FoodOtpLoginScreen extends StatefulWidget {
  final WidgetBuilder? afterVerifiedBuilder;

  const FoodOtpLoginScreen({
    super.key,
    this.afterVerifiedBuilder,
  });

  @override
  State<FoodOtpLoginScreen> createState() => _FoodOtpLoginScreenState();
}

class _FoodOtpLoginScreenState extends State<FoodOtpLoginScreen> {
  static const Color primary = Color(0xFF9F342C);
  static const Color bg = Color(0xFFF6F6F7);
  static const String _buildStamp =
      String.fromEnvironment("SELFX_BUILD_STAMP", defaultValue: "local");

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final FocusNode phoneFocusNode = FocusNode();

  String? errorText;
  String? _statusText;
  bool _sendingOtp = false;

  @override
  void dispose() {
    phoneController.dispose();
    nameController.dispose();
    phoneFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_sendingOtp) return;

    final mobile = phoneController.text.trim();
    debugPrint("[OTP] Get OTP tapped. mobile_length=${mobile.length}");
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile)) {
      debugPrint("[OTP] Invalid mobile number format.");
      setState(() {
        errorText = "Enter a valid 10-digit mobile number";
        _statusText = null;
      });
      return;
    }

    setState(() {
      _sendingOtp = true;
      errorText = null;
      _statusText = "Checking rate limit...";
    });

    // Step 1: Rate limit check against Laravel backend
    try {
      await PwaAuthService.instance.checkRateLimit(mobile);
    } catch (e) {
      debugPrint("[OTP] Rate limit check failed: $e");
      if (!mounted) return;
      setState(() {
        _sendingOtp = false;
        errorText = _readableError(e);
        _statusText = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _statusText = "Sending OTP to +91 $mobile...");

    // Step 2: Send OTP via Firebase
    FirebaseOtpSession session;
    try {
      debugPrint("[OTP] Calling Firebase sendOtp for +91$mobile");
      session = await FirebaseAuthService.instance.sendOtp(mobile);
      debugPrint("[OTP] Firebase sendOtp completed.");
    } catch (e) {
      debugPrint("[OTP] Firebase sendOtp failed: $e");
      if (!mounted) return;
      setState(() {
        _sendingOtp = false;
        errorText = _readableError(e);
        _statusText = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _sendingOtp = false;
      _statusText = "OTP sent. Opening verification screen...";
    });

    // Step 3: Navigate to OTP verify screen, passing the optional name
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FoodOtpVerifyScreen(
            mobileNumber: mobile,
            otpSession: session,
            customerName: nameController.text.trim(),
            afterVerifiedBuilder: widget.afterVerifiedBuilder,
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _statusText = null);
    } catch (e, stack) {
      debugPrint("[OTP] Failed to open verification screen: $e");
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      setState(() {
        errorText =
            "OTP was sent, but the verification screen could not open. Please refresh and try again.";
        _statusText = null;
      });
    }
  }

  String _readableError(Object error) {
    final message = error.toString().replaceFirst("Exception: ", "").trim();
    if (message.isEmpty) return "Unable to send OTP. Please try again.";
    return message;
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
                    _topHeroSection(),
                    Transform.translate(
                      offset: const Offset(0, -34),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _loginCard(),
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

  Widget _topHeroSection() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
      child: Container(
        width: double.infinity,
        height: 270,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7A211E), primary, Color(0xFFD85B43)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(.08),
                      Colors.transparent,
                      Colors.black.withOpacity(.16),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 42),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 92,
                      height: 44,
                      child: Image.asset(
                        "assets/self.png",
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 72),
                      child: Text(
                        "Sign in",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Optional Name field ---
          const Text(
            "Your Name",
            style: TextStyle(
              color: Color(0xFF151518),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: nameController,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => phoneFocusNode.requestFocus(),
            decoration: InputDecoration(
              counterText: "",
              hintText: "e.g. Kumar  (optional)",
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: const Color(0xFFF5F5F6),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE7E7EA)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // --- Mobile number section ---
          Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Mobile Number",
                style: TextStyle(
                  color: Color(0xFF151518),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _countryBox(),
              const SizedBox(width: 12),
              Expanded(child: _phoneField()),
            ],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 14),
            _InlineError(message: errorText!),
          ],
          if (_statusText != null) ...[
            const SizedBox(height: 14),
            _InlineStatus(message: _statusText!),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: _sendingOtp ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: primary,
                disabledBackgroundColor: primary.withOpacity(.65),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _sendingOtp
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      "Get OTP",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              "Build $_buildStamp",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              "Terms & Conditions",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: primary,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countryBox() {
    return Container(
      width: 60,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E7EA)),
      ),
      alignment: Alignment.center,
      child: const Text(
        "+91",
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _phoneField() {
    return TextField(
      controller: phoneController,
      focusNode: phoneFocusNode,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumber],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      onSubmitted: (_) => _sendOtp(),
      decoration: InputDecoration(
        counterText: "",
        hintText: "99999 99999",
        hintStyle: TextStyle(color: Colors.grey.shade400),
        filled: true,
        fillColor: const Color(0xFFF5F5F6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE7E7EA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineStatus extends StatelessWidget {
  final String message;

  const _InlineStatus({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF395B2E),
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
