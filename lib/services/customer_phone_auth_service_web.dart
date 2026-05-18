import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:api_selfxo_project/api/dio_client.dart';
import 'package:api_selfxo_project/firebase_options.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerOtpSession {
  final String phoneNumber;
  final ConfirmationResult? confirmationResult;
  final String otpCode;

  const CustomerOtpSession({
    required this.phoneNumber,
    this.confirmationResult,
    required this.otpCode,
  });
}

class CustomerPhoneAuthService {
  CustomerPhoneAuthService._();

  static final CustomerPhoneAuthService instance = CustomerPhoneAuthService._();

  static const String dummyMobileNumber = "8790701275";
  static const String dummyOtp = "";
  static const String recaptchaContainerId = "recaptcha-container";
  static const Duration _firebaseTimeout = Duration(seconds: 90);

  bool _firebaseReady = false;

  Future<CustomerOtpSession> sendOtp(String mobileNumber) async {
    _log("sendOtp started. raw_length=${mobileNumber.length} host=${Uri.base.host}");
    await _ensureFirebaseReady();
    _ensureRecaptchaContainer();
    await _checkRateLimit(mobileNumber);

    final phoneNumber = _toIndianE164(mobileNumber);
    _log("calling FirebaseAuth.signInWithPhoneNumber for $phoneNumber");
    late ConfirmationResult confirmationResult;
    final verifier = _createRecaptchaVerifier();
    try {
      confirmationResult = await FirebaseAuth.instance
          .signInWithPhoneNumber(phoneNumber, verifier)
          .timeout(_firebaseTimeout);
      _log("Firebase OTP SMS request accepted. verificationId_present=${confirmationResult.verificationId.isNotEmpty}");
      _resetRecaptchaVerifier(verifier, "OTP SMS request accepted");
    } on FirebaseAuthException catch (e) {
      _logFirebaseException("sendOtp", e);
      if (_shouldResetRecaptcha(e.code)) {
        _resetRecaptchaVerifier(verifier, "FirebaseAuthException ${e.code}");
      }
      throw Exception(_firebaseAuthMessage(e));
    } on TimeoutException catch (e) {
      _log("sendOtp timed out: $e");
      _resetRecaptchaVerifier(verifier, "sendOtp timeout");
      throw Exception(
        "OTP request timed out. Please complete the reCAPTCHA prompt and try again.",
      );
    } catch (e, stack) {
      _log("sendOtp unexpected failure: $e");
      debugPrintStack(stackTrace: stack);
      _resetRecaptchaVerifier(verifier, "unexpected sendOtp failure");
      throw Exception("Unable to send OTP. Please refresh and try again.");
    }

    return CustomerOtpSession(
      phoneNumber: phoneNumber,
      confirmationResult: confirmationResult,
      otpCode: dummyOtp,
    );
  }

  Future<void> verifyOtp({
    required CustomerOtpSession session,
    required String otp,
  }) async {
    _log("verifyOtp started. otp_length=${otp.length}");
    await _ensureFirebaseReady();

    final digits = otp.replaceAll(RegExp(r'\D'), '');
    final confirmationResult = session.confirmationResult;
    if (confirmationResult == null) {
      throw Exception("OTP session expired. Please request OTP again.");
    }

    late UserCredential credential;
    try {
      credential = await confirmationResult.confirm(digits).timeout(
            _firebaseTimeout,
          );
      _log("Firebase OTP confirm completed. user_present=${credential.user != null}");
    } on FirebaseAuthException catch (e) {
      _logFirebaseException("verifyOtp", e);
      throw Exception(_firebaseAuthMessage(e));
    } on TimeoutException catch (e) {
      _log("verifyOtp timed out: $e");
      throw Exception("OTP verification timed out. Please try again.");
    } catch (e, stack) {
      _log("verifyOtp unexpected failure: $e");
      debugPrintStack(stackTrace: stack);
      throw Exception("Unable to verify OTP. Please try again.");
    }
    final user = credential.user ?? FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("Unable to verify OTP. Please try again.");
    }

