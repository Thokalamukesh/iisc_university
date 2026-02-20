import 'package:api_selfxo_project/core/kiosk_log.dart';
// import 'package:api_selfxo_project/background_image/background_image.dart';
// import 'package:api_selfxo_project/screens/resturaunt_select_screen.dart';
// import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// import '../services/auth_service.dart';

// class AppInitScreen extends StatefulWidget {
//   const AppInitScreen({super.key});

//   @override
//   State<AppInitScreen> createState() => _AppInitScreenState();
// }

// class _AppInitScreenState extends State<AppInitScreen> {
//   @override
//   void initState() {
//     super.initState();
//     _init();
//   }

//   Future<void> _init() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final restaurantId = prefs.getString("restaurant_id");

//       // 🔴 No restaurant selected
//       if (restaurantId == null || restaurantId.isEmpty) {
//         if (!mounted) return;

//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(builder: (_) => const RestaurantSelectScreen()),
//         );
//         return;
//       }

//       // 🔐 Initialize kiosk
//       final ok = await AuthService().initializeKiosk();

//       if (!ok) {
//         _error();
//         return;
//       }

//       if (!mounted) return;

//       Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(builder: (_) => const WelcomeScreen()),
//       );
//     } catch (e) {
//       _error();
//     }
//   }

//   void _error() {
//     if (!mounted) return;

//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//         content: Text("Unable to initialize kiosk"),
//         backgroundColor: Colors.red,
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return const Scaffold(
//       backgroundColor: Colors.black,
//       body: Center(child: CircularProgressIndicator(color: Colors.white)),
//     );
//   }
// }
