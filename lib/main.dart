import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:api_selfxo_project/screens/splash_screen.dart';
import 'package:api_selfxo_project/background_image/background_image.dart';
import 'package:api_selfxo_project/core/connectivity_service.dart';
import 'package:api_selfxo_project/core/idle_timer.dart';
import 'package:api_selfxo_project/core/kiosk_background_service.dart';
import 'package:api_selfxo_project/core/kiosk_config.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';
import 'package:api_selfxo_project/core/kiosk_power.dart';
import 'package:api_selfxo_project/core/kiosk_watchdog.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeKioskBackgroundService();
    // Send an early heartbeat so the background watchdog doesn't relaunch
    // the app during cold start.
    sendUiHeartbeat();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      reportUiCrash(details.exception, details.stack ?? StackTrace.current);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      reportUiCrash(error, stack);
      return true;
    };
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    PaintingBinding.instance.imageCache.maximumSizeBytes = 120 << 20; // 120MB
    PaintingBinding.instance.imageCache.maximumSize = 300;
    WakelockPlus.enable();
    runApp(const MyApp());
  }, (error, stack) {
    reportUiCrash(error, stack);
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Timer? _idleTimer;
  late final VoidCallback _idleListener;
  Timer? _heartbeatTimer;
  Timer? _serviceHeartbeatTimer;
  bool _tickersEnabled = true;
  late final KioskWatchdog _watchdog;
  final FocusNode _appFocusNode = FocusNode(debugLabel: 'app-root');

  static const bool _enableHeartbeatLogs = false;

  static const Duration _idleTimeout = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetIdleTimer();
    _startServiceHeartbeat();

    ConnectivityService.instance.start();
    _idleListener = _handleIdleState;
    IdleTimer.enabled.addListener(_idleListener);

    _watchdog = KioskWatchdog(
      onFreezeDetected: _handleFreezeDetected,
      onJankDetected: (_) {},
    );
    _watchdog.start();

    KioskMemoryService.instance.start(
      cacheClearInterval: KioskConfig.memoryCacheClearInterval,
      maintenanceInterval: KioskConfig.maintenanceInterval,
      mediaRefreshInterval: KioskConfig.mediaRefreshInterval,
      activityCooldown: KioskConfig.activityCooldown,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      KioskPower.requestIgnoreBatteryOptimizations();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      sendUiReady();
    });

    _heartbeatTimer?.cancel();
    if (_enableHeartbeatLogs) {
      _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {});
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_appFocusNode.canRequestFocus) {
        _appFocusNode.requestFocus();
      }
    });
  }

  void _handleFreezeDetected(String reason) {
    _scheduleImageCacheClear();
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    ConnectivityService.instance.dispose();
    IdleTimer.enabled.removeListener(_idleListener);
    _idleTimer?.cancel();
    _heartbeatTimer?.cancel();
    _serviceHeartbeatTimer?.cancel();
    _watchdog.stop();
    KioskMemoryService.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    _appFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final content = TickerMode(
          enabled: _tickersEnabled,
          child: Focus(
            focusNode: _appFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              _resetIdleTimer();
              _watchdog.reportUserActivity();
              KioskMemoryService.instance.reportUserActivity();
              return KeyEventResult.ignored;
            },
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _resetIdleTimer();
                _watchdog.reportUserActivity();
                KioskMemoryService.instance.reportUserActivity();
                FocusManager.instance.primaryFocus?.unfocus();
              },
              onPointerMove: (_) {
                _resetIdleTimer();
                _watchdog.reportUserActivity();
                KioskMemoryService.instance.reportUserActivity();
                FocusManager.instance.primaryFocus?.unfocus();
              },
              onPointerSignal: (_) {
                _resetIdleTimer();
                _watchdog.reportUserActivity();
                KioskMemoryService.instance.reportUserActivity();
                FocusManager.instance.primaryFocus?.unfocus();
              },
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );

        return ValueListenableBuilder<bool>(
          valueListenable: ConnectivityService.instance.isOnline,
          builder: (context, online, _) {
            return Stack(
              children: [
                content,
                if (!online) _buildNoInternetOverlay(),
              ],
            );
          },
        );
      },
      home: const SplashScreen(),
    );
  }

  Widget _buildNoInternetOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                ),
              ),
            ),
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFFBFB), Color(0xFFFFEAEA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFFFC9C9)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFEBEE), Color(0xFFFFCDD2)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.redAccent,
                          size: 64,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE3E3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons
                                  .signal_wifi_statusbar_connected_no_internet_4,
                              size: 16,
                              color: Colors.redAccent,
                            ),
                            SizedBox(width: 6),
                            Text(
                              "Offline",
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        "No Internet Connection",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Trying to reconnect automatically",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: const LinearProgressIndicator(
                          minHeight: 6,
                          backgroundColor: Color(0xFFFFD7D7),
                          color: Color(0xFFB71C1C),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (!IdleTimer.enabled.value) {
      return;
    }
    _idleTimer = Timer(_idleTimeout, _handleIdleTimeout);
  }

  void _handleIdleTimeout() {
    if (!IdleTimer.enabled.value) return;
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    _scheduleImageCacheClear();
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
    _resetIdleTimer();
  }

  void _startServiceHeartbeat() {
    _serviceHeartbeatTimer?.cancel();
    sendUiHeartbeat();
    _serviceHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => sendUiHeartbeat(),
    );
  }

  void _scheduleImageCacheClear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  void _handleIdleState() {
    if (!IdleTimer.enabled.value) {
      _idleTimer?.cancel();
    } else {
      _resetIdleTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resetIdleTimer();
      _tickersEnabled = true;
      WakelockPlus.enable();
      _watchdog.start();
      KioskMemoryService.instance.resume();
      _startServiceHeartbeat();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _idleTimer?.cancel();
      _tickersEnabled = false;
      _watchdog.stop();
      KioskMemoryService.instance.pause();
      if (mounted) setState(() {});
    }
  }

  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
