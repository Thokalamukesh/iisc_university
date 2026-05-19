import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/api/web_api_config.dart';
import 'package:api_selfxo_project/core/kiosk_bootstrap.dart';
import 'package:api_selfxo_project/firebase_options.dart';
import 'package:api_selfxo_project/printer/register_kiosk.dart';
import 'package:api_selfxo_project/screens/admin_dashboard_screens/adim_homescreen.dart';
import 'package:api_selfxo_project/screens/block_screen.dart';
import 'package:api_selfxo_project/screens/login_screen.dart';
import 'package:api_selfxo_project/screens/payment_success.dart';
import 'package:api_selfxo_project/services/pwa_auth_service.dart';
import 'package:api_selfxo_project/services/session_manager.dart';
import 'package:api_selfxo_project/widget/pos_payment_success_dialog.dart';
import 'package:api_selfxo_project/core/connectivity_service.dart';
import 'package:api_selfxo_project/core/idle_timer.dart';
import 'package:api_selfxo_project/core/kiosk_background_service.dart';
import 'package:api_selfxo_project/core/kiosk_config.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';
import 'package:api_selfxo_project/core/kiosk_power.dart';
import 'package:api_selfxo_project/core/kiosk_watchdog.dart';
import 'package:api_selfxo_project/providers/restaurant_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final AppRouteObserver appRouteObserver = AppRouteObserver();

class AppRouteObserver extends NavigatorObserver {
  final ValueNotifier<String> currentRouteHint =
      ValueNotifier<String>('unknown');

  void _updateCurrent(Route<dynamic>? route) {
    if (route == null) {
      currentRouteHint.value = 'unknown';
      return;
    }
    final routeName = route.settings.name?.trim();
    if (routeName != null && routeName.isNotEmpty) {
      currentRouteHint.value = routeName;
      return;
    }
    currentRouteHint.value = '${route.settings}|${route.toString()}';
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateCurrent(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _updateCurrent(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateCurrent(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateCurrent(previousRoute);
  }
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (kIsWeb) {
      debugPrint("[FIREBASE] Initializing web Firebase app.");
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } on FirebaseException catch (e) {
        if (e.code != "duplicate-app") rethrow;
        debugPrint("[FIREBASE] Web Firebase app already initialized.");
      }
      debugPrint(
        "[FIREBASE] Initialized project=${Firebase.app().options.projectId} "
        "authDomain=${Firebase.app().options.authDomain}",
      );
    }
    if (!kIsWeb) {
      await initializeKioskBackgroundService();
    }
    // Send an early heartbeat so the background watchdog doesn't relaunch
    // the app during cold start.
    sendUiHeartbeat();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      reportUiCrash(details.exception, details.stack ?? StackTrace.current);
    };
    ErrorWidget.builder = (details) {
      debugPrint("[FLUTTER][FATAL_WIDGET] ${details.exceptionAsString()}");
      return Material(
        color: const Color(0xFFF6F6F7),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFF9F342C),
                      size: 34,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Unable to open this screen",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF151518),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Please refresh and try again.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      reportUiCrash(error, stack);
      return true;
    };
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    PaintingBinding.instance.imageCache.maximumSizeBytes = 120 << 20; // 120MB
    PaintingBinding.instance.imageCache.maximumSize = 300;
    if (kIsWeb) {
      runApp(
        ChangeNotifierProvider(
          create: (_) => RestaurantProvider(),
          child: const WebCustomerApp(),
        ),
      );
      return;
    }
    if (!kIsWeb) {
      WakelockPlus.enable();
    }
    final prefs = await SharedPreferences.getInstance();
    final restaurantId = prefs.getString("restaurant_id");
    final setupDone = prefs.getBool("kiosk_setup_done") ?? false;
    if (restaurantId != null && restaurantId.trim().isNotEmpty) {
      try {
        await DeviceBootstrap.ensureDeviceReady();
      } catch (_) {}
    }

    final Widget initialHome = kIsWeb
        ? _resolveInitialWebHome()
        : (setupDone ? const AdminHomeScreen() : const RegisterKioskScreen());

    runApp(
      ChangeNotifierProvider(
        create: (_) => RestaurantProvider(),
        child: MyApp(initialHome: initialHome),
      ),
    );
  }, (error, stack) {
    reportUiCrash(error, stack);
  });
}

