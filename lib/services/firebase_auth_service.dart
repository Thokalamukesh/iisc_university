import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:api_selfxo_project/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Holds the result of a Firebase OTP send.
class FirebaseOtpSession {
  final String phoneNumber;
  final ConfirmationResult? confirmationResult;

  const FirebaseOtpSession({
    required this.phoneNumber,
    this.confirmationResult,
  });
}

/// Singleton Firebase auth service.
///
/// Responsibilities:
/// - Initialize Firebase ONLY ONCE
/// - Send OTP via `verifyPhoneNumber()` (web: invisible reCAPTCHA)
/// - Verify OTP and return Firebase ID token
/// - Prevent duplicate OTP sends, captcha loops, multiple `initializeApp()`
///
/// This service does NOT talk to Laravel. It only handles Firebase.
class FirebaseAuthService {
  FirebaseAuthService._();

  static final FirebaseAuthService instance = FirebaseAuthService._();

  static const String _recaptchaContainerId = 'recaptcha-container';
  static const Duration _firebaseTimeout = Duration(seconds: 90);

  bool _firebaseReady = false;
  bool _otpInFlight = false;

  // ── Public API ────────────────────────────────────────────────

  /// Sends OTP to the given mobile number.
  ///
  /// [mobileNumber] — raw 10-digit Indian mobile (e.g. "9876543210").
  /// Returns a [FirebaseOtpSession] containing the [ConfirmationResult].
  Future<FirebaseOtpSession> sendOtp(String mobileNumber) async {
    if (_otpInFlight) {
      throw Exception('OTP request already in progress. Please wait.');
    }
    _otpInFlight = true;

    try {
      _log(
          'sendOtp started. raw_length=${mobileNumber.length} host=${Uri.base.host}');
      await _ensureFirebaseReady();
      _ensureRecaptchaContainer();

      final phoneNumber = _toIndianE164(mobileNumber);
      _log('calling FirebaseAuth.signInWithPhoneNumber for $phoneNumber');

      final verifier = _createRecaptchaVerifier();
      late ConfirmationResult confirmationResult;

      try {
        confirmationResult = await FirebaseAuth.instance
            .signInWithPhoneNumber(phoneNumber, verifier)
            .timeout(_firebaseTimeout);
        _log('Firebase OTP SMS request accepted.');
        _resetRecaptchaVerifier(verifier, 'OTP SMS request accepted');
      } on FirebaseAuthException catch (e) {
        _logFirebaseException('sendOtp', e);
        if (_shouldResetRecaptcha(e.code)) {
          _resetRecaptchaVerifier(verifier, 'FirebaseAuthException ${e.code}');
        }
        throw Exception(_firebaseAuthMessage(e));
      } on TimeoutException {
        _resetRecaptchaVerifier(verifier, 'sendOtp timeout');
        throw Exception(
          'OTP request timed out. Please complete the reCAPTCHA prompt and try again.',
        );
      } catch (e, stack) {
        _log('sendOtp unexpected failure: $e');
        debugPrintStack(stackTrace: stack);
        _resetRecaptchaVerifier(verifier, 'unexpected sendOtp failure');
        throw Exception('Unable to send OTP. Please refresh and try again.');
      }

      return FirebaseOtpSession(
        phoneNumber: phoneNumber,
        confirmationResult: confirmationResult,
      );
    } finally {
      _otpInFlight = false;
    }
  }

  /// Verifies OTP and returns the Firebase ID token string.
  ///
  /// After this succeeds the caller should send the ID token to the Laravel
  /// backend via `PwaAuthService.login()`.
  Future<String> verifyOtp({
    required FirebaseOtpSession session,
    required String otp,
  }) async {
    _log('verifyOtp started. otp_length=${otp.length}');
    await _ensureFirebaseReady();

    final digits = otp.replaceAll(RegExp(r'\D'), '');
    final confirmationResult = session.confirmationResult;
    if (confirmationResult == null) {
      throw Exception('OTP session expired. Please request OTP again.');
    }

    late UserCredential credential;
    try {
      credential = await confirmationResult.confirm(digits).timeout(
            _firebaseTimeout,
          );
      _log(
          'Firebase OTP confirm completed. user_present=${credential.user != null}');
    } on FirebaseAuthException catch (e) {
      _logFirebaseException('verifyOtp', e);
      throw Exception(_firebaseAuthMessage(e));
    } on TimeoutException {
      throw Exception('OTP verification timed out. Please try again.');
    } catch (e, stack) {
      _log('verifyOtp unexpected failure: $e');
      debugPrintStack(stackTrace: stack);
      throw Exception('Unable to verify OTP. Please try again.');
    }

    final user = credential.user ?? FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Unable to verify OTP. Please try again.');
    }

