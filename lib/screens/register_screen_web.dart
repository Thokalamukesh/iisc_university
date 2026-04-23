import 'dart:async';

import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:api_selfxo_project/providers/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/web_qr_menu_entry.dart';
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
      if (restaurantProvider.restaurants.isNotEmpty) {
        setState(() {
          _webRestaurants
            ..clear()
            ..addAll(restaurantProvider.restaurants);
          _loadingRestaurants = false;
          _restaurantLoadError = restaurantProvider.errorMessage;
        });
        return;
      }
    } catch (e, stackTrace) {
      kioskLogError(
        'Web register bootstrap failed: $e',
        tag: 'WEB_RESTAURANTS',
        error: e,
        stackTrace: stackTrace,
      );
    }

    await _loadWebRestaurants();
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
      final restaurants = restaurantProvider.restaurants.isNotEmpty
          ? restaurantProvider.restaurants
          : await KioskApi()
                .getAllRestaurantsWeb()
                .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _webRestaurants
          ..clear()
          ..addAll(restaurants);
        _loadingRestaurants = false;
        _restaurantLoadError = restaurants.isEmpty
            ? (restaurantProvider.errorMessage ?? "No restaurants found")
            : restaurantProvider.errorMessage;
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
      final id = restaurant["id"]?.toString() ?? "";
      final hash = restaurant["hash"]?.toString() ?? "";
      final name = restaurant["name"]?.toString() ?? "";
      return _normalized(name).contains(query) ||
          _normalized(hash).contains(query) ||
          _normalized(id).contains(query);
    }).toList();
  }

  Future<void> _openRestaurantMenu(Map<String, dynamic> restaurant) async {
    if (loading) return;
    final restaurantProvider = context.read<RestaurantProvider>();

    final restaurantId =
        restaurant["hash"]?.toString().trim().isNotEmpty == true
            ? restaurant["hash"].toString().trim()
            : restaurant["id"]?.toString().trim() ?? "";
    if (restaurantId.isEmpty) {
      _showError("Selected restaurant is invalid");
      return;
    }

    setState(() {
      loading = true;
      _selectedRestaurant = restaurant;
    });

    await restaurantProvider.setSelectedRestaurant(restaurant);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WebQrMenuEntryScreen(restaurantId: restaurantId),
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
      borderRadius: BorderRadius.circular(22),
      onTap: () => _openRestaurantMenu(restaurant),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF9F342C) : const Color(0xFFE7E3DE),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isSelected ? 0.10 : 0.05),
              blurRadius: isSelected ? 24 : 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F2EE),
                ),
                clipBehavior: Clip.antiAlias,
                child: logoUrl == null
                    ? const Center(
                        child: Icon(
                          Icons.storefront_rounded,
                          size: 40,
                          color: Color(0xFF9F342C),
                        ),
                      )
                    : AppNetworkImage(
                        url: logoUrl,
                        fit: BoxFit.cover,
                        fallback: const Center(
                          child: Icon(
                            Icons.storefront_rounded,
                            size: 40,
                            color: Color(0xFF9F342C),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.fade,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F1F1F),
                      height: 1.2,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isSelected
                            ? const [Color(0xFFB54439), Color(0xFF8E2A23)]
                            : const [Color(0xFFF4E8DC), Color(0xFFECD9C8)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: (isSelected
                                  ? const Color(0xFF9F342C)
                                  : const Color(0xFFC58A5A))
                              .withOpacity(0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Order Now",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF6E302A),
                          ),
                        ),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withOpacity(0.18)
                                : Colors.white.withOpacity(0.72),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF6E302A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                                    child: const Column(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
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

                                      return GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: filteredRestaurants.length,
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: media.size.width > 900
                                              ? 4
                                              : media.size.width > 700
                                                  ? 3
                                                  : 2,
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 16,
                                          childAspectRatio: 0.8,
                                        ),
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
                          CircularProgressIndicator(),
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