Widget _resolveInitialWebHome() {
  return const _WebSessionGate();
}

class WebCustomerApp extends StatefulWidget {
  const WebCustomerApp({super.key});

  @override
  State<WebCustomerApp> createState() => _WebCustomerAppState();
}

class _WebCustomerAppState extends State<WebCustomerApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      sendUiReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorObservers: [appRouteObserver],
      debugShowCheckedModeBanner: false,
      home: _resolveInitialWebHome(),
    );
  }
}

/// Session gate for web/PWA.
///
/// On startup:
/// 1. Checks SharedPreferences for a stored Sanctum token.
/// 2. If found, calls GET /restore-session to validate.
/// 3. If valid → navigates to CustomerBlockScreen (dashboard).
/// 4. If invalid or missing → shows FoodOtpLoginScreen.
///
/// Target: session restore under 1 second.
class _WebSessionGate extends StatefulWidget {
  const _WebSessionGate();

  @override
  State<_WebSessionGate> createState() => _WebSessionGateState();
}

class _WebSessionGateState extends State<_WebSessionGate> {
  bool _checking = true;
  bool _sessionValid = false;

  @override
  void initState() {
    super.initState();
    _tryRestoreSession();
  }

  Future<void> _tryRestoreSession() async {
    final timer = Stopwatch()..start();
    try {
      final hasToken = await SessionManager.instance.hasSession();
      if (!hasToken) {
        debugPrint('[SESSION_GATE] No stored token → login screen');
        if (mounted) setState(() { _checking = false; _sessionValid = false; });
        return;
      }

      debugPrint('[SESSION_GATE] Token found → validating with backend...');
      final customer = await PwaAuthService.instance.restoreSession();
      timer.stop();
      debugPrint('[SESSION_GATE] restoreSession completed in ${timer.elapsedMilliseconds}ms');

      if (customer != null) {
        debugPrint('[SESSION_GATE] Session valid → dashboard');
        if (mounted) setState(() { _checking = false; _sessionValid = true; });
      } else {
        debugPrint('[SESSION_GATE] Session invalid → login screen');
        if (mounted) setState(() { _checking = false; _sessionValid = false; });
      }
    } catch (e) {
      debugPrint('[SESSION_GATE] Error during restore: $e');
      if (mounted) setState(() { _checking = false; _sessionValid = false; });
    }
  }



  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFFF6F6F7),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF9F342C),
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Loading...',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_sessionValid) {
      return const CustomerBlockScreen();
    }

    return const FoodOtpLoginScreen();
  }
}

class MyApp extends StatefulWidget {
  final Widget initialHome;

  const MyApp({super.key, required this.initialHome});

  @override
  State<MyApp> createState() => _MyAppState();
}

enum _GlobalScanPaymentState {
  paid,
  unpaid,
  unverifiedServerError,
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Timer? _idleTimer;
  late final VoidCallback _idleListener;
  Timer? _heartbeatTimer;
  Timer? _serviceHeartbeatTimer;
  bool _tickersEnabled = true;
  bool _isExitingFromRemoteBack = false;
  KioskWatchdog? _watchdog;
  final FocusNode _appFocusNode = FocusNode(debugLabel: 'app-root');
  final StringBuffer _globalScanBuffer = StringBuffer();
  Timer? _globalScanIdleTimer;
  late final KeyEventCallback _globalHardwareKeyHandler;
  bool _globalScanBusy = false;
  String _lastGlobalScan = '';
  DateTime _lastGlobalScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<_GlobalScanTask> _globalScanQueue = <_GlobalScanTask>[];
  final Set<int> _globalQueuedOrderIds = <int>{};

