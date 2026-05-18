import 'dart:async';

import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/core/receipt_print_mode.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:api_selfxo_project/screens/main_navigation.dart';
import 'package:api_selfxo_project/screens/register_screen.dart';
import 'package:api_selfxo_project/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebQrMenuEntryScreen extends StatefulWidget {
  final String restaurantId;
  final String? requestedOrderType;
  final Map<String, dynamic>? initialRestaurant;

  const WebQrMenuEntryScreen({
    super.key,
    required this.restaurantId,
    this.requestedOrderType,
    this.initialRestaurant,
  });

  @override
  State<WebQrMenuEntryScreen> createState() => _WebQrMenuEntryScreenState();
}

class _WebQrMenuEntryScreenState extends State<WebQrMenuEntryScreen> {
  bool _loading = true;
  bool _bootstrapping = false;
  bool _navigated = false;
  String? _errorMessage;

  String _normalizedKey(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  ({String id, String? hash, String? name})? _resolveRestaurantIdentityFromList(
    String raw,
    List<Map<String, dynamic>> restaurants,
  ) {
    final needle = _normalizedKey(raw);
    if (needle.isEmpty) return null;

    for (final item in restaurants) {
      final id = item["id"]?.toString().trim() ?? "";
      final hash = item["hash"]?.toString().trim() ?? "";
      final name = item["name"]?.toString().trim() ?? "";
      if (id.isEmpty && hash.isEmpty) continue;
      final idKey = _normalizedKey(id);
      final hashKey = _normalizedKey(hash);
      final nameKey = _normalizedKey(name);
      if (needle == idKey || needle == hashKey || needle == nameKey) {
        final canonicalId = id.isNotEmpty ? id : hash;
        return (
          id: canonicalId,
          hash: hash.isNotEmpty ? hash : null,
          name: name.isNotEmpty ? name : null,
        );
      }
    }
    return null;
  }

  String? _restaurantMapId(Map<String, dynamic>? restaurant) {
    if (restaurant == null) return null;
    final v = restaurant["id"]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
    return null;
  }

  String? _restaurantMapHash(Map<String, dynamic>? restaurant) {
    if (restaurant == null) return null;
    final v = restaurant["hash"]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
    return null;
  }

  String? _restaurantMapName(Map<String, dynamic>? restaurant) {
    if (restaurant == null) return null;
    final v = restaurant["name"]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
    return null;
  }

  String _extractErrorMessage(Object error) {
    final raw = error.toString().replaceFirst("Exception: ", "").trim();
    if (raw.isEmpty) {
      return "This restaurant menu could not be opened.";
    }
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _bootstrapFromQr();
  }

  Future<void> _bootstrapFromQr() async {
    if (_bootstrapping || _navigated) return;
    _bootstrapping = true;
    final navigationTimer = Stopwatch()..start();

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final previousRestaurantId =
          prefs.getString("restaurant_id")?.trim() ?? "";
      final previousRestaurantHash =
          prefs.getString("restaurant_hash")?.trim() ?? "";

      String resolvedRestaurantId = widget.restaurantId.trim();
      String? resolvedRestaurantHash;
      String? resolvedRestaurantName;

      final selectedRestaurant = widget.initialRestaurant;
      if (selectedRestaurant != null) {
        final selectedId = _restaurantMapId(selectedRestaurant);
        final selectedHash = _restaurantMapHash(selectedRestaurant);
        final selectedName = _restaurantMapName(selectedRestaurant);
        resolvedRestaurantId =
            selectedId ?? selectedHash ?? resolvedRestaurantId;
        resolvedRestaurantHash = selectedHash;
        resolvedRestaurantName = selectedName;
      } else {
        try {
          final restaurants = await KioskApi().getAllRestaurantsWeb();
          final matched = _resolveRestaurantIdentityFromList(
            resolvedRestaurantId,
            restaurants,
          );
          if (matched != null) {
            resolvedRestaurantId = matched.id.trim();
            resolvedRestaurantHash = matched.hash?.trim();
            resolvedRestaurantName = matched.name?.trim();
          }
        } catch (_) {}
      }

      final currentRestaurantKey =
          resolvedRestaurantHash?.trim().isNotEmpty == true
              ? resolvedRestaurantHash!.trim()
              : resolvedRestaurantId;

      final restaurantChanged = previousRestaurantId.trim().isNotEmpty &&
          previousRestaurantId.trim() != currentRestaurantKey &&
          previousRestaurantHash.trim() != currentRestaurantKey;

      if (restaurantChanged) {
        await prefs.remove("auth_token");
        await prefs.remove("admin_token");
        await prefs.remove("branch_id");
        await prefs.remove("home_banner_url");
        await prefs.remove("gst_number");
      }

      await prefs.setString("restaurant_id", resolvedRestaurantId);
      if (resolvedRestaurantHash != null && resolvedRestaurantHash.isNotEmpty) {
        await prefs.setString("restaurant_hash", resolvedRestaurantHash);
      }
      if (resolvedRestaurantName != null && resolvedRestaurantName.isNotEmpty) {
        await prefs.setString("restaurant_name", resolvedRestaurantName);
      }
      await prefs.setBool("kiosk_setup_done", true);
      kioskLog(
        'web bootstrap restaurant resolved '
        'incoming=${widget.restaurantId} id=$resolvedRestaurantId '
        'hash=${resolvedRestaurantHash ?? "-"} changed=$restaurantChanged',
        tag: 'WEB_BOOTSTRAP',
      );

      final authTimer = Stopwatch()..start();
      final ok = await AuthService().initializeKiosk(force: restaurantChanged);
      authTimer.stop();
      kioskLog(
        'initializeKiosk completed ok=$ok '
        'duration=${authTimer.elapsedMilliseconds}ms',
        tag: 'WEB_BOOTSTRAP',
      );
      if (!ok) {
        throw Exception("Unable to initialize this restaurant on web.");
      }

      final orderType = _resolveInitialOrderType(
        requested: widget.requestedOrderType,
        restaurant: null,
        kioskSettings: null,
      );
      unawaited(_warmMenuDataInBackground());

      if (!mounted || _navigated) return;
      _navigated = true;
      navigationTimer.stop();
      kioskLog(
        'menu navigation ready duration=${navigationTimer.elapsedMilliseconds}ms',
        tag: 'WEB_BOOTSTRAP',
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainNavigation(orderType: orderType),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _extractErrorMessage(e);
        _loading = false;
      });
      return;
    } finally {
      _bootstrapping = false;
    }
  }

  ({Map<String, dynamic>? restaurant, Map<String, dynamic>? kioskSettings})
      _extractRestaurantBundle(dynamic raw) {
    Map<String, dynamic>? toStringKeyedMap(dynamic value) {
      if (value is! Map) return null;
      return value.map((key, value) => MapEntry("$key", value));
    }

    final root = toStringKeyedMap(raw);
    final data = toStringKeyedMap(root?["data"]);

    final restaurant = toStringKeyedMap(root?["restaurant"]) ??
        toStringKeyedMap(data?["restaurant"]);
    final kioskSettings = toStringKeyedMap(root?["kiosk_settings"]) ??
        toStringKeyedMap(data?["kiosk_settings"]);

    return (restaurant: restaurant, kioskSettings: kioskSettings);
  }

  Future<void> _applyRestaurantMeta({
    required SharedPreferences prefs,
    required Map<String, dynamic>? restaurant,
    required Map<String, dynamic>? kioskSettings,
  }) async {
    final gst = _extractTaxId(restaurant, kioskSettings);
    if (gst != null && gst.trim().isNotEmpty) {
      await prefs.setString("gst_number", gst);
    }
    await ReceiptPrintMode.storeFromMap(kioskSettings);
    await ReceiptPrintMode.storeFromMap(restaurant);
  }

  Future<void> _refreshRestaurantMetaInBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timer = Stopwatch()..start();
      final res = await KioskApi().getRestaurantData();
      timer.stop();
      kioskLog(
        'getRestaurantData background duration=${timer.elapsedMilliseconds}ms',
        tag: 'WEB_BOOTSTRAP',
      );
      final bundle = _extractRestaurantBundle(res.data);
      await _applyRestaurantMeta(
        prefs: prefs,
        restaurant: bundle.restaurant,
        kioskSettings: bundle.kioskSettings,
      );
    } catch (_) {}
  }

  Future<void> _warmMenuDataInBackground() async {
    final timer = Stopwatch()..start();
    await Future.wait<void>([
      _refreshRestaurantMetaInBackground(),
      KioskApi().warmProductsCache(),
    ]);
    timer.stop();
    kioskLog(
      'background menu warmup duration=${timer.elapsedMilliseconds}ms',
      tag: 'WEB_BOOTSTRAP',
    );
  }

  String _resolveInitialOrderType({
    required String? requested,
    required Map<String, dynamic>? restaurant,
    required Map<String, dynamic>? kioskSettings,
  }) {
    final requestedType = _normalizeOrderType(requested);
    final availability = _resolveOrderTypeAvailability(
      restaurant,
      kioskSettings,
    );

    if (requestedType != null) {
      if (requestedType == "pickup" && availability["pickup"] == true) {
        return "pickup";
      }
      if (requestedType == "dine_in" && availability["dine_in"] == true) {
        return "dine_in";
      }
      if (requestedType == "take_away" && availability["pickup"] == true) {
        return "pickup";
      }
    }

    if (availability["dine_in"] == true) return "dine_in";
    if (availability["pickup"] == true) return "pickup";
    return "dine_in";
  }

  Map<String, bool> _resolveOrderTypeAvailability(
    Map<String, dynamic>? restaurant,
    Map<String, dynamic>? kioskSettings,
  ) {
    bool? dineIn;
    bool? pickup;

    final sources = [kioskSettings, restaurant];
    for (final src in sources) {
      if (src == null) continue;

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
        final types =
            listVal.map(_normalizeOrderType).whereType<String>().toSet();
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

  String? _extractTaxId(
    Map<String, dynamic>? restaurant,
    Map<String, dynamic>? kioskSettings,
  ) {
    final sources = [kioskSettings, restaurant];
    for (final src in sources) {
      if (src == null) continue;
      final v = src["gst_number"] ??
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

  bool? _readBool(Map<String, dynamic> src, List<String> keys) {
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

  List<String>? _readList(Map<String, dynamic> src, List<String> keys) {
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

  String? _normalizeOrderType(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value
        .trim()
        .toLowerCase()
        .replaceAll("-", "_")
        .replaceAll(RegExp(r"\s+"), "_");
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF9F342C),
                    ),
                    Icon(
                      Icons.restaurant_menu_rounded,
                      size: 28,
                      color: Color(0xFF9F342C),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Text(
                "Preparing menu...",
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF1EE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      size: 38,
                      color: Color(0xFF9F342C),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Unable to open restaurant menu",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE3E6EA)),
                    ),
                    child: Text(
                      _errorMessage ??
                          "This restaurant menu could not be opened.",
                      style: const TextStyle(
                        color: Colors.black87,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _bootstrapFromQr,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9F342C),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("Retry"),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const UserIdScreen(),
                        ),
                      );
                    },
                    child: const Text("Open manual restaurant entry"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
