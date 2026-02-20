import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/register_screen.dart'; // UserIdScreen

Future<void> logoutAndChangeRestaurant(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();

  // 🔥 CLEAR ONLY CONTEXTUAL DATA (DO NOT TOUCH DEVICE ID)
  await prefs.remove("auth_token");
  await prefs.remove("admin_token");
  await prefs.remove("restaurant_id");
  await prefs.remove("branch_id");
  await prefs.remove("home_banner_url");

  // 🧹 Optional: clear anything restaurant-scoped
  // await prefs.remove("last_order_id");

  // ✅ HARD RESET NAVIGATION
  if (!context.mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const UserIdScreen()),
    (route) => false,
  );
}