  static const bool _enableHeartbeatLogs = false;

  static const Duration _idleTimeout = Duration(minutes: 3);
  static const Duration _globalScanDebounceWindow = Duration(
    milliseconds: 1200,
  );
  static const Duration _globalScanIdleFlushDelay = Duration(
    milliseconds: 480,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetIdleTimer();

    ConnectivityService.instance.start();
    _idleListener = _handleIdleState;
    IdleTimer.enabled.addListener(_idleListener);

    if (!kIsWeb) {
      _startServiceHeartbeat();
      _watchdog = KioskWatchdog(
        onFreezeDetected: _handleFreezeDetected,
        onJankDetected: (_) {},
      )..start();
    }
    _globalHardwareKeyHandler = _handleGlobalHardwareKeyEvent;
    if (!kIsWeb) {
      HardwareKeyboard.instance.addHandler(_globalHardwareKeyHandler);
    }

    if (!kIsWeb) {
      KioskMemoryService.instance.start(
        cacheClearInterval: KioskConfig.memoryCacheClearInterval,
        maintenanceInterval: KioskConfig.maintenanceInterval,
        mediaRefreshInterval: KioskConfig.mediaRefreshInterval,
        activityCooldown: KioskConfig.activityCooldown,
      );
    }

    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        KioskPower.requestIgnoreBatteryOptimizations();
      });
    }

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
      MaterialPageRoute(builder: (_) => _buildRootFallbackHome()),
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
    _globalScanIdleTimer?.cancel();
    if (!kIsWeb) {
      HardwareKeyboard.instance.removeHandler(_globalHardwareKeyHandler);
      KioskMemoryService.instance.stop();
    }
    _watchdog?.stop();
    WidgetsBinding.instance.removeObserver(this);
    _appFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorObservers: [appRouteObserver],
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final content = TickerMode(
          enabled: _tickersEnabled,
          child: Focus(
            focusNode: _appFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              _resetIdleTimer();
              _watchdog?.reportUserActivity();
              if (!kIsWeb) {
                KioskMemoryService.instance.reportUserActivity();
              }
              if (_isRemoteBackKey(event)) {
                unawaited(_handleSystemBackPress());
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _resetIdleTimer();
                _watchdog?.reportUserActivity();
                if (!kIsWeb) {
                  KioskMemoryService.instance.reportUserActivity();
                }
                FocusManager.instance.primaryFocus?.unfocus();
              },
              onPointerMove: (_) {
                _resetIdleTimer();
                _watchdog?.reportUserActivity();
                if (!kIsWeb) {
                  KioskMemoryService.instance.reportUserActivity();
                }
                FocusManager.instance.primaryFocus?.unfocus();
              },
              onPointerSignal: (_) {
                _resetIdleTimer();
                _watchdog?.reportUserActivity();
                if (!kIsWeb) {
                  KioskMemoryService.instance.reportUserActivity();
                }
                FocusManager.instance.primaryFocus?.unfocus();
              },
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );

        return ValueListenableBuilder<bool>(
          valueListenable: ConnectivityService.instance.isOnline,
          builder: (context, online, _) {
            return PopScope(
              canPop: false,
              onPopInvoked: (didPop) {
                if (didPop) return;
                _handleSystemBackPress();
              },
              child: Stack(
                children: [
                  content,
                  if (!online) _buildNoInternetOverlay(),
                ],
              ),
            );
          },
        );
      },
      home: widget.initialHome,
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
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
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

  void _handleIdleTimeout() async {
    if (!IdleTimer.enabled.value) return;
    if (await _shouldSkipIdleRedirectBySetupState()) {
      _resetIdleTimer();
      return;
    }
    if (_isIdleRedirectBlockedForCurrentRoute()) {
      _resetIdleTimer();
      return;
    }
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    _scheduleImageCacheClear();
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _buildRootFallbackHome()),
      (_) => false,
    );
    _resetIdleTimer();
  }

  Widget _buildRootFallbackHome() {
    if (kIsWeb) {
      return _resolveInitialWebHome();
    }
    return const AdminHomeScreen();
  }

  Future<bool> _shouldSkipIdleRedirectBySetupState() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    final setupDone = prefs.getBool('kiosk_setup_done') ?? false;
    final restaurantId = prefs.getString('restaurant_id')?.trim() ?? '';
    if (!setupDone || restaurantId.isEmpty) {
      return true;
    }
    return false;
  }

  bool _isIdleRedirectBlockedForCurrentRoute() {
    final routeHint = appRouteObserver.currentRouteHint.value.toLowerCase();
    if (routeHint.trim().isEmpty || routeHint == 'unknown') {
      return false;
    }
    const blockedHints = <String>[
      'registerkioskscreen',
      'register_screen',
      'registerscreen',
      'userid',
      'userscreen',
      'appinit',
      'setup',
      'paymentscreen',
      'payment_screen',
      'pickupqrscreen',
      'pickup_qr',
      'pickup',
    ];
    for (final blocked in blockedHints) {
      if (routeHint.contains(blocked)) return true;
    }
    return false;
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

  Future<void> _handleSystemBackPress() async {
    _resetIdleTimer();
    _watchdog?.reportUserActivity();
    if (!kIsWeb) {
      KioskMemoryService.instance.reportUserActivity();
    }

    final nav = rootNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (_isExitingFromRemoteBack) return;
      _isExitingFromRemoteBack = true;
      sendUiManualExit(cooldown: const Duration(minutes: 10));
      stopKioskBackgroundService();
      try {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await SystemNavigator.pop();
      } finally {
        _isExitingFromRemoteBack = false;
      }
    }
  }

  bool _isRemoteBackKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }
    final key = event.logicalKey;
    return key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack;
  }

  bool _handleGlobalHardwareKeyEvent(KeyEvent event) {
    if (kIsWeb) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return false;
    }

    _resetIdleTimer();
    _watchdog?.reportUserActivity();
    KioskMemoryService.instance.reportUserActivity();

    if (_isRemoteBackKey(event)) {
      unawaited(_handleSystemBackPress());
      return true;
    }

    if (_shouldSuppressGlobalScanForCurrentRoute()) {
      return false;
    }

    _handleGlobalPaymentScanKey(event);
    return false;
  }

  bool _shouldSuppressGlobalScanForCurrentRoute() {
    final routeHint = appRouteObserver.currentRouteHint.value.toLowerCase();
    if (routeHint.trim().isEmpty || routeHint == 'unknown') return false;
    const blockedHints = <String>[
      'pickupqrscreen',
      'pickup_qr',
      'webscantoprint',
      'scan_to_print',
      'payment_screen_web',
      'paymentscreenweb',
    ];
    for (final blocked in blockedHints) {
      if (routeHint.contains(blocked)) return true;
    }
    return false;
  }

  bool _handleGlobalPaymentScanKey(KeyEvent event) {
    if (kIsWeb) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _flushGlobalScanBuffer(trigger: 'enter');
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_globalScanBuffer.isNotEmpty) {
        final cur = _globalScanBuffer.toString();
        _globalScanBuffer
          ..clear()
          ..write(cur.substring(0, cur.length - 1));
      }
      _scheduleGlobalScanIdleFlush();
      return true;
    }

    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        !_isControlCharacter(character)) {
      _globalScanBuffer.write(character);
      _scheduleGlobalScanIdleFlush();
      return true;
    }

    return false;
  }

  bool _isControlCharacter(String value) {
    final code = value.codeUnitAt(0);
    return code < 32 || code == 127;
  }

  void _scheduleGlobalScanIdleFlush() {
    _globalScanIdleTimer?.cancel();
    _globalScanIdleTimer = Timer(_globalScanIdleFlushDelay, () {
      _flushGlobalScanBuffer(trigger: 'idle');
    });
  }

  void _flushGlobalScanBuffer({required String trigger}) {
    _globalScanIdleTimer?.cancel();
    final captured = _globalScanBuffer.toString();
    _globalScanBuffer.clear();

    final value = _sanitizeScan(captured);
    if (value.isEmpty) return;

    final orderId = _extractOrderIdFromPaymentQr(value);
    if (orderId == null) return;

    final now = DateTime.now();
    if (_lastGlobalScan == value &&
        now.difference(_lastGlobalScanAt) < _globalScanDebounceWindow) {
      return;
    }
    _lastGlobalScan = value;
    _lastGlobalScanAt = now;

    _enqueueGlobalPaymentScan(
      orderId: orderId,
      source: trigger,
      rawValue: value,
    );
  }

  void _enqueueGlobalPaymentScan({
    required int orderId,
    required String source,
    required String rawValue,
  }) {
    if (_globalQueuedOrderIds.contains(orderId)) {
      _showGlobalScanSnack(
        'Order #$orderId already in print queue.',
        background: Colors.blueGrey.shade700,
        duration: const Duration(milliseconds: 900),
      );
      return;
    }

    _globalQueuedOrderIds.add(orderId);
    _globalScanQueue.add(
      _GlobalScanTask(orderId: orderId, source: source, rawValue: rawValue),
    );

    if (_globalScanQueue.length > 1 || _globalScanBusy) {
      _showGlobalScanSnack(
        'Order #$orderId added to queue.',
        background: Colors.blueGrey.shade700,
        duration: const Duration(milliseconds: 900),
      );
    }

    unawaited(_drainGlobalScanQueue());
  }

  Future<void> _drainGlobalScanQueue() async {
    if (_globalScanBusy) return;
    _globalScanBusy = true;
    try {
      while (_globalScanQueue.isNotEmpty) {
        final task = _globalScanQueue.removeAt(0);
        _globalQueuedOrderIds.remove(task.orderId);
        await _processGlobalPaymentScan(
          orderId: task.orderId,
          source: task.source,
          rawValue: task.rawValue,
        );
      }
    } finally {
      _globalScanBusy = false;
    }
  }

  String _sanitizeScan(String raw) {
    return raw
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  int? _extractOrderIdFromPaymentQr(String value) {
    final normalized = value.toUpperCase();
    final match = RegExp(r'PRINT[_\-:]?ORDER[_\-:]?(\d{1,12})').firstMatch(
      normalized,
    );
    final id = int.tryParse(match?.group(1) ?? '');
    if (id == null || id <= 0) return null;
    return id;
  }

  Future<void> _processGlobalPaymentScan({
    required int orderId,
    required String source,
    required String rawValue,
  }) async {
    _showGlobalScanSnack(
      'Checking payment for order #$orderId...',
      background: Colors.blueGrey.shade700,
      duration: const Duration(milliseconds: 900),
    );
    try {
      final paymentState = await _resolveGlobalScanPaymentState(
        orderId,
      ).timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () => _GlobalScanPaymentState.unverifiedServerError,
      );
      if (paymentState == _GlobalScanPaymentState.unpaid) {
        _showGlobalScanSnack(
          'Order #$orderId is not paid yet.',
          background: Colors.orange.shade800,
        );
        return;
      }

      if (paymentState == _GlobalScanPaymentState.unverifiedServerError) {
        _showGlobalScanSnack(
          'Payment API issue (500). Printing by scanned QR...',
          background: Colors.orange.shade700,
          duration: const Duration(milliseconds: 1200),
        );
      }

      if (!mounted) return;
      unawaited(_showScanAcceptedPopup(orderId));

      await _withGlobalKioskRecovery(
        () => PaymentSuccessDialog.printReceiptUsingTabletFlow(
          cart: const [],
          orderNumber: orderId,
        ),
      );

      _showGlobalScanSnack(
        'Order #$orderId printed successfully.',
        background: Colors.green.shade700,
      );
    } catch (e) {
      _showGlobalScanSnack(
        'Print failed for order #$orderId ($source): ${_friendlyDioError(e)}',
        background: Colors.red.shade700,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _showScanAcceptedPopup(int orderId) async {
    final popupContext = rootNavigatorKey.currentContext;
    if (popupContext == null) return;
    PosPaymentSuccessData data = _buildFallbackScanPopupData(orderId);
    try {
      data = await _buildScanPopupData(orderId).timeout(
        const Duration(milliseconds: 900),
        onTimeout: () => _buildFallbackScanPopupData(orderId),
      );
    } catch (_) {}
    if (!mounted) return;
    final activeContext = rootNavigatorKey.currentContext;
    if (activeContext == null) return;
    // ignore: use_build_context_synchronously
    unawaited(
      showPosPaymentSuccessDialog(
        activeContext,
        autoClose: const Duration(seconds: 2),
        data: data,
      ),
    );
  }

  PosPaymentSuccessData _buildFallbackScanPopupData(int orderId) {
    return PosPaymentSuccessData(
      orderId: orderId.toString(),
      amountPaid: '-',
      amountLabel: 'Bill Amount',
      paymentMethod: 'QR Scan',
      dateTimeText: DateTime.now()
          .toLocal()
          .toIso8601String()
          .replaceFirst('T', ' ')
          .split('.')
          .first,
      orderedItems: const [],
      title: 'Payment Received',
      subtitle: 'Receipt Printing',
    );
  }

  Future<PosPaymentSuccessData> _buildScanPopupData(int orderId) async {
    dynamic payload;
    try {
      final orderRes = await _withGlobalKioskRecovery(
        () => KioskApi().getOrderDetails(orderId),
      );
      payload = orderRes.data;
    } catch (_) {
      return _buildFallbackScanPopupData(orderId);
    }

    final orderedItems = _extractPopupOrderedItems(payload);
    final amountValue = _findNumByKeys(payload, const [
      'total',
      'grand_total',
      'total_amount',
      'amount',
      'paid_amount',
      'payable_amount',
      'final_total',
    ]);
    final amountText = amountValue == null
        ? '-'
        : (amountValue % 1 == 0
            ? 'Rs ${amountValue.toStringAsFixed(0)}'
            : 'Rs ${amountValue.toStringAsFixed(2)}');
    final paymentMethod = _findTextByKeys(payload, const [
          'payment_mode',
          'paymentMethod',
          'payment_method',
          'paymentMode',
          'method',
          'mode',
          'gateway',
        ]) ??
        'QR Scan';

    return PosPaymentSuccessData(
      orderId: orderId.toString(),
      amountPaid: amountText,
      amountLabel: 'Bill Amount',
      paymentMethod: paymentMethod,
      dateTimeText: DateTime.now()
          .toLocal()
          .toIso8601String()
          .replaceFirst('T', ' ')
          .split('.')
          .first,
      orderedItems: orderedItems,
      title: 'Payment Received',
      subtitle: 'Receipt Printing',
    );
  }

  List<String> _extractPopupOrderedItems(dynamic payload) {
    final rawItems = _findLikelyOrderItemsList(payload);
    if (rawItems.isEmpty) return const [];
    final lines = <String>[];
    for (final item in rawItems) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final nested = map['item'] is Map
          ? Map<String, dynamic>.from(map['item'] as Map)
          : map['menu_item'] is Map
              ? Map<String, dynamic>.from(map['menu_item'] as Map)
              : const <String, dynamic>{};
      final name = (map['name'] ??
              map['item_name'] ??
              map['menu_item_name'] ??
              nested['name'] ??
              nested['item_name'] ??
              '')
          .toString()
          .trim();
      if (name.isEmpty) continue;
      final qty = _asNumSafe(
            map['qty'] ?? map['quantity'] ?? map['count'] ?? map['qty_ordered'],
          ) ??
          _asNumSafe(
              map['pivot'] is Map ? (map['pivot'] as Map)['quantity'] : 0) ??
          1;
      final price = _asNumSafe(
            map['price'] ??
                map['unit_price'] ??
                map['amount'] ??
                map['total'] ??
                nested['price'],
          ) ??
          0;
      final qtyText = qty % 1 == 0 ? qty.toStringAsFixed(0) : qty.toString();
      final lineTotal = qty * price;
      final lineAmount = lineTotal % 1 == 0
          ? lineTotal.toStringAsFixed(0)
          : lineTotal.toStringAsFixed(2);
      lines.add('$qtyText x $name (Rs $lineAmount)');
      if (lines.length >= 6) break;
    }
    return lines;
  }

  List<dynamic> _findLikelyOrderItemsList(dynamic value, {int depth = 5}) {
    if (value == null || depth <= 0) return const [];
    if (value is Map) {
      for (final key in const [
        'order_items',
        'items',
        'orderItems',
        'order_item_list',
        'orderDetails',
      ]) {
        final candidate = value[key];
        if (candidate is List && _looksLikeOrderItemsList(candidate)) {
          return candidate;
        }
      }
      final nestedOrder = value['order'];
      if (nestedOrder is Map) {
        final nested = _findLikelyOrderItemsList(nestedOrder, depth: depth - 1);
        if (nested.isNotEmpty) return nested;
      }
      final nestedData = value['data'];
      if (nestedData != null) {
        final nested = _findLikelyOrderItemsList(nestedData, depth: depth - 1);
        if (nested.isNotEmpty) return nested;
      }
      for (final entry in value.entries) {
        final nested = _findLikelyOrderItemsList(entry.value, depth: depth - 1);
        if (nested.isNotEmpty) return nested;
      }
    } else if (value is List) {
      if (_looksLikeOrderItemsList(value)) return value;
      for (final item in value) {
        final nested = _findLikelyOrderItemsList(item, depth: depth - 1);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const [];
  }

  bool _looksLikeOrderItemsList(List<dynamic> list) {
    if (list.isEmpty) return false;
    final first = list.first;
    if (first is! Map) return false;
    final keys = first.keys.map((key) => key.toString()).toSet();
    return keys.contains('name') ||
        keys.contains('item_name') ||
        keys.contains('menu_item_name') ||
        keys.contains('qty') ||
        keys.contains('quantity') ||
        keys.contains('price') ||
        keys.contains('amount');
  }

  String? _findTextByKeys(dynamic value, List<String> keys, {int depth = 5}) {
    if (value == null || depth <= 0) return null;
    if (value is Map) {
      for (final key in keys) {
        if (value.containsKey(key)) {
          final raw = value[key];
          if (raw != null) {
            final text = raw.toString().trim();
            if (text.isNotEmpty) return text;
          }
        }
      }
      for (final entry in value.entries) {
        final nested = _findTextByKeys(entry.value, keys, depth: depth - 1);
        if (nested != null && nested.isNotEmpty) return nested;
      }
    } else if (value is List) {
      for (final item in value) {
        final nested = _findTextByKeys(item, keys, depth: depth - 1);
        if (nested != null && nested.isNotEmpty) return nested;
      }
    }
    return null;
  }

  num? _findNumByKeys(dynamic value, List<String> keys, {int depth = 5}) {
    if (value == null || depth <= 0) return null;
    if (value is Map) {
      for (final key in keys) {
        if (value.containsKey(key)) {
          final parsed = _asNumSafe(value[key]);
          if (parsed != null) return parsed;
        }
      }
      for (final entry in value.entries) {
        final nested = _findNumByKeys(entry.value, keys, depth: depth - 1);
        if (nested != null) return nested;
      }
    } else if (value is List) {
      for (final item in value) {
        final nested = _findNumByKeys(item, keys, depth: depth - 1);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  num? _asNumSafe(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }

  Future<T> _withGlobalKioskRecovery<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      final message = e.toString().toLowerCase();
      final needsRecovery = message.contains('kiosk token missing') ||
          message.contains('auth_token') ||
          message.contains('restaurant_not_configured') ||
          message.contains('restaurant not configured') ||
          message.contains('unauthorized');
      if (!needsRecovery) rethrow;
      await DeviceBootstrap.ensureDeviceReady();
      return action();
    }
  }

  bool _looksLikeServerErrorText(String message) {
    final m = message.toLowerCase();
    return m.contains('500') ||
        m.contains('server error') ||
        m.contains('internal server error');
  }

  Future<_GlobalScanPaymentState> _resolveGlobalScanPaymentState(
    int orderId,
  ) async {
    try {
      final paymentRes = await _withGlobalKioskRecovery(
        () => KioskApi().checkPayment(orderId),
      );
      if (_containsPaidState(paymentRes.data, 5)) {
        return _GlobalScanPaymentState.paid;
      }
      return _GlobalScanPaymentState.unpaid;
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code == 404 || code == 400) return _GlobalScanPaymentState.unpaid;
      return _GlobalScanPaymentState.unverifiedServerError;
    } catch (e) {
      if (_looksLikeServerErrorText(e.toString())) {
        return _GlobalScanPaymentState.unverifiedServerError;
      }
      return _GlobalScanPaymentState.unverifiedServerError;
    }
  }

  String _friendlyDioError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final path = e.requestOptions.path;
      final base = e.requestOptions.baseUrl;
      if (status != null) {
        return 'HTTP $status ($base$path)';
      }
      return '$base$path: ${e.message ?? e.type.name}';
    }
    return e.toString();
  }

  bool _containsPaidState(dynamic value, int depth) {
    if (value == null || depth <= 0) return false;
    if (value is Map) {
      for (final key in const [
        'status',
        'payment_status',
        'paymentStatus',
        'order_status',
        'orderStatus',
        'state',
        'payment_state',
        'paymentState',
        'paid',
        'is_paid',
        'isPaid',
        'success',
        'is_success',
        'isSuccess',
        'result',
        'message',
      ]) {
        if (value.containsKey(key) && _isPaidStatus(value[key])) {
          return true;
        }
      }
      for (final nestedKey in const [
        'data',
        'order',
        'payment',
        'response',
        'result',
        'payload',
      ]) {
        if (value.containsKey(nestedKey) &&
            _containsPaidState(value[nestedKey], depth - 1)) {
          return true;
        }
      }
      for (final entry in value.entries) {
        if (_containsPaidState(entry.value, depth - 1)) return true;
      }
    } else if (value is List) {
      for (final item in value) {
        if (_containsPaidState(item, depth - 1)) return true;
      }
    } else if (_isPaidStatus(value)) {
      return true;
    }
    return false;
  }

  bool _isPaidStatus(dynamic status) {
    if (status == true) return true;
    if (status is num) return status == 1;
    final s = status?.toString().trim().toLowerCase() ?? '';
    if (s.isEmpty) return false;
    if (s.contains('cancel') ||
        s.contains('refund') ||
        s.contains('failed') ||
        s.contains('void') ||
        s.contains('unpaid') ||
        s.contains('pending')) {
      return false;
    }
    return s.contains('paid') ||
        s.contains('completed') ||
        s.contains('success') ||
        s.contains('successful') ||
        s.contains('captured') ||
        s.contains('authorized');
  }

  void _showGlobalScanSnack(
    String message, {
    required Color background,
    Duration duration = const Duration(seconds: 1),
  }) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: background,
        duration: duration,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.resumed) {
      _resetIdleTimer();
      _tickersEnabled = true;
      WakelockPlus.enable();
      _watchdog?.start();
      KioskMemoryService.instance.resume();
      _startServiceHeartbeat();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _idleTimer?.cancel();
      _tickersEnabled = false;
      _watchdog?.stop();
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

class _GlobalScanTask {
  final int orderId;
  final String source;
  final String rawValue;

  const _GlobalScanTask({
    required this.orderId,
    required this.source,
    required this.rawValue,
  });
}
