import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _init();
  }

  Future<void> _init() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _setOnlineImmediate(results.any((r) => r != ConnectivityResult.none));
    } catch (_) {
      _setOnlineImmediate(true);
    }

    _subscription?.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      _setOnlineImmediate(results.any((r) => r != ConnectivityResult.none));
    });
  }

  void markOffline() {
    _setOnlineImmediate(false);
  }

  void _setOnlineImmediate(bool online) {
    if (isOnline.value != online) {
      isOnline.value = online;
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
