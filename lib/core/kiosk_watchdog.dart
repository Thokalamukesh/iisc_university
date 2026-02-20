import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';

class KioskWatchdog {
  KioskWatchdog({
    required void Function(String reason) onFreezeDetected,
    required void Function(String message) onJankDetected,
    this.enableIsolateWatchdog = true,
    this.requireUserActivityForFreeze = true,
    this.activityWindow = const Duration(seconds: 180),
    this.stallThreshold = const Duration(seconds: 6),
    this.checkInterval = const Duration(seconds: 2),
    this.uiHeartbeatInterval = const Duration(seconds: 1),
    this.jankWindow = const Duration(seconds: 10),
    this.jankThresholdPercent = 0.2,
  }) : _onFreezeDetected = onFreezeDetected,
       _onJankDetected = onJankDetected;

  final void Function(String reason) _onFreezeDetected;
  final void Function(String message) _onJankDetected;
  final bool enableIsolateWatchdog;
  final bool requireUserActivityForFreeze;
  final Duration activityWindow;
  final Duration stallThreshold;
  final Duration checkInterval;
  final Duration uiHeartbeatInterval;
  final Duration jankWindow;
  final double jankThresholdPercent;

  DateTime _lastFrameTime = DateTime.now();
  DateTime _lastUiBeat = DateTime.now();
  DateTime _lastActivityTime = DateTime.now();
  DateTime _lastJankWindow = DateTime.now();
  int _totalFrames = 0;
  int _jankFrames = 0;
  Duration _worstFrame = Duration.zero;
  Timer? _timer;
  Timer? _uiBeatTimer;
  TimingsCallback? _timingsCallback;
  bool _running = false;
  bool _freezeReported = false;
  Isolate? _watchdogIsolate;
  SendPort? _watchdogSendPort;
  ReceivePort? _watchdogReceivePort;

  void start() {
    if (_running) return;
    _running = true;
    _lastFrameTime = DateTime.now();
    _lastUiBeat = DateTime.now();
    _lastActivityTime = DateTime.now();
    _lastJankWindow = DateTime.now();
    _totalFrames = 0;
    _jankFrames = 0;
    _worstFrame = Duration.zero;
    _freezeReported = false;

    _timingsCallback = _onFrameTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);

    _timer = Timer.periodic(checkInterval, _tick);
    _uiBeatTimer = Timer.periodic(uiHeartbeatInterval, (_) {
      _lastUiBeat = DateTime.now();
    });
    if (enableIsolateWatchdog) {
      _startIsolateWatchdog();
    }
  }

  void stop() {
    _running = false;
    if (_timingsCallback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_timingsCallback!);
      _timingsCallback = null;
    }
    _timer?.cancel();
    _timer = null;
    _uiBeatTimer?.cancel();
    _uiBeatTimer = null;
    _stopIsolateWatchdog();
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    _lastFrameTime = DateTime.now();
    for (final t in timings) {
      final total = t.totalSpan;
      _totalFrames++;
      if (total > const Duration(milliseconds: 32)) {
        _jankFrames++;
      }
      if (total > _worstFrame) _worstFrame = total;
    }
  }

  void _tick(Timer timer) {
    if (!_running) return;
    final now = DateTime.now();
    final gap = now.difference(_lastUiBeat);
    final recentlyActive = now.difference(_lastActivityTime) <= activityWindow;
    final shouldCheckFreeze = !requireUserActivityForFreeze || recentlyActive;
    if (shouldCheckFreeze && gap >= stallThreshold && !_freezeReported) {
      _freezeReported = true;
      _onFreezeDetected(
        "UI heartbeat stalled for ${gap.inMilliseconds}ms "
        "(threshold ${stallThreshold.inMilliseconds}ms)",
      );
    }

    _watchdogSendPort?.send(DateTime.now().millisecondsSinceEpoch);

    if (now.difference(_lastJankWindow) >= jankWindow) {
      if (_totalFrames > 0) {
        final jankPct = _jankFrames / _totalFrames;
        if (jankPct >= jankThresholdPercent) {
          _onJankDetected(
            "Jank ${(_jankFrames * 100 / _totalFrames).toStringAsFixed(1)}% "
            "over ${jankWindow.inSeconds}s (worst ${_worstFrame.inMilliseconds}ms)",
          );
        }
      }
      _lastJankWindow = now;
      _totalFrames = 0;
      _jankFrames = 0;
      _worstFrame = Duration.zero;
      if (gap < stallThreshold) {
        _freezeReported = false;
      }
    }
  }

  void reportUserActivity() {
    _lastActivityTime = DateTime.now();
  }

  Future<void> _startIsolateWatchdog() async {
    if (_watchdogIsolate != null) return;
    _watchdogReceivePort = ReceivePort();
    _watchdogIsolate = await Isolate.spawn(_watchdogEntry, {
      "sendPort": _watchdogReceivePort!.sendPort,
      "stallMs": stallThreshold.inMilliseconds,
    }, debugName: "kiosk_watchdog");
    _watchdogReceivePort!.listen((message) {
      if (message is SendPort) {
        _watchdogSendPort = message;
      }
    });
  }

  void _stopIsolateWatchdog() {
    _watchdogSendPort?.send(-1);
    _watchdogReceivePort?.close();
    _watchdogReceivePort = null;
    _watchdogSendPort = null;
    _watchdogIsolate?.kill(priority: Isolate.immediate);
    _watchdogIsolate = null;
  }

  static void _watchdogEntry(Map<String, dynamic> args) {
    final SendPort sendPort = args["sendPort"] as SendPort;
    final int stallMs = args["stallMs"] as int? ?? 6000;
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    int lastBeat = DateTime.now().millisecondsSinceEpoch;

    final stallTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final gap = now - lastBeat;
      if (gap >= stallMs) {
        // Use kioskLog here to ensure isolate output is visible.
        // This is a last-resort indicator when the UI isolate is stalled.
        // ignore: avoid_print
      }
    });

    receivePort.listen((message) {
      if (message is int) {
        if (message == -1) {
          stallTimer.cancel();
          receivePort.close();
          Isolate.exit();
        }
        lastBeat = message;
      }
    });
  }
}
