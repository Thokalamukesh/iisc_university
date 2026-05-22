import 'dart:async';

import 'package:api_selfxo_project/services/pwa_auth_service.dart';
import 'package:api_selfxo_project/services/session_manager.dart';
import 'package:flutter/foundation.dart';

/// Web customer auth state used by GoRouter redirects.
///
/// On Flutter Web the browser owns back/forward history. The router guard below
/// keeps protected URLs available after refresh, and redirects old `/login`
/// history entries to `/home` once a customer or guest session exists.
class WebAuthService extends ChangeNotifier {
  WebAuthService._();

  static final WebAuthService instance = WebAuthService._();

  bool _initialized = false;
  bool _authenticated = false;

  bool get initialized => _initialized;
  bool get isAuthenticated => _authenticated;

  Future<void> initialize() async {
    final hasToken = await SessionManager.instance.hasSession();
    final isGuest = await SessionManager.instance.isGuestSession();

    _authenticated = hasToken || isGuest;
    _initialized = true;
    notifyListeners();

    // Keep first paint fast: a stored token is trusted for routing immediately,
    // then validated in the background. If the backend rejects it, GoRouter's
    // redirect sends the browser to `/login` without leaving duplicate pages.
    if (hasToken) {
      unawaited(_validateStoredToken());
    }
  }

  Future<void> markLoggedIn() async {
    _authenticated = true;
    _initialized = true;
    notifyListeners();
  }

  Future<void> continueAsGuest() async {
    await SessionManager.instance.continueAsGuest();
    await markLoggedIn();
  }

  Future<void> logout() async {
    await PwaAuthService.instance.logout();
    _authenticated = false;
    _initialized = true;
    notifyListeners();
  }

  Future<void> _validateStoredToken() async {
    final customer = await PwaAuthService.instance.restoreSession();
    if (customer != null) return;
    _authenticated = await SessionManager.instance.isGuestSession();
    notifyListeners();
  }
}
