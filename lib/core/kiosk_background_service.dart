import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Duration _heartbeatCheckInterval = Duration(seconds: 15);
const Duration _heartbeatTimeout = Duration(seconds: 60);
const Duration _startupGracePeriod = Duration(minutes: 3);
const Duration _openAppCooldown = Duration(minutes: 3);

Future<void> initializeKioskBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: kioskBackgroundOnStart,
      autoStart: true,
      autoStartOnBoot: true,
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

@pragma('vm:entry-point')
void kioskBackgroundOnStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    await service.setForegroundNotificationInfo(
      title: 'SELFX Kiosk',
      content: 'Monitoring kiosk health',
    );
  }

  bool allowAutoOpen = true;
  Future<void> refreshAllowAutoOpen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restaurantId = prefs.getString("restaurant_id");
      allowAutoOpen = restaurantId != null && restaurantId.trim().isNotEmpty;
    } catch (_) {
      allowAutoOpen = true;
    }
  }
  await refreshAllowAutoOpen();

  final int serviceStart = DateTime.now().millisecondsSinceEpoch;
  int lastHeartbeat = serviceStart;
  int lastOpenApp = 0;
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
    final heartbeatExpired = gapMs >= _heartbeatTimeout.inMilliseconds;
    final startupGracePassed = elapsed >= _startupGracePeriod.inMilliseconds;
    final cooldownPassed = cooldownMs >= _openAppCooldown.inMilliseconds;

    if (allowAutoOpen &&
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
