import 'dart:async';

import 'package:api_selfxo_project/background_image/background_image.dart';
import 'package:api_selfxo_project/core/kiosk_bootstrap.dart';
import 'package:api_selfxo_project/printer/register_kiosk.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _navDelayTimer;
  bool _initStarted = false;
  bool _didNavigate = false;
  bool _skipVisualSplash = false;
  @override
  void initState() {
    super.initState();
    _skipVisualSplash = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  Future<void> _init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final restaurantId = prefs.getString("restaurant_id");
      final setupDone = prefs.getBool("kiosk_setup_done") ?? false;
      if (!mounted) return;

      if (_didNavigate) return;
      if (restaurantId == null || restaurantId.trim().isEmpty) {
        _didNavigate = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RegisterKioskScreen()),
        );
        return;
      }

      try {
        await DeviceBootstrap.ensureDeviceReady();
      } catch (e) {}

      if (_didNavigate) return;
      _didNavigate = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              setupDone ? const WelcomeScreen() : const RegisterKioskScreen(),
        ),
      );
    } catch (e) {}
  }

  Future<void> _delay(Duration duration) {
    final completer = Completer<void>();
    _navDelayTimer?.cancel();
    _navDelayTimer = Timer(duration, () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    _navDelayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_skipVisualSplash) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            "assets/spalsh.jpeg",
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      ),
    );
  }
}
