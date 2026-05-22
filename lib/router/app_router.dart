import 'package:api_selfxo_project/router/auth_service.dart';
import 'package:api_selfxo_project/screens/block_screen.dart';
import 'package:api_selfxo_project/screens/home_screen.dart';
import 'package:api_selfxo_project/screens/login_screen.dart';
import 'package:api_selfxo_project/screens/profile_screen.dart';
import 'package:api_selfxo_project/screens/settings_screen.dart';
import 'package:api_selfxo_project/screens/web_qr_menu_entry.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppRouter {
  static GoRouter createRouter({
    required WebAuthService authService,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    return GoRouter(
      navigatorKey: navigatorKey,
      refreshListenable: authService,
      // Keep this false so context.go() writes a clean browser history entry;
      // Chrome back/forward can then restore `/home`, `/orders`, `/profile`,
      // and deep-linked restaurant URLs normally.
      routerNeglect: false,
      debugLogDiagnostics: false,
      redirect: (context, state) {
        final uri = state.uri;
        final path = uri.path.isEmpty ? '/' : uri.path;
        final isLogin = path == '/login';
        final isSplash = path == '/loading';
        final forceLogin = uri.queryParameters['force'] == '1';
        final qrTarget = _restaurantLaunchFromUri(uri);

        if (path == '/' && qrTarget.restaurantId != null) {
          final orderType = qrTarget.orderType;
          final query = orderType == null
              ? ''
              : '?orderType=${Uri.encodeQueryComponent(orderType)}';
          return '/restaurant/${Uri.encodeComponent(qrTarget.restaurantId!)}$query';
        }

        // Do not redirect to `/loading` while auth is starting. A loading
        // redirect becomes a real browser history entry on web, which makes
        // Chrome Back/Forward feel broken. Let the requested URL stay in place,
        // then apply auth redirects once SharedPreferences/session restore is
        // ready.
        if (!authService.initialized) return null;

        if (path == '/') {
          return authService.isAuthenticated ? '/home' : '/login';
        }

        final publicMenuLink = _isRestaurantPath(path);
        if (!authService.isAuthenticated && !isLogin && !publicMenuLink) {
          return '/login';
        }

        // If Chrome back lands on an old `/login` entry after login, this
        // replaces it with `/home`; it prevents duplicate login pages in
        // browser history while keeping normal back/forward behavior elsewhere.
        if (authService.isAuthenticated && isLogin && !forceLogin) {
          return '/home';
        }

        if (authService.isAuthenticated && isSplash) {
          return '/home';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/loading',
          builder: (_, __) => const _RouterLoadingScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => FoodOtpLoginScreen(
            onLoginComplete: authService.markLoggedIn,
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/orders',
          builder: (_, __) => const CustomerBlockScreen(initialTab: 1),
        ),
        GoRoute(
          path: '/offers',
          builder: (_, __) => const CustomerBlockScreen(initialTab: 2),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, __) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/restaurant/:restaurantId',
          builder: (_, state) => WebQrMenuEntryScreen(
            restaurantId: state.pathParameters['restaurantId'] ?? '',
            requestedOrderType: state.uri.queryParameters['orderType'] ??
                state.uri.queryParameters['order_type'],
          ),
        ),
        GoRoute(
          path: '/menu/:restaurantId',
          builder: (_, state) => WebQrMenuEntryScreen(
            restaurantId: state.pathParameters['restaurantId'] ?? '',
            requestedOrderType: state.uri.queryParameters['orderType'] ??
                state.uri.queryParameters['order_type'],
          ),
        ),
        GoRoute(
          path: '/kiosk/:restaurantId',
          builder: (_, state) => WebQrMenuEntryScreen(
            restaurantId: state.pathParameters['restaurantId'] ?? '',
            requestedOrderType: state.uri.queryParameters['orderType'] ??
                state.uri.queryParameters['order_type'],
          ),
        ),
        GoRoute(
          path: '/restaurants-home/:restaurantId',
          builder: (_, state) => WebQrMenuEntryScreen(
            restaurantId: state.pathParameters['restaurantId'] ?? '',
            requestedOrderType: state.uri.queryParameters['orderType'] ??
                state.uri.queryParameters['order_type'],
          ),
        ),
      ],
    );
  }

  static bool _isRestaurantPath(String path) {
    return path.startsWith('/restaurant/') ||
        path.startsWith('/menu/') ||
        path.startsWith('/kiosk/') ||
        path.startsWith('/restaurants-home/');
  }

  static ({String? restaurantId, String? orderType}) _restaurantLaunchFromUri(
    Uri uri,
  ) {
    String? firstNonEmpty(Map<String, String> params, List<String> keys) {
      for (final key in keys) {
        final value = params[key]?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    String? fromPath(List<String> rawSegments) {
      final segments = rawSegments
          .map((segment) => segment.trim())
          .where((segment) => segment.isNotEmpty)
          .toList();
      for (var i = 0; i < segments.length - 1; i++) {
        final current = segments[i].toLowerCase();
        if (current == 'restaurant' ||
            current == 'restaurants' ||
            current == 'restaurants-home' ||
            current == 'menu' ||
            current == 'kiosk') {
          return segments[i + 1];
        }
      }
      return null;
    }

    const restaurantKeys = [
      'restaurant_id',
      'restaurantId',
      'rid',
      'restaurant',
      'slug',
    ];
    const orderTypeKeys = ['order_type', 'orderType', 'type'];

    var restaurantId = firstNonEmpty(uri.queryParameters, restaurantKeys);
    var orderType = firstNonEmpty(uri.queryParameters, orderTypeKeys);
    restaurantId ??= fromPath(uri.pathSegments);

    final fragment = uri.fragment.trim();
    if (fragment.isNotEmpty) {
      final fragmentUri = Uri.tryParse(
        fragment.startsWith('/') ? fragment : '/$fragment',
      );
      if (fragmentUri != null) {
        restaurantId ??=
            firstNonEmpty(fragmentUri.queryParameters, restaurantKeys);
        orderType ??= firstNonEmpty(fragmentUri.queryParameters, orderTypeKeys);
        restaurantId ??= fromPath(fragmentUri.pathSegments);
      }
    }

    return (restaurantId: restaurantId, orderType: orderType);
  }
}

class _RouterLoadingScreen extends StatelessWidget {
  const _RouterLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF6F6F7),
      body: Center(
        child: SizedBox(
          width: 42,
          height: 42,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Color(0xFFD32F2F),
          ),
        ),
      ),
    );
  }
}