    final firebaseToken = await user.getIdToken(true);
    if (firebaseToken == null || firebaseToken.trim().isEmpty) {
      throw Exception('Unable to create Firebase session. Please try again.');
    }

    _log('verifyOtp completed. uid=${user.uid}');
    return firebaseToken;
  }

  /// Returns the current Firebase user's UID (if signed in).
  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  // ── Firebase Init (singleton) ─────────────────────────────────

  Future<void> _ensureFirebaseReady() async {
    if (!_firebaseReady) {
      _log('Firebase.initializeApp starting for web.');
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } on FirebaseException catch (e) {
        if (e.code != 'duplicate-app') rethrow;
        _log('Firebase default app already exists.');
      }
      _firebaseReady = true;
    }
    final app = Firebase.app();
    _log(
      'Firebase ready. projectId=${app.options.projectId} authDomain=${app.options.authDomain}',
    );
    FirebaseAuth.instance.setLanguageCode('en');
  }

  // ── reCAPTCHA Management ──────────────────────────────────────

  void _ensureRecaptchaContainer() {
    final existing = html.document.getElementById(_recaptchaContainerId);
    if (existing != null) {
      _log('reCAPTCHA container found in DOM.');
      return;
    }
    final element = html.DivElement()..id = _recaptchaContainerId;
    html.document.body?.append(element);
    _log('reCAPTCHA container was missing; created fallback DOM node.');
  }

  RecaptchaVerifier _createRecaptchaVerifier() {
    html.document.getElementById(_recaptchaContainerId)?.children.clear();
    return RecaptchaVerifier(
      auth: FirebaseAuthPlatform.instance,
      onSuccess: () => _log('reCAPTCHA solved.'),
      onError: (error) => _logFirebaseException('recaptcha', error),
      onExpired: () {
        _log('reCAPTCHA expired.');
        _hideRecaptchaBadge();
      },
    );
  }

  void _resetRecaptchaVerifier(RecaptchaVerifier verifier, String reason) {
    _log('resetting reCAPTCHA verifier. reason=$reason');
    try {
      verifier.clear();
    } catch (e) {
      _log('reCAPTCHA clear ignored: $e');
    }
    _ensureRecaptchaContainer();
    html.document.getElementById(_recaptchaContainerId)?.children.clear();
    _hideRecaptchaBadge();
  }

  void _hideRecaptchaBadge() {
    final badge = html.document.querySelector('.grecaptcha-badge');
    if (badge != null) {
      badge
        ..setAttribute('aria-hidden', 'true')
        ..style.visibility = 'hidden'
        ..style.opacity = '0'
        ..style.pointerEvents = 'none';
    }
  }

  bool _shouldResetRecaptcha(String code) {
    return code == 'captcha-check-failed' ||
        code == 'invalid-app-credential' ||
        code == 'web-context-cancelled' ||
        code == 'web-context-already-presented';
  }

  // ── Helpers ───────────────────────────────────────────────────

  String _toIndianE164(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+')) {
      final digits = trimmed.substring(1).replaceAll(RegExp(r'\D'), '');
      if (RegExp(r'^91[6-9]\d{9}$').hasMatch(digits)) {
        return '+$digits';
      }
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      return '+91$digits';
    }
    if (RegExp(r'^91[6-9]\d{9}$').hasMatch(digits)) {
      return '+$digits';
    }
    throw Exception('Enter a valid 10-digit mobile number');
  }

  String _firebaseAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-verification-code':
        return 'Incorrect OTP. Please check and try again.';
      case 'too-many-requests':
        return 'Too many OTP attempts. Please try again later.';
      case 'invalid-phone-number':
        return 'Enter a valid 10-digit mobile number.';
      case 'captcha-check-failed':
        return 'reCAPTCHA failed. Please refresh and try again.';
      case 'invalid-app-credential':
        return 'Firebase rejected the reCAPTCHA verifier. Ensure gitam.sirixo.com is in Firebase Authorized domains and you are accessing the app via https://gitam.sirixo.com/.';
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled for this Firebase project.';
      case 'unauthorized-domain':
        return 'This website is not authorized for Firebase phone sign-in.';
      case 'network-request-failed':
        return 'Network error while contacting Firebase. Please try again.';
      case 'web-context-cancelled':
      case 'web-context-already-presented':
        return 'reCAPTCHA was interrupted. Please refresh and try again.';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Unable to verify OTP. Please try again.';
    }
  }

  void _logFirebaseException(String stage, FirebaseAuthException error) {
    _log(
      '$stage FirebaseAuthException code=${error.code} '
      'message=${error.message ?? ""} plugin=${error.plugin}',
    );
  }

  void _log(String message) {
    final line = '[FIREBASE_AUTH] $message';
    debugPrint(line);
    html.window.console.debug(line);
  }
}