    final firebaseToken = await user.getIdToken(true);
    if (firebaseToken == null || firebaseToken.trim().isEmpty) {
      throw Exception("Unable to create Firebase session. Please try again.");
    }

    final loginPayload = await _loginWithBackend(firebaseToken);
    final sanctumToken = _readToken(loginPayload);
    if (sanctumToken.isEmpty) {
      throw Exception("Login succeeded, but customer token was missing.");
    }

    final prefs = await SharedPreferences.getInstance();
    final mobile = _localIndianMobile(session.phoneNumber);
    await prefs.setString("customer_mobile", mobile);
    await prefs.setBool("customer_mobile_verified", true);
    await prefs.setString("customer_firebase_uid", user.uid);
    await prefs.setString("customer_firebase_token", firebaseToken);
    await prefs.setString("customer_sanctum_token", sanctumToken);
    _log("verifyOtp completed. uid=${user.uid}");
  }

  Future<String?> currentFirebaseToken() async {
    await _ensureFirebaseReady();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      if (token != null && token.trim().isNotEmpty) return token;
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("customer_firebase_token");
  }

  Future<void> _ensureFirebaseReady() async {
    if (!_firebaseReady) {
      _log("Firebase.initializeApp starting for web.");
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } on FirebaseException catch (e) {
        if (e.code != "duplicate-app") rethrow;
        _log("Firebase default app already exists.");
      }
      _firebaseReady = true;
    }
    final app = Firebase.app();
    _log(
      "Firebase ready. projectId=${app.options.projectId} authDomain=${app.options.authDomain}",
    );
    FirebaseAuth.instance.setLanguageCode("en");
  }

  void _ensureRecaptchaContainer() {
    final existing = html.document.getElementById(recaptchaContainerId);
    if (existing != null) {
      _log("reCAPTCHA container found in DOM.");
      return;
    }

    final element = html.DivElement()..id = recaptchaContainerId;
    html.document.body?.append(element);
    _log("reCAPTCHA container was missing; created fallback DOM node.");
  }

  RecaptchaVerifier _createRecaptchaVerifier() {
    html.document.getElementById(recaptchaContainerId)?.children.clear();
    return RecaptchaVerifier(
      auth: FirebaseAuthPlatform.instance,
      // No container makes FlutterFire use Firebase's invisible verifier.
      // There is no persistent widget on every screen; Google may still show
      // a one-time challenge only when the browser/session requires it.
      onSuccess: () => _log("reCAPTCHA solved."),
      onError: (error) {
        _logFirebaseException("recaptcha", error);
      },
      onExpired: () {
        _log("reCAPTCHA expired.");
        _hideRecaptchaBadge();
      },
    );
  }

  void _resetRecaptchaVerifier(RecaptchaVerifier verifier, String reason) {
    _log("resetting reCAPTCHA verifier. reason=$reason");
    try {
      verifier.clear();
    } catch (e) {
      _log("reCAPTCHA clear ignored: $e");
    }
    _ensureRecaptchaContainer();
    html.document.getElementById(recaptchaContainerId)?.children.clear();
    _hideRecaptchaBadge();
  }

  void _hideRecaptchaBadge() {
    final badge = html.document.querySelector(".grecaptcha-badge");
    if (badge != null) {
      badge
        ..setAttribute("aria-hidden", "true")
        ..style.visibility = "hidden"
        ..style.opacity = "0"
        ..style.pointerEvents = "none";
    }
  }

  bool _shouldResetRecaptcha(String code) {
    return code == "captcha-check-failed" ||
        code == "invalid-app-credential" ||
        code == "web-context-cancelled" ||
        code == "web-context-already-presented";
  }

  Future<void> _checkRateLimit(String mobileNumber) async {
    try {
      final res = await DioClient.getDio().post(
        "pwa/check-rate-limit",
        data: {"phone": _localIndianMobile(_toIndianE164(mobileNumber))},
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) return;
      throw Exception(_messageFromPayload(res.data, "Unable to send OTP."));
    } on DioException catch (e) {
      final message = _messageFromPayload(
        e.response?.data,
        "Unable to send OTP. Please try again.",
      );
      throw Exception(message);
    }
  }

  Future<dynamic> _loginWithBackend(String firebaseToken) async {
    try {
      final res = await DioClient.getDio().post(
        "pwa/login",
        data: {
          "firebase_token": firebaseToken,
          "device_fingerprint": _deviceFingerprint(),
        },
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) return res.data;
      throw Exception(_messageFromPayload(res.data, "Unable to login."));
    } on DioException catch (e) {
      final message = _messageFromPayload(
        e.response?.data,
        "Unable to login. Please try again.",
      );
      throw Exception(message);
    }
  }

  String _deviceFingerprint() {
    final host = Uri.base.host.trim();
    return host.isEmpty ? "flutter-web" : "flutter-web-$host";
  }

  String _readToken(dynamic payload) {
    if (payload is Map) {
      final data = payload["data"];
      for (final key in const [
        "token",
        "access_token",
        "sanctum_token",
        "plain_text_token",
      ]) {
        final value = payload[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      if (data is Map) return _readToken(data);
    }
    return "";
  }

  String _messageFromPayload(dynamic payload, String fallback) {
    if (payload is Map) {
      for (final key in const ["message", "error", "detail"]) {
        final value = payload[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      final errors = payload["errors"];
      if (errors is Map) {
        for (final value in errors.values) {
          if (value is List && value.isNotEmpty) {
            return value.first.toString();
          }
          if (value != null && value.toString().trim().isNotEmpty) {
            return value.toString().trim();
          }
        }
      }
    }
    return fallback;
  }

  String _firebaseAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case "invalid-verification-code":
        return "Incorrect OTP. Please check and try again.";
      case "too-many-requests":
        return "Too many OTP attempts. Please try again later.";
      case "invalid-phone-number":
        return "Enter a valid 10-digit mobile number.";
      case "captcha-check-failed":
        return "reCAPTCHA failed. Please refresh and try again.";
      case "invalid-app-credential":
        return "Firebase rejected the reCAPTCHA verifier. Add localhost, 127.0.0.1, and your CloudFront domain in Firebase Authorized domains, then refresh and try again.";
      case "operation-not-allowed":
        return "Phone sign-in is not enabled for this Firebase project.";
      case "unauthorized-domain":
        return "This website is not authorized for Firebase phone sign-in.";
      case "network-request-failed":
        return "Network error while contacting Firebase. Please try again.";
      case "web-context-cancelled":
      case "web-context-already-presented":
        return "reCAPTCHA was interrupted. Please refresh and try again.";
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : "Unable to verify OTP. Please try again.";
    }
  }

  String _toIndianE164(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith("+")) {
      final digits = trimmed.substring(1).replaceAll(RegExp(r'\D'), '');
      if (RegExp(r'^91[6-9]\d{9}$').hasMatch(digits)) {
        return "+$digits";
      }
    }

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      return "+91$digits";
    }
    if (RegExp(r'^91[6-9]\d{9}$').hasMatch(digits)) {
      return "+$digits";
    }

    throw Exception("Enter a valid 10-digit mobile number");
  }

  String _localIndianMobile(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith("91")) {
      return digits.substring(2);
    }
    return digits;
  }

  void _logFirebaseException(String stage, FirebaseAuthException error) {
    _log(
      "$stage FirebaseAuthException code=${error.code} "
      "message=${error.message ?? ""} plugin=${error.plugin}",
    );
  }

  void _log(String message) {
    final line = "[OTP][WEB] $message";
    debugPrint(line);
    html.window.console.debug(line);
  }
}
