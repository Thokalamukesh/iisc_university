import 'package:api_selfxo_project/api/dio_client.dart';
import 'package:api_selfxo_project/services/session_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Service for communicating with the Laravel PWA auth APIs.
///
/// Endpoints consumed:
/// - POST /api/pwa/login              — Exchange Firebase ID token for Sanctum token
/// - GET  /api/pwa/restore-session    — Validate existing Sanctum token
/// - POST /api/pwa/logout             — Revoke current Sanctum token
/// - GET  /api/pwa/profile            — Fetch customer profile
/// - GET  /api/pwa/customer/orders    — Fetch order history
/// - POST /api/pwa/check-rate-limit   — Pre-flight OTP rate limit check
///
/// Uses [SessionManager] for all token/customer persistence.
class PwaAuthService {
  PwaAuthService._();

  static final PwaAuthService instance = PwaAuthService._();

  final SessionManager _session = SessionManager.instance;

  // ── Login ─────────────────────────────────────────────────────

  /// Exchanges a Firebase ID token for a Sanctum token.
  ///
  /// On success, persists the Sanctum token + customer data via [SessionManager].
  /// Returns the customer map from the response.
  Future<Map<String, dynamic>> login({
    required String firebaseIdToken,
    required String firebaseUid,
    String customerName = '',
  }) async {
    _log('login() called');
    final dio = DioClient.getDio();

    try {
      final body = <String, dynamic>{
        'firebase_token': firebaseIdToken,
        'device_fingerprint': _deviceFingerprint(),
      };
      // Only send name if the user actually typed one
      if (customerName.trim().isNotEmpty) {
        body['name'] = customerName.trim();
      }

      final res = await dio.post('pwa/login', data: body);
      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        throw Exception(_messageFromPayload(res.data, 'Unable to login.'));
      }

      final payload = res.data;
      final sanctumToken = _readToken(payload);
      if (sanctumToken.isEmpty) {
        throw Exception('Login succeeded, but customer token was missing.');
      }

      final customer = _readCustomer(payload);

      await _session.persistLogin(
        sanctumToken: sanctumToken,
        customer: customer,
        firebaseUid: firebaseUid,
        firebaseIdToken: firebaseIdToken,
      );

      _log('login() completed. customer_id=${customer['id']}');
      return customer;
    } on DioException catch (e) {
      final message = _messageFromPayload(
        e.response?.data,
        'Unable to login. Please try again.',
      );
      throw Exception(message);
    }
  }

  // ── Session Restore ───────────────────────────────────────────

  /// Validates the stored Sanctum token against the backend.
  ///
  /// Returns the customer map if valid, `null` if the session is expired/invalid.
  /// Does NOT throw — callers should treat `null` as "needs fresh login".
  Future<Map<String, dynamic>?> restoreSession() async {
    final token = await _session.getSanctumToken();
    if (token == null) {
      _log('restoreSession() — no stored token');
      return null;
    }

    try {
      final dio = DioClient.getDio();
      final res = await dio.get(
        'pwa/restore-session',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final statusCode = res.statusCode ?? 0;
      if (statusCode == 401 || statusCode == 403) {
        _log('restoreSession() — token rejected ($statusCode)');
        await _session.clearSession();
        return null;
      }

      if (statusCode < 200 || statusCode >= 300) {
        _log('restoreSession() — unexpected status $statusCode');
        return null;
      }

      final payload = res.data;
      final success = payload is Map ? payload['success'] : null;
      if (success == false) {
        await _session.clearSession();
        return null;
      }

      final customer = _readCustomer(payload);
      await _session.setCustomer(customer);
      _log('restoreSession() — session restored. customer_id=${customer['id']}');
      return customer;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        await _session.clearSession();
      }
      _log('restoreSession() — DioException status=$status');
      return null;
    } catch (e) {
      _log('restoreSession() — error: $e');
      return null;
    }
  }

  // ── Logout ────────────────────────────────────────────────────

  /// Revokes the Sanctum token on the backend and clears local storage.
  Future<void> logout() async {
    final token = await _session.getSanctumToken();
    if (token != null && token.isNotEmpty) {
      try {
        await DioClient.getDio().post(
          'pwa/logout',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        _log('logout() — server token revoked');
      } catch (e) {
        _log('logout() — server revoke failed (ignored): $e');
      }
    }
    await _session.clearSession();
    _log('logout() — local session cleared');
  }

  // ── Rate Limit Check ──────────────────────────────────────────

  /// Pre-flight rate limit check before Firebase sends OTP.
  /// Throws if rate limited.
  Future<void> checkRateLimit(String mobileNumber) async {
    try {
      final res = await DioClient.getDio().post(
        'pwa/check-rate-limit',
        data: {'phone': _toLocal10Digits(mobileNumber)},
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) return;
      throw Exception(_messageFromPayload(res.data, 'Unable to send OTP.'));
    } on DioException catch (e) {
      final message = _messageFromPayload(
        e.response?.data,
        'Unable to send OTP. Please try again.',
      );
      throw Exception(message);
    }
  }

  // ── Authed Dio helper (for other screens) ─────────────────────

  /// Returns a Dio instance with the Sanctum `Authorization` header set.
  /// Throws if no token is stored.
  Future<Dio> getAuthedDio() async {
    final token = await _session.getSanctumToken();
    if (token == null) {
      throw Exception('Not authenticated. Please sign in.');
    }
    final dio = DioClient.getDio();
    dio.options.headers['Authorization'] = 'Bearer $token';
    return dio;
  }

  // ── Private Helpers ───────────────────────────────────────────

  String _deviceFingerprint() {
    final host = Uri.base.host.trim();
    return host.isEmpty ? 'flutter-web' : 'flutter-web-$host';
  }

  String _readToken(dynamic payload) {
    if (payload is Map) {
      final data = payload['data'];
      for (final key in const [
        'token',
        'access_token',
        'sanctum_token',
        'plain_text_token',
      ]) {
        final value = payload[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      if (data is Map) return _readToken(data);
    }
    return '';
  }

  Map<String, dynamic> _readCustomer(dynamic payload) {
    if (payload is Map) {
      final data = payload['data'];
      if (data is Map && data.containsKey('customer')) {
        final customer = data['customer'];
        if (customer is Map) {
          return customer.map((k, v) => MapEntry('$k', v));
        }
      }
      if (payload.containsKey('customer')) {
        final customer = payload['customer'];
        if (customer is Map) {
          return customer.map((k, v) => MapEntry('$k', v));
        }
      }
    }
    return const {};
  }

  String _messageFromPayload(dynamic payload, String fallback) {
    if (payload is Map) {
      for (final key in const ['message', 'error', 'detail']) {
        final value = payload[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      final errors = payload['errors'];
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

  void _log(String message) {
    debugPrint('[PWA_AUTH] $message');
  }
}
