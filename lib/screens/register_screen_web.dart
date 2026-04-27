import 'dart:async';

import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:api_selfxo_project/providers/restaurant_provider.dart';
import 'package:api_selfxo_project/screens/main_navigation.dart';
import 'package:api_selfxo_project/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget/app_network_image_web.dart';

class UserIdScreen extends StatefulWidget {
  const UserIdScreen({super.key});

  @override
  State<UserIdScreen> createState() => _UserIdScreenState();
}

class _UserIdScreenState extends State<UserIdScreen> {
  final TextEditingController controller = TextEditingController();
  final List<Map<String, dynamic>> _webRestaurants = [];

  bool loading = false;
  bool _loadingRestaurants = true;
  String? _restaurantLoadError;
  Map<String, dynamic>? _selectedRestaurant;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapWebRegister();
    });
  }

  Future<void> _bootstrapWebRegister() async {
    try {
      final restaurantProvider = context.read<RestaurantProvider>();
      await restaurantProvider
          .initializeForWeb()
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      final restaurants = restaurantProvider.restaurants;
      setState(() {
        _webRestaurants
          ..clear()
          ..addAll(restaurants);
        _loadingRestaurants = false;
        _restaurantLoadError = restaurants.isEmpty
            ? (restaurantProvider.errorMessage ?? "Unable to load restaurants")
            : null;
      });
    } catch (e, stackTrace) {
      kioskLogError(
        'Web register bootstrap failed: $e',
        tag: 'WEB_RESTAURANTS',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loadingRestaurants = false;
        _restaurantLoadError = "Unable to load restaurants";
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _loadWebRestaurants() async {
    setState(() {
      _loadingRestaurants = true;
      _restaurantLoadError = null;
    });
    try {
      final restaurantProvider = context.read<RestaurantProvider>();
      await restaurantProvider
          .refreshRestaurants()
          .timeout(const Duration(seconds: 8));
      final restaurants = restaurantProvider.restaurants;
      if (!mounted) return;
      setState(() {
        _webRestaurants
          ..clear()
          ..addAll(restaurants);
        _loadingRestaurants = false;
        _restaurantLoadError = restaurants.isEmpty
            ? (restaurantProvider.errorMessage ?? "Unable to load restaurants")
            : null;
      });
    } catch (e, stackTrace) {
      kioskLogError(
        'Direct web restaurant load failed: $e',
        tag: 'WEB_RESTAURANTS',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loadingRestaurants = false;
        _restaurantLoadError = "Unable to load restaurants";
      });
    }
  }

  String _normalized(String value) => value.trim().toLowerCase();

  String? _restaurantLogoUrl(Map<String, dynamic> restaurant) {
    final raw = restaurant["logo_url"]?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  List<Map<String, dynamic>> _filteredRestaurants() {
    final query = _normalized(controller.text);
    if (query.isEmpty) return _webRestaurants;

    return _webRestaurants.where((restaurant) {
      final name = restaurant["name"]?.toString() ?? "";
      return _normalized(name).contains(query);
    }).toList();
  }

  Future<void> _openRestaurantMenu(Map<String, dynamic> restaurant) async {
    if (loading) return;
    final restaurantNumericId = restaurant["id"]?.toString().trim() ?? "";
    final restaurantHash = restaurant["hash"]?.toString().trim() ?? "";
    final restaurantName = restaurant["name"]?.toString().trim() ?? "";
    final restaurantId =
        restaurantNumericId.isNotEmpty ? restaurantNumericId : restaurantHash;
    if (restaurantId.isEmpty) {
      _showError("Selected restaurant is invalid");
      return;
    }

    setState(() {
      loading = true;
      _selectedRestaurant = restaurant;
    });

    final prefs = await SharedPreferences.getInstance();
    final previousRestaurantId = prefs.getString("restaurant_id")?.trim() ?? "";
    final previousRestaurantHash =
        prefs.getString("restaurant_hash")?.trim() ?? "";
    final changedRestaurant = previousRestaurantId.isNotEmpty &&
        previousRestaurantId != restaurantId &&
        previousRestaurantHash != restaurantHash;
    if (changedRestaurant) {
      await prefs.remove("auth_token");
      await prefs.remove("admin_token");
      await prefs.remove("branch_id");
      await prefs.remove("home_banner_url");
      await prefs.remove("gst_number");
    }
    await prefs.setString("restaurant_id", restaurantId);
    if (restaurantHash.isNotEmpty) {
      await prefs.setString("restaurant_hash", restaurantHash);
    }
    if (restaurantName.isNotEmpty) {
      await prefs.setString("restaurant_name", restaurantName);
    }
    await prefs.setBool("kiosk_setup_done", true);
    unawaited(AuthService().initializeKiosk(force: changedRestaurant));

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const MainNavigation(orderType: "dine_in"),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  Widget _buildRestaurantCard(Map<String, dynamic> restaurant) {
    final bool isSelected = _selectedRestaurant?["id"] == restaurant["id"];
    final String name = restaurant["name"]?.toString().trim() ?? "Restaurant";
    final String? logoUrl = _restaurantLogoUrl(restaurant);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _openRestaurantMenu(restaurant),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF9F342C) : const Color(0xFFE7E3DE),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isSelected ? 0.10 : 0.05),
              blurRadius: isSelected ? 20 : 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F2EE),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: logoUrl == null
                    ? const Center(
                        child: Icon(
                          Icons.storefront_rounded,
                          size: 34,
                          color: Color(0xFF9F342C),
                        ),
                      )
                    : AppNetworkImage(
                        url: logoUrl,
                        fit: BoxFit.cover,
                        fallback: const Center(
                          child: Icon(
                            Icons.storefront_rounded,
                            size: 34,
                            color: Color(0xFF9F342C),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F1F1F),
                        height: 1.15,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isSelected
                        ? const [Color(0xFFB54439), Color(0xFF8E2A23)]
                        : const [Color(0xFFF4E8DC), Color(0xFFECD9C8)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isSelected
                              ? const Color(0xFF9F342C)
                              : const Color(0xFFC58A5A))
                          .withOpacity(0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 21,
                  color: isSelected ? Colors.white : const Color(0xFF6E302A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isTablet = media.size.width > 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFF8F4EF), Color(0xFFF3ECE5)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 28 : 18,
                        22,
                        isTablet ? 28 : 18,
                        14,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 980),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: isTablet ? 430 : double.infinity,
                                ),
                                child: TextField(
                                  controller: controller,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: "Search restaurant",
                                    hintStyle: const TextStyle(fontSize: 14),
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                      size: 20,
                                    ),
                                    suffixIcon: controller.text.isEmpty
                                        ? null
                                        : IconButton(
                                            onPressed: () {
                                              controller.clear();
                                              setState(() {});
                                            },
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                          ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE9E1D8),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF9F342C),
                                        width: 1.2,
                                      ),
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 980),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_loadingRestaurants)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 32,
                                    ),
                                    alignment: Alignment.center,
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          width: 54,
                                          height: 54,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: const [
                                              CircularProgressIndicator(
                                                strokeWidth: 3,
                                                color: Color(0xFF9F342C),
                                              ),
                                              Icon(
                                                Icons.restaurant_menu_rounded,
                                                size: 24,
                                                color: Color(0xFF9F342C),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 14),
                                        Text(
                                          "Loading restaurants...",
                                          style: TextStyle(
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (_restaurantLoadError != null)
                                  Center(
                                    child: SizedBox(
                                      width: 220,
                                      height: 44,
                                      child: OutlinedButton(
                                        onPressed: _loadWebRestaurants,
                                        child: const Text("Retry loading"),
                                      ),
                                    ),
                                  )
                                else
                                  Builder(
                                    builder: (context) {
                                      final filteredRestaurants =
                                          _filteredRestaurants();
                                      if (filteredRestaurants.isEmpty) {
                                        return const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 30,
                                          ),
                                          child: Text(
                                            "No restaurants found.",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.black54,
                                            ),
                                          ),
                                        );
                                      }

                                      return ListView.separated(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: filteredRestaurants.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 14),
                                        itemBuilder: (context, index) =>
                                            _buildRestaurantCard(
                                          filteredRestaurants[index],
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (loading)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withOpacity(0.18),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: Stack(
                              alignment: Alignment.center,
                              children: const [
                                CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Color(0xFF9F342C),
                                ),
                                Icon(
                                  Icons.restaurant_menu_rounded,
                                  size: 24,
                                  color: Color(0xFF9F342C),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                          Text("Opening menu..."),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
