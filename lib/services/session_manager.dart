import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized session storage for the PWA customer auth flow.
///
/// Stores:
/// - `sanctum_token`   — Laravel Sanctum bearer token
/// - `customer_json`   — Serialized customer profile from the login/restore response
/// - `customer_mobile` — Local 10-digit mobile number
/// - `last_restaurant` — Last restaurant the customer ordered from
/// - `login_timestamp` — ISO-8601 timestamp of the most recent login
///
/// All keys are prefixed to avoid collision with kiosk keys.
class SessionManager {
  SessionManager._();

  static final SessionManager instance = SessionManager._();

  // ── Key constants ─────────────────────────────────────────────
  static const String _keySanctumToken = 'customer_sanctum_token';
  static const String _keyCustomerJson = 'customer_json';
  static const String _keyCustomerMobile = 'customer_mobile';
  static const String _keyMobileVerified = 'customer_mobile_verified';
  static const String _keyFirebaseUid = 'customer_firebase_uid';
  static const String _keyFirebaseToken = 'customer_firebase_token';
  static const String _keyLastRestaurant = 'last_restaurant';
  static const String _keyLoginTimestamp = 'login_timestamp';

  // ── Token ─────────────────────────────────────────────────────

  Future<String?> getSanctumToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keySanctumToken)?.trim();
    return (token != null && token.isNotEmpty) ? token : null;
  }

  Future<void> setSanctumToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySanctumToken, token.trim());
  }

  /// Whether the user has a stored Sanctum token (quick sync check).
  Future<bool> hasSession() async {
    final token = await getSanctumToken();
    return token != null;
  }

  // ── Customer Profile ──────────────────────────────────────────

  Future<Map<String, dynamic>?> getCustomer() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCustomerJson);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setCustomer(Map<String, dynamic> customer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomerJson, jsonEncode(customer));

    // Also sync the mobile & verified flags for backwards compat.
    final phone = customer['phone']?.toString().trim() ?? '';
    if (phone.isNotEmpty) {
      final localMobile = _toLocal10Digits(phone);
      await prefs.setString(_keyCustomerMobile, localMobile);
      await prefs.setBool(_keyMobileVerified, true);
    }
  }

  Future<String?> getCustomerMobile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCustomerMobile)?.trim();
  }

  // ── Firebase (write-once during login) ────────────────────────

  Future<void> setFirebaseCredentials({
    required String uid,
    required String idToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFirebaseUid, uid);
    await prefs.setString(_keyFirebaseToken, idToken);
  }

  // ── Last Restaurant ───────────────────────────────────────────

  Future<void> setLastRestaurant(String restaurantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastRestaurant, restaurantId.trim());
  }

  Future<String?> getLastRestaurant() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastRestaurant)?.trim();
  }

  // ── Login Timestamp ───────────────────────────────────────────

  Future<void> setLoginTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLoginTimestamp, DateTime.now().toIso8601String());
  }

  // ── Full Login Persist (called after /login success) ──────────

  Future<void> persistLogin({
    required String sanctumToken,
    required Map<String, dynamic> customer,
    required String firebaseUid,
    required String firebaseIdToken,
  }) async {
    await setSanctumToken(sanctumToken);
    await setCustomer(customer);
    await setFirebaseCredentials(uid: firebaseUid, idToken: firebaseIdToken);
    await setLoginTimestamp();
    debugPrint('[SESSION] Login persisted for phone=${customer['phone']}');
  }

  // ── Logout / Clear ────────────────────────────────────────────

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySanctumToken);
    await prefs.remove(_keyCustomerJson);
    await prefs.remove(_keyCustomerMobile);
    await prefs.remove(_keyMobileVerified);
    await prefs.remove(_keyFirebaseUid);
    await prefs.remove(_keyFirebaseToken);
    await prefs.remove(_keyLoginTimestamp);
    debugPrint('[SESSION] Session cleared.');
  }

  // ── Helpers ───────────────────────────────────────────────────

  /// Extracts local 10-digit mobile from full phone string (e.g. "919876543210" → "9876543210").
  String _toLocal10Digits(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }
}
