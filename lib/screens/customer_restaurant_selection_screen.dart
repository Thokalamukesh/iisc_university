import 'package:flutter/material.dart';

import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/core/fast_page_route.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:api_selfxo_project/screens/block_screen.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_account_screen.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_offers_screen.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_orders_screen.dart';
import 'package:api_selfxo_project/screens/web_qr_menu_entry.dart';
import 'package:api_selfxo_project/services/restaurant_api_service.dart';

class CustomerRestaurantSelectionScreen extends StatefulWidget {
  const CustomerRestaurantSelectionScreen({super.key});

  @override
  State<CustomerRestaurantSelectionScreen> createState() =>
      _CustomerRestaurantSelectionScreenState();
}

class _CustomerRestaurantSelectionScreenState
    extends State<CustomerRestaurantSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _restaurants = [];
  bool _loading = true;
  String? _errorMessage;
  String? _openingRestaurantKey;
  int _selectedBottomIndex = 0;

  final Color primaryRed = const Color(0xFFD32F2F);
  final Color scaffoldBg = const Color(0xFFF9F9F9);
  static const Color _snackGreen = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
  }

  Future<void> _loadRestaurants() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final data = await KioskApi().getAllRestaurantsWeb();
      if (!mounted) return;

      setState(() {
        _restaurants
          ..clear()
          ..addAll(data);
        _loading = false;
      });
    } catch (e, s) {
      kioskLogError(
        "load failed: $e",
        tag: "CUSTOMER_FLOW",
        error: e,
        stackTrace: s,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorMessage = _restaurantLoadErrorMessage(e);
      });
    }
  }

  String _restaurantLoadErrorMessage(Object error) {
    if (error is RestaurantApiException) {
      return error.message;
    }
    return "Unable to load restaurants. Please try again.";
  }

  String _readRestaurantString(
      Map<String, dynamic> restaurant, List<String> keys) {
    for (final key in keys) {
      final value = restaurant[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return "";
  }

  String _restaurantRouteKey(Map<String, dynamic> restaurant) {
    final id = _readRestaurantString(
      restaurant,
      const ["id", "restaurant_id", "restaurantId"],
    );
    if (id.isNotEmpty) return id;

    return _readRestaurantString(
      restaurant,
      const ["hash", "slug", "restaurant_hash"],
    );
  }

  String _restaurantSubtitle(Map<String, dynamic> restaurant) {
    final branchName =
        _readRestaurantString(restaurant, const ["branch_name", "branchName"]);
    final address = _readRestaurantString(restaurant, const ["address"]);
    final city = _readRestaurantString(restaurant, const ["city"]);
    final cuisine = _readRestaurantString(restaurant, const ["cuisine"]);

    if (branchName.isNotEmpty && city.isNotEmpty) {
      return "$branchName • $city";
    }
    if (branchName.isNotEmpty) return branchName;
    if (address.isNotEmpty) return address.replaceAll("\n", " ");
    if (cuisine.isNotEmpty) return cuisine;

    return "Multi Cuisine";
  }

  void _openRestaurantMenu(Map<String, dynamic> restaurant) {
    if (_openingRestaurantKey != null) return;

    final routeKey = _restaurantRouteKey(restaurant);
    if (routeKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Unable to open this restaurant"),
          backgroundColor: _snackGreen,
        ),
      );
      return;
    }

    setState(() => _openingRestaurantKey = routeKey);

    Navigator.of(context).pushReplacement(
      fastPageRoute(
        (_) => WebQrMenuEntryScreen(
          restaurantId: routeKey,
          initialRestaurant: restaurant,
        ),
      ),
    );
  }

  // Unified approach for both hardware and software back events
  void _openBlockSelection() {
    Navigator.of(context).pushReplacement(
      fastPageRoute(
        (_) => const CustomerBlockScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // Change 'onPopInvokedWithResult' to 'onPopInvoked' for compatibility with your Flutter SDK
      onPopInvoked: (didPop) {
        if (didPop) return;
        _openBlockSelection();
      },
      child: Scaffold(
        backgroundColor: scaffoldBg,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _buildSelectedTab(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildSelectedTab() {
    switch (_selectedBottomIndex) {
      case 1:
        return const CustomerOrdersScreen();
      case 2:
        return const CustomerOffersScreen();
      case 3:
        return const CustomerAccountScreen();
      case 0:
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    return Column(
      children: [
        _buildSearchAndFilter(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadRestaurants,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: Column(
                      children: [
                        _buildPromoBanner(),
                        const SizedBox(height: 16),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(),
                          )
                        else if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            child: _errorWidget(),
                          )
                        else if (_restaurants.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(40),
                            child: Text(
                              "No restaurants found nearby 😕",
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        else
                          ..._restaurants.map(
                            (restaurant) => _buildRestaurantCard(restaurant),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _openBlockSelection,
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.black87,
                  size: 20,
                ),
              ),
              const SizedBox(width: 4),
              Image.asset(
                "assets/lo.png",
                height: 34,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Text(
                    "SelfXO",
                    style: TextStyle(
                      color: primaryRed,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  );
                },
              ),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () {
                setState(() {
                  _selectedBottomIndex = 3;
                });
              },
              icon: const Icon(
                Icons.person_outline,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: "Search restaurant...",
                  border: InputBorder.none,
                  icon: Icon(Icons.search, color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Icon(Icons.tune_rounded, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0D6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.stars, color: Colors.orange),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Student Exclusive Offers",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 2),
                Text(
                  "Save more with amazing deals!",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedBottomIndex = 2;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              "View Offers",
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(Map<String, dynamic> restaurant) {
    final routeKey = _restaurantRouteKey(restaurant);
    final isOpening = routeKey.isNotEmpty && _openingRestaurantKey == routeKey;
    final logoUrl = restaurant["logo_url"]?.toString() ?? "";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _openingRestaurantKey == null
              ? () => _openRestaurantMenu(restaurant)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 70,
                    height: 70,
                    color: Colors.grey.shade100,
                    child: logoUrl.isNotEmpty
                        ? Image.network(
                            logoUrl.replaceAll(
                                "/storage/", "/user-uploads/logo/"),
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return _RestaurantLogoFallback(
                                name: restaurant["name"] ?? "Restaurant",
                              );
                            },
                          )
                        : _RestaurantLogoFallback(
                            name: restaurant["name"] ?? "Restaurant",
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurant["name"] ?? "Restaurant",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${_restaurantSubtitle(restaurant)} • 20-30 mins",
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.green, size: 16),
                          const SizedBox(width: 4),
                          const Text(
                            "4.5",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Free delivery on ₹149+",
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                CircleAvatar(
                  backgroundColor: const Color(0xFFFFF5F2),
                  child: isOpening
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primaryRed,
                          ),
                        )
                      : Icon(Icons.arrow_forward, color: primaryRed, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedBottomIndex,
      selectedItemColor: primaryRed,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      onTap: (index) {
        setState(() {
          _selectedBottomIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_filled),
          label: "Home",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.assignment_outlined),
          label: "Orders",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.local_offer_outlined),
          label: "Offers",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          label: "Account",
        ),
      ],
    );
  }

  Widget _errorWidget() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 40, color: Colors.red),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? "Error",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _loadRestaurants,
          style: ElevatedButton.styleFrom(backgroundColor: primaryRed),
          child: const Text("Retry", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _RestaurantLogoFallback extends StatelessWidget {
  final String name;
  const _RestaurantLogoFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? "R" : name.trim()[0].toUpperCase();
    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Color(0xFFFFF3EA)),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFFD3542A),
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
