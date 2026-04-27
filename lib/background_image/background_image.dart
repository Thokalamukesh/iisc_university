import 'dart:async';

import 'package:api_selfxo_project/core/kiosk_bootstrap.dart';
import 'package:api_selfxo_project/core/kiosk_config.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';
import 'package:api_selfxo_project/core/connectivity_service.dart';
import 'package:api_selfxo_project/core/receipt_print_mode.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/kiosk_api.dart';
import '../screens/main_navigation.dart';
import '../screens/pin_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late PageController _pageController;
  Timer? _sliderTimer;
  VoidCallback? _maintenanceListener;
  VoidCallback? _mediaRefreshListener;
  int _mediaRefreshKey = 0;

  bool isLoading = true;
  bool hasError = false;
  bool _openingAdmin = false;
  bool _openingOrder = false;
  bool _loadingRestaurant = false;
  VoidCallback? _onlineListener;

  String restaurantName = "Start Your Order";
  List<String> banners = [];
  int currentIndex = 0;
  bool _showDineIn = true;
  bool _showPickup = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();

    _loadRestaurant();

    ConnectivityService.instance.start();
    _onlineListener = () {
      final online = ConnectivityService.instance.isOnline.value;
      if (online && (hasError || isLoading)) {
        if (!mounted) return;
        setState(() {
          isLoading = true;
          hasError = false;
        });
        _loadRestaurant();
      }
    };
    ConnectivityService.instance.isOnline.addListener(_onlineListener!);

    _maintenanceListener = _handleMaintenanceTick;
    KioskMemoryService.instance.maintenanceTick.addListener(
      _maintenanceListener!,
    );
    _mediaRefreshListener = _handleMediaRefreshTick;
    KioskMemoryService.instance.mediaRefreshTick.addListener(
      _mediaRefreshListener!,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _sliderTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startSlider();
    }
  }

  Future<void> _loadRestaurant() async {
    if (_loadingRestaurant) return;
    _loadingRestaurant = true;
    try {
      await DeviceBootstrap.ensureDeviceReady();
      final res = await KioskApi().getRestaurantData();

      final prefs = await SharedPreferences.getInstance();

      final restaurant = res.data["restaurant"];
      final media = restaurant?["media"];
      final kioskSettings = res.data["kiosk_settings"];

      final backendDeviceId = kioskSettings?["device_id"];
      if (backendDeviceId != null && backendDeviceId.toString().isNotEmpty) {
        await prefs.setString("device_uuid", backendDeviceId.toString());
      }

      final gst = _extractTaxId(
        restaurant is Map ? restaurant : null,
        kioskSettings is Map ? kioskSettings : null,
      );
      if (gst != null && gst.toString().trim().isNotEmpty) {
        await prefs.setString("gst_number", gst.toString().trim());
      }

      await ReceiptPrintMode.storeFromMap(
        kioskSettings is Map ? kioskSettings : null,
      );
      await ReceiptPrintMode.storeFromMap(
        restaurant is Map ? restaurant : null,
      );

      List<String> tempBanners = [];
      if (media is List) {
        tempBanners = media
            .whereType<Map>()
            .where((m) => m["path"] != null)
            .map<String>((m) => m["path"].toString())
            .toList();
      }

      if (tempBanners.isEmpty &&
          kioskSettings is Map &&
          kioskSettings["home_banner_url"] != null) {
        tempBanners.add(kioskSettings["home_banner_url"].toString());
      }

      if (!mounted) return;

      final types = _resolveOrderTypeAvailability(
        restaurant is Map ? restaurant : null,
        kioskSettings is Map ? kioskSettings : null,
      );

      setState(() {
        restaurantName = restaurant?["name"] ?? "Start Your Order";
        banners = tempBanners;
        _showDineIn = types["dine_in"] ?? true;
        _showPickup = types["pickup"] ?? true;
        isLoading = false;
        hasError = false;
      });

      _startSlider();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        hasError = true;
        isLoading = false;
      });
    } finally {
      _loadingRestaurant = false;
    }
  }

  void _startSlider() {
    _sliderTimer?.cancel();
    if (!KioskConfig.enableAutoScroll) return;
    if (banners.length < 2) return;
    _sliderTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      try {
        if (!_pageController.hasClients) return;
        currentIndex = (currentIndex + 1) % banners.length;
        _pageController.animateToPage(
          currentIndex,
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeInOutSine,
        );
      } catch (_) {}
    });
  }

  void _handleMaintenanceTick() {
    if (!mounted) return;
    try {
      _sliderTimer?.cancel();
      if (banners.length < 2) return;
      final int page = _pageController.hasClients
          ? (_pageController.page?.round() ?? currentIndex)
          : currentIndex;
      _pageController.dispose();
      _pageController = PageController(initialPage: page);
      currentIndex = page;
      _startSlider();
    } catch (_) {}
  }

  void _handleMediaRefreshTick() {
    if (!mounted) return;
    _mediaRefreshKey = KioskMemoryService.instance.mediaRefreshTick.value;
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_onlineListener != null) {
      ConnectivityService.instance.isOnline.removeListener(_onlineListener!);
    }
    if (_maintenanceListener != null) {
      KioskMemoryService.instance.maintenanceTick.removeListener(
        _maintenanceListener!,
      );
    }
    if (_mediaRefreshListener != null) {
      KioskMemoryService.instance.mediaRefreshTick.removeListener(
        _mediaRefreshListener!,
      );
    }
    _sliderTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final bool isTablet = MediaQuery.of(context).size.width > 600;

    final Size screenSize = MediaQuery.of(context).size;
    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final int bannerCacheWidth = (screenSize.width * dpr).round();
    final int bannerCacheHeight = (screenSize.height * dpr).round();

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: banners.isEmpty
                ? Container(color: Colors.black)
                : PageView.builder(
                    key: ValueKey("banner-refresh-$_mediaRefreshKey"),
                    controller: _pageController,
                    itemCount: banners.length,
                    itemBuilder: (_, i) => Image.network(
                      banners[i],
                      fit: BoxFit.cover,
                      cacheWidth: bannerCacheWidth,
                      cacheHeight: bannerCacheHeight,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
          ),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black38, Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
          Positioned(
            top: -5,
            left: -30,
            right: -10, // 🔒 full width so right alignment works
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 40 : 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    _glassContainer(
                      isTablet: isTablet,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            restaurantName.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isTablet ? 24 : 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "(A PRODUCT OF SIRIXO)",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isTablet ? 12 : 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(), // 👈 pushes icon to the right

                    _adminWithStatus(isTablet),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: isTablet ? 80 : 40,
            left: isTablet ? 100 : 20,
            right: isTablet ? 80 : 20,
            child: _orderPanel(isTablet),
          ),
        ],
      ),
    );
  }

  Widget _adminWithStatus(bool isTablet) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isOnline,
      builder: (_, online, __) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _adminButton(isTablet),
            Positioned(
              top: -10,
              right: -25,
              child: Container(
                width: isTablet ? 12 : 10,
                height: isTablet ? 12 : 10,
                decoration: BoxDecoration(
                  color: online
                      ? const Color.fromARGB(151, 105, 240, 175)
                      : Colors.redAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: online ? Colors.green : Colors.red,
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _adminButton(bool isTablet) {
    return IconButton(
      icon: Icon(
        Icons.person_rounded,
        color: Colors.white,
        size: isTablet ? 30 : 30,
      ),
      onPressed: _openingAdmin
          ? null
          : () async {
              setState(() => _openingAdmin = true);
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const PinScreen(),
              );
              if (!mounted) return;
              setState(() {
                _openingAdmin = false;
                isLoading = true;
              });
              _loadRestaurant();
            },
    );
  }

  Widget _orderPanel(bool isTablet) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 15 : 25),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            "TAP TO START BELOW",
            style: TextStyle(
              fontSize: isTablet ? 42 : 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),

          const SizedBox(height: 40),
          if (_showDineIn || _showPickup)
            Builder(
              builder: (_) {
                if (_showDineIn && !_showPickup) {
                  return Center(
                    child: SizedBox(
                      width: isTablet ? 360 : 240,
                      child: _orderButton(
                        "EAT HERE",
                        Icons.restaurant_rounded,
                        Colors.green.shade700,
                        "dine_in",
                        isTablet,
                      ),
                    ),
                  );
                }
                if (_showPickup && !_showDineIn) {
                  return Column(
                    children: [
                      SizedBox(
                        width: isTablet ? 360 : 240,
                        child: _orderButton(
                          "TAKE AWAY",
                          Icons.shopping_bag_rounded,
                          Colors.orange.shade800,
                          "pickup",
                          isTablet,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Eat Here not available",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_showDineIn)
                      Expanded(
                        child: _orderButton(
                          "EAT HERE",
                          Icons.restaurant_rounded,
                          Colors.green.shade700,
                          "dine_in",
                          isTablet,
                        ),
                      ),
                    if (_showDineIn && _showPickup)
                      SizedBox(width: isTablet ? 45 : 12),
                    if (_showPickup)
                      Expanded(
                        child: _orderButton(
                          "TAKE AWAY",
                          Icons.shopping_bag_rounded,
                          Colors.orange.shade800,
                          "pickup",
                          isTablet,
                        ),
                      ),
                  ],
                );
              },
            )
          else
            const Text(
              "Ordering unavailable",
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Map<String, bool> _resolveOrderTypeAvailability(
    Map? restaurant,
    Map? kioskSettings,
  ) {
    bool? dineIn;
    bool? pickup;

    final sources = [kioskSettings, restaurant];
    for (final src in sources) {
      if (src is! Map) continue;

      final listVal = _readList(src, const [
        "order_types",
        "orderTypes",
        "available_order_types",
        "order_type_list",
        "orderTypeList",
        "order_type",
        "orderType",
      ]);
      if (listVal != null && listVal.isNotEmpty) {
        final types = listVal.map(_normalizeOrderType).toSet();
        if (types.any((t) => t == "dine_in" || t == "dinein")) {
          dineIn = true;
        }
        if (types.any(
          (t) => t == "pickup" || t == "takeaway" || t == "take_away",
        )) {
          pickup = true;
        }
        if (dineIn != true) dineIn = false;
        if (pickup != true) pickup = false;
      }

      dineIn ??= _readBool(src, const [
        "dine_in",
        "dinein",
        "eat_here",
        "eatHere",
        "is_dine_in",
        "dine_in_enabled",
        "eat_here_enabled",
        "allow_dine_in_orders",
      ]);

      pickup ??= _readBool(src, const [
        "pickup",
        "takeaway",
        "take_away",
        "takeAway",
        "is_pickup",
        "pickup_enabled",
        "takeaway_enabled",
        "take_away_enabled",
        "allow_customer_pickup_orders",
      ]);

      final allowCustomerOrders = _readBool(src, const [
        "allow_customer_orders",
        "customer_orders_enabled",
        "allow_orders",
      ]);
      if (allowCustomerOrders == false) {
        dineIn = false;
        pickup = false;
      }
    }

    return {"dine_in": dineIn ?? true, "pickup": pickup ?? true};
  }

  String? _extractTaxId(Map? restaurant, Map? kioskSettings) {
    final sources = [kioskSettings, restaurant];
    for (final src in sources) {
      if (src is! Map) continue;
      final v =
          src["gst_number"] ??
          src["gstin"] ??
          src["tax_id"] ??
          src["taxId"] ??
          src["gst_no"] ??
          src["gst"];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
  }

  bool? _readBool(Map src, List<String> keys) {
    for (final k in keys) {
      if (!src.containsKey(k)) continue;
      final v = src[k];
      if (v is bool) return v;
      if (v is num) return v > 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == "true" || s == "1" || s == "yes") return true;
        if (s == "false" || s == "0" || s == "no") return false;
      }
    }
    return null;
  }

  List<String>? _readList(Map src, List<String> keys) {
    for (final k in keys) {
      if (!src.containsKey(k)) continue;
      final v = src[k];
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
      if (v is String && v.isNotEmpty) {
        return v.split(",").map((e) => e.trim()).toList();
      }
    }
    return null;
  }

  String _normalizeOrderType(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll("-", "_")
        .replaceAll(RegExp(r"\s+"), "_");
  }

  Widget _orderButton(
    String label,
    IconData icon,
    Color color,
    String type,
    bool isTablet,
  ) {
    return InkWell(
      onTap: _openingOrder
          ? null
          : () {
              setState(() => _openingOrder = true);
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) =>
                      MainNavigation(orderType: type),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            },
      child: Container(
        height: isTablet ? 100 : 100, // Reduced height for horizontal layout
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          // Changed from Column to Row
          children: [
            Icon(icon, size: isTablet ? 60 : 30, color: Colors.white),
            SizedBox(width: isTablet ? 15 : 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: isTablet ? 30 : 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassContainer({required Widget child, required bool isTablet}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Container(
        constraints: BoxConstraints(minWidth: isTablet ? 260 : 180),
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 20 : 14,
          vertical: isTablet ? 10 : 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white24),
        ),
        child: child,
      ),
    );
  }
}
