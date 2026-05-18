import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class CustomerOtpSession {
  final String phoneNumber;
  final Object? confirmationResult;
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
  static const String dummyOtp = "123456";

  Future<CustomerOtpSession> sendOtp(String mobileNumber) async {
    final phoneNumber = _toIndianE164(mobileNumber);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return CustomerOtpSession(
      phoneNumber: phoneNumber,
      otpCode: dummyOtp,
    );
  }

  Future<void> verifyOtp({
    required CustomerOtpSession session,
    required String otp,
  }) async {
    final digits = otp.replaceAll(RegExp(r'\D'), '');
    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (digits != session.otpCode) {
      throw Exception("Incorrect OTP. Use ${session.otpCode} for demo login.");
    }

    final prefs = await SharedPreferences.getInstance();
    final mobile = _localIndianMobile(session.phoneNumber);
    await prefs.setString("customer_mobile", mobile);
    await prefs.setString("customer_firebase_uid", "dummy-customer-$mobile");
    await prefs.setString("customer_firebase_token", "dummy-token-$mobile");
  }

  Future<String?> currentFirebaseToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("customer_firebase_token");
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
}
