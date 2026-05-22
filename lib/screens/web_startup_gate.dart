import 'package:api_selfxo_project/providers/restaurant_provider.dart';
import 'package:api_selfxo_project/screens/register_screen.dart';
import 'package:api_selfxo_project/screens/register_screen_io.dart';
import 'package:api_selfxo_project/screens/web_qr_menu_entry.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class WebStartupGate extends StatefulWidget {
  const WebStartupGate({super.key});

  @override
  State<WebStartupGate> createState() => _WebStartupGateState();
}

class _WebStartupGateState extends State<WebStartupGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RestaurantProvider>().initializeForWeb();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RestaurantProvider>(
      builder: (context, restaurantProvider, _) {
        if (!restaurantProvider.isInitialized ||
            restaurantProvider.isInitializing) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final launchRestaurantId = restaurantProvider.launchRestaurantId;
        if (launchRestaurantId != null &&
            launchRestaurantId.trim().isNotEmpty) {
          return WebQrMenuEntryScreen(
            restaurantId: launchRestaurantId,
            requestedOrderType: restaurantProvider.launchOrderType,
          );
        }

        return const UserIdScreen();
      },
    );
  }
}
