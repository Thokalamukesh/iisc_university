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
  int _selectedCategoryIndex = 0;

  // Design Constants
  final Color primaryBrand = const Color(0xFFD32F2F);
  final Color background = const Color(0xFFFCFCFC);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapWebRegister();
    });
  }

  // --- LOGIC KEPT AS IS ---
  Future<void> _bootstrapWebRegister() async {
    try {
      final restaurantProvider = context.read<RestaurantProvider>();
      await restaurantProvider.initializeForWeb();
      if (!mounted) return;
      final restaurants = restaurantProvider.restaurants;
      setState(() {
        _webRestaurants
          ..clear()
          ..addAll(restaurants);
        _loadingRestaurants = false;
        _restaurantLoadError = restaurants.isEmpty
            ? (restaurantProvider.errorMessage ?? "Unable to load")
            : null;
      });
    } catch (e, stackTrace) {
      kioskLogError('Web register bootstrap failed: $e',
          tag: 'WEB_RESTAURANTS', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loadingRestaurants = false;
        _restaurantLoadError = "Unable to load";
      });
    }
  }

  Future<void> _loadWebRestaurants() async {
    setState(() {
      _loadingRestaurants = true;
      _restaurantLoadError = null;
    });
    try {
      final restaurantProvider = context.read<RestaurantProvider>();
      await restaurantProvider.refreshRestaurants();
      final restaurants = restaurantProvider.restaurants;
      if (!mounted) return;
      setState(() {
        _webRestaurants
          ..clear()
          ..addAll(restaurants);
        _loadingRestaurants = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRestaurants = false;
        _restaurantLoadError = "Retry";
      });
    }
  }

  Future<void> _openRestaurantMenu(Map<String, dynamic> restaurant) async {
    if (loading) return;
    final restaurantNumericId = restaurant["id"]?.toString().trim() ?? "";
    final restaurantHash = restaurant["hash"]?.toString().trim() ?? "";
    final restaurantName = restaurant["name"]?.toString().trim() ?? "";
    final restaurantId =
        restaurantNumericId.isNotEmpty ? restaurantNumericId : restaurantHash;

    setState(() {
      loading = true;
    });
    final prefs = await SharedPreferences.getInstance();
    final previousRestaurantId = prefs.getString("restaurant_id")?.trim() ?? "";
    final changedRestaurant =
        previousRestaurantId.isNotEmpty && previousRestaurantId != restaurantId;

    if (changedRestaurant) {
      await prefs.remove("auth_token");
      await prefs.remove("admin_token");
    }
    await prefs.setString("restaurant_id", restaurantId);
    await prefs.setString("restaurant_hash", restaurantHash);
    await prefs.setString("restaurant_name", restaurantName);

    final initialized = await AuthService().initializeKiosk(
      force: changedRestaurant,
    );
    if (!initialized) {
      if (!mounted) return;
      setState(() => loading = false);
      final reason =
          AuthService.lastFailureReason ?? "Kiosk registration failed";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
      return;
    }
    await prefs.setBool("kiosk_setup_done", true);

    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => const MainNavigation(orderType: "dine_in")));
  }

  // --- NEW UI BUILDERS ---

  @override
  Widget build(BuildContext context) {
    final filtered = _webRestaurants
        .where((r) => r["name"]
            .toString()
            .toLowerCase()
            .contains(controller.text.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBox(),
            _buildCategories(),
            Expanded(
              child: _loadingRestaurants
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.red))
                  : _restaurantLoadError != null
                      ? Center(
                          child: TextButton(
                            onPressed: _loadWebRestaurants,
                            child: const Text("Retry"),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            _buildPromoBanner(),
                            const SizedBox(height: 16),
                            ...filtered.map((r) => _buildRestaurantTile(r)),
                            if (filtered.isEmpty)
                              const Center(child: Text("No restaurants found")),
                          ],
                        ),
            ),
            _buildLocationBar(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Replace the Column/Text with your Image
          Image.asset(
            'assets/lo.png', // Path to your png
            height: 30, // Adjust height to match the design
            fit: BoxFit.contain,
            // If the image fails to load during development, show a fallback
            errorBuilder: (context, error, stackTrace) {
              return const Text(
                "SELFX",
                style: TextStyle(
                  color: Color(0xFFCC0000),
                  fontWeight: FontWeight.bold,
                  fontSize: 32,
                ),
              );
            },
          ),
          const CircleAvatar(
            backgroundColor: Color.fromARGB(255, 168, 159, 159),
            child: Icon(Icons.person_outline,
                color: Color.fromARGB(255, 104, 10, 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200)),
              child: TextField(
                controller: controller,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: "Search restaurant, cuisine or dish...",
                  prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
            child: const Icon(Icons.tune_rounded),
          )
        ],
      ),
    );
  }

  Widget _buildCategories() {
    final cats = ["All Restaurants", "Fast Food", "Cafe", "Beverages"];
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: cats.length,
        itemBuilder: (context, index) {
          bool sel = _selectedCategoryIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategoryIndex = index),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF8B1A1A) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: sel ? Colors.transparent : Colors.grey.shade200),
              ),
              child: Center(
                  child: Text(cats[index],
                      style: TextStyle(
                          color: sel ? Colors.white : Colors.black87,
                          fontWeight:
                              sel ? FontWeight.bold : FontWeight.normal))),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF9F7),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFFEECE6))),
      child: Row(
        children: [
          const Icon(Icons.stars, color: Colors.orange, size: 30),
          const SizedBox(width: 12),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text("Student Exclusive Offers",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("Save more with amazing deals!",
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.orange, borderRadius: BorderRadius.circular(8)),
            child: const Text("View Offers",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildRestaurantTile(Map<String, dynamic> r) {
    final String name = r["name"]?.toString() ?? "Restaurant";
    return GestureDetector(
      onTap: () => _openRestaurantMenu(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.shade100)),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                  width: 70,
                  height: 70,
                  child: AppNetworkImage(
                      url: r["logo_url"] ?? "",
                      fit: BoxFit.cover,
                      fallback:
                          const Icon(Icons.restaurant, color: Colors.red))),
            ),
            const SizedBox(width: 15),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17)),
                  const Text("Multi Cuisine • 30-40 mins",
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 5),
                  Row(children: [
                    const Icon(Icons.star, color: Colors.green, size: 14),
                    const Text(" 4.5",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(" • Free delivery on ₹149+",
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 11)),
                  ]),
                ])),
            const CircleAvatar(
                radius: 15,
                backgroundColor: Color(0xFFFBE9E7),
                child: Icon(Icons.chevron_right, color: Colors.red, size: 18)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade100))),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.red),
          const SizedBox(width: 8),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text("Delivering to",
                    style: TextStyle(color: Colors.grey, fontSize: 10)),
                Text("Campus Area",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ])),
          OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              child: const Text("Change Location",
                  style: TextStyle(color: Colors.red, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.red,
      currentIndex: 0,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
        BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long), label: "Orders"),
        BottomNavigationBarItem(icon: Icon(Icons.local_offer), label: "Offers"),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: "Account"),
      ],
    );
  }
}
