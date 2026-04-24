import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Duration _heartbeatCheckInterval = Duration(seconds: 15);
const Duration _heartbeatTimeout = Duration(seconds: 60);
const Duration _startupGracePeriod = Duration(seconds: 20);
const Duration _openAppCooldown = Duration(seconds: 45);
const Duration _initialBootOpenDelay = Duration(seconds: 12);
const Duration _manualExitDefaultCooldown = Duration(minutes: 10);
const bool _kioskAutoStartEnabled = false;

Future<void> initializeKioskBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: kioskBackgroundOnStart,
      autoStart: _kioskAutoStartEnabled,
      autoStartOnBoot: _kioskAutoStartEnabled,
      isForegroundMode: true,
      initialNotificationTitle: 'SELFX Kiosk',
      initialNotificationContent: 'Kiosk service running',
      foregroundServiceTypes: const [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
    ),
  );
  await service.startService();
}

void stopKioskBackgroundService() {
  FlutterBackgroundService().invoke("stopService");
}

void sendUiHeartbeat() {
  FlutterBackgroundService().invoke("ui_heartbeat", {
    "ts": DateTime.now().millisecondsSinceEpoch,
  });
}

void sendUiReady() {
  FlutterBackgroundService().invoke("ui_ready", {
    "ts": DateTime.now().millisecondsSinceEpoch,
  });
}

void reportUiCrash(Object error, StackTrace stack) {
  FlutterBackgroundService().invoke("ui_crash", {
    "error": error.toString(),
    "stack": stack.toString(),
    "ts": DateTime.now().millisecondsSinceEpoch,
  });
}

void sendUiManualExit({Duration cooldown = _manualExitDefaultCooldown}) {
  FlutterBackgroundService().invoke("manual_exit", {
    "ts": DateTime.now().millisecondsSinceEpoch,
    "cooldownMs": cooldown.inMilliseconds,
  });
}

@pragma('vm:entry-point')
void kioskBackgroundOnStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    await service.setForegroundNotificationInfo(
      title: 'SELFX Kiosk',
      content: 'Monitoring kiosk health',
    );
  }

  bool allowAutoOpen = false;
  Future<void> refreshAllowAutoOpen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restaurantId = prefs.getString("restaurant_id");
      final autoStartOnBoot = prefs.getBool("auto_start_on_boot") ?? false;
      allowAutoOpen =
          _kioskAutoStartEnabled &&
          autoStartOnBoot &&
          restaurantId != null &&
          restaurantId.trim().isNotEmpty;
    } catch (_) {
      allowAutoOpen = false;
    }
  }
  await refreshAllowAutoOpen();

  final int serviceStart = DateTime.now().millisecondsSinceEpoch;
  int lastHeartbeat = serviceStart;
  int lastOpenApp = 0;
  int suppressAutoOpenUntil = 0;
  bool uiReady = false;

  service.on("ui_heartbeat").listen((event) {
    final ts = event?["ts"];
    if (ts is int) {
      lastHeartbeat = ts;
    } else {
      lastHeartbeat = DateTime.now().millisecondsSinceEpoch;
    }
  });

  service.on("ui_ready").listen((event) {
    uiReady = true;
    suppressAutoOpenUntil = 0;
    final ts = event?["ts"];
    if (ts is int) {
      lastHeartbeat = ts;
    } else {
      lastHeartbeat = DateTime.now().millisecondsSinceEpoch;
    }
    refreshAllowAutoOpen();
  });

  service.on("ui_crash").listen((_) {
    lastHeartbeat = 0;
  });

  service.on("manual_exit").listen((event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dynamic rawCooldown = event?["cooldownMs"];
    final cooldownMs = rawCooldown is num
        ? rawCooldown.toInt()
        : _manualExitDefaultCooldown.inMilliseconds;
    suppressAutoOpenUntil = now + cooldownMs;
    lastHeartbeat = now;
    lastOpenApp = now;
  });

  Timer(_initialBootOpenDelay, () async {
    await refreshAllowAutoOpen();
    if (DateTime.now().millisecondsSinceEpoch < suppressAutoOpenUntil) return;
    if (!allowAutoOpen || uiReady) return;
    if (service is AndroidServiceInstance) {
      await service.openApp();
      final now = DateTime.now().millisecondsSinceEpoch;
      lastOpenApp = now;
      lastHeartbeat = now;
    }
  });

  Timer? watchdogTimer;
  watchdogTimer = Timer.periodic(_heartbeatCheckInterval, (_) async {
    if (service is AndroidServiceInstance) {
      final isForeground = await service.isForegroundService();
      if (!isForeground) {
        await service.setAsForegroundService();
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final gapMs = now - lastHeartbeat;
    final elapsed = now - serviceStart;
    final cooldownMs = now - lastOpenApp;
    final manualExitSuppressed = now < suppressAutoOpenUntil;
    final heartbeatExpired = gapMs >= _heartbeatTimeout.inMilliseconds;
    final startupGracePassed = elapsed >= _startupGracePeriod.inMilliseconds;
    final cooldownPassed = cooldownMs >= _openAppCooldown.inMilliseconds;

    if (allowAutoOpen &&
        !manualExitSuppressed &&
        heartbeatExpired &&
        cooldownPassed &&
        (uiReady || startupGracePassed)) {
      if (service is AndroidServiceInstance) {
        await service.openApp();
      }
      lastOpenApp = now;
      lastHeartbeat = now;
    }
  });

  service.on("stopService").listen((_) {
    watchdogTimer?.cancel();
    service.stopSelf();
  });
}
