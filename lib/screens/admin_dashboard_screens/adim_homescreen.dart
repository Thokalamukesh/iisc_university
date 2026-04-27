import 'dart:async';
import 'package:api_selfxo_project/screens/admin_dashboard_screens/categorie_screen.dart';
import 'package:flutter/material.dart';
import 'package:api_selfxo_project/core/order_utils.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:api_selfxo_project/screens/admin_dashboard_screens/products_dashboard.dart';
import 'package:api_selfxo_project/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Import your category screen here
// import 'package:api_selfxo_project/screens/admin_dashboard_screens/categories_dashboard.dart';

import 'dashboard.dart';
import 'order_history.dart';
import 'settings.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int index = 0;
  int badgeCount = 0;
  int _reloadSeed = 0;

  bool _badgeLoading = false;

  @override
  void initState() {
    super.initState();
    _attemptTokenRecovery();
  }

  Future<void> _attemptTokenRecovery() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("auth_token")?.trim() ?? "";
      if (token.isNotEmpty) return;
      kioskLog('auth token missing on admin home; attempting recovery',
          tag: 'ADMIN_HOME');
      final ok = await AuthService().initializeKiosk(force: false);
      kioskLog('auth token recovery result=$ok', tag: 'ADMIN_HOME');
      if (!mounted || !ok) return;
      setState(() {
        _reloadSeed++;
      });
    } catch (e, stackTrace) {
      kioskLogError(
        'auth token recovery failed: $e',
        tag: 'ADMIN_HOME',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  List<Widget> _buildPages() {
    return [
      DashboardTab(key: ValueKey('dashboard-$_reloadSeed')),
      CategoriesScreen(key: ValueKey('categories-$_reloadSeed')),
      ProductsTab(
        key: ValueKey('products-$_reloadSeed'),
        onProductsUpdated: () {},
      ),
      OrdersHistoryTab(key: ValueKey('orders-$_reloadSeed')),
      SettingsScreen(key: ValueKey('settings-$_reloadSeed')),
    ];
  }

  Future<void> _refreshBadge() async {
    if (_badgeLoading) return;
    _badgeLoading = true;
    try {
      // This uses OrderUtils which we updated to map 'uuid' to 'transaction_id'
      final count = await OrderUtils.getPendingOrderCount();
      if (mounted) setState(() => badgeCount = count);
    } catch (e) {
    } finally {
      _badgeLoading = false;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 95,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: index,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF9F342C),
        unselectedItemColor: Colors.grey.shade500,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedFontSize: 13,
        unselectedFontSize: 12,
        selectedIconTheme: const IconThemeData(size: 26),
        unselectedIconTheme: const IconThemeData(size: 24),
        onTap: (i) => setState(() => index = i),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: "Dashboard",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.category_outlined),
            label: "Categories",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            label: "Products",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: "Orders",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: "Settings",
          ),
        ],
      ),
    );
  }
}
