import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RestaurantProvider extends ChangeNotifier {
  static const String _defaultFallbackRestaurantSlug = "demo-restaurant";
  static const List<String> _restaurantQueryKeys = <String>[
    "restaurant_id",
    "restaurantId",
    "rid",
    "restaurant",
    "slug",
  ];
  static const List<String> _orderTypeQueryKeys = <String>[
    "order_type",
    "orderType",
    "type",
  ];

  bool _initializing = false;
  bool _initialized = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _restaurants = const [];
  String? _launchRestaurantId;
  String? _launchOrderType;
  String? _savedRestaurantId;
  String? _savedRestaurantName;
  String? _fallbackRestaurantId;

  bool get isInitializing => _initializing;
  bool get isInitialized => _initialized;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get restaurants => _restaurants;
  String? get launchRestaurantId => _launchRestaurantId;
  String? get launchOrderType => _launchOrderType;
  String? get savedRestaurantId => _savedRestaurantId;
  String? get savedRestaurantName => _savedRestaurantName;
  String? get fallbackRestaurantId => _fallbackRestaurantId;

  Future<void> initializeForWeb() async {
    if (!kIsWeb || _initialized || _initializing) return;
    _initializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final routeContext = _parseRouteContext(Uri.base);

      _launchOrderType = routeContext.orderType;
      _savedRestaurantId = prefs.getString("restaurant_id")?.trim();
      _savedRestaurantName = prefs.getString("restaurant_name")?.trim();

      _restaurants = await _loadRestaurantsSafely();

      final explicitRestaurant = routeContext.restaurantId;
      if (explicitRestaurant != null && explicitRestaurant.isNotEmpty) {
        final matched = _matchRestaurant(explicitRestaurant);
        _launchRestaurantId =
            _restaurantIdentifier(matched) ?? explicitRestaurant;
        _savedRestaurantName = matched?["name"]?.toString().trim();
        await _persistSelection(
          restaurantId: _launchRestaurantId!,
          restaurantName: _savedRestaurantName,
        );
      }

      _fallbackRestaurantId = _resolveFallbackRestaurantId();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "").trim();
    } finally {
      _initializing = false;
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> refreshRestaurants() async {
    if (!kIsWeb || _initializing) return;
    _initializing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _restaurants = await _loadRestaurantsSafely(forceRefresh: true);
      _fallbackRestaurantId = _resolveFallbackRestaurantId();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "").trim();
    } finally {
      _initializing = false;
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> setSelectedRestaurant(Map<String, dynamic> restaurant) async {
    final restaurantId = restaurant["id"]?.toString().trim().isNotEmpty == true
        ? restaurant["id"].toString().trim()
        : _restaurantIdentifier(restaurant);
    if (restaurantId == null || restaurantId.isEmpty) return;
    final restaurantHash = restaurant["hash"]?.toString().trim();
    final restaurantName = restaurant["name"]?.toString().trim();
    await _persistSelection(
      restaurantId: restaurantId,
      restaurantHash: restaurantHash,
      restaurantName: restaurantName,
    );
    _savedRestaurantId = restaurantId;
    _savedRestaurantName = restaurantName;
    notifyListeners();
  }

  Future<void> _persistSelection({
    required String restaurantId,
    String? restaurantHash,
    String? restaurantName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("restaurant_id", restaurantId);
    if (restaurantHash != null && restaurantHash.trim().isNotEmpty) {
      await prefs.setString("restaurant_hash", restaurantHash.trim());
    }
    if (restaurantName != null && restaurantName.trim().isNotEmpty) {
      await prefs.setString("restaurant_name", restaurantName.trim());
    }
  }

  Future<List<Map<String, dynamic>>> _loadRestaurantsSafely({
    bool forceRefresh = false,
  }) async {
    try {
      return await KioskApi()
          .getAllRestaurantsWeb(forceRefresh: forceRefresh)
          .timeout(const Duration(seconds: 15));
    } catch (e, stackTrace) {
      kioskLogError(
        'Restaurant load failed: $e',
        tag: 'WEB_RESTAURANTS',
        error: e,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  String? _resolveFallbackRestaurantId() {
    final savedMatch = _matchRestaurant(_savedRestaurantId);
    final explicitMatch = _matchRestaurant(_launchRestaurantId);
    final fallbackMatch = _matchRestaurant(_defaultFallbackRestaurantSlug);

    return _restaurantIdentifier(savedMatch) ??
        _restaurantIdentifier(explicitMatch) ??
        _restaurantIdentifier(fallbackMatch) ??
        (_restaurants.isNotEmpty
            ? _restaurantIdentifier(_restaurants.first)
            : null);
  }

  Map<String, dynamic>? _matchRestaurant(String? rawId) {
    if (rawId == null || rawId.trim().isEmpty) return null;
    final candidate = rawId.trim().toLowerCase();
    for (final restaurant in _restaurants) {
      final id = restaurant["id"]?.toString().trim().toLowerCase();
      final hash = restaurant["hash"]?.toString().trim().toLowerCase();
      if (candidate == id || candidate == hash) {
        return restaurant;
      }
    }
    return null;
  }

  String? _restaurantIdentifier(Map<String, dynamic>? restaurant) {
    if (restaurant == null) return null;
    final id = restaurant["id"]?.toString().trim();
    if (id != null && id.isNotEmpty) return id;
    final hash = restaurant["hash"]?.toString().trim();
    if (hash != null && hash.isNotEmpty) return hash;
    return null;
  }

  _ResolvedWebRestaurantContext _parseRouteContext(Uri baseUri) {
    String? restaurantId =
        _firstNonEmpty(baseUri.queryParameters, _restaurantQueryKeys);
    String? orderType =
        _firstNonEmpty(baseUri.queryParameters, _orderTypeQueryKeys);

    restaurantId ??= _extractRestaurantFromPath(baseUri.pathSegments);

    final fragment = baseUri.fragment.trim();
    if (fragment.isNotEmpty) {
      final normalizedFragment =
          fragment.startsWith("/") ? fragment : "/$fragment";
      final fragmentUri = Uri.tryParse(normalizedFragment);
      if (fragmentUri != null) {
        restaurantId ??=
            _firstNonEmpty(fragmentUri.queryParameters, _restaurantQueryKeys);
        orderType ??=
            _firstNonEmpty(fragmentUri.queryParameters, _orderTypeQueryKeys);
        restaurantId ??= _extractRestaurantFromPath(fragmentUri.pathSegments);
      }
    }

    return _ResolvedWebRestaurantContext(
      restaurantId: restaurantId,
      orderType: orderType,
    );
  }

  String? _firstNonEmpty(
    Map<String, String> params,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = params[key];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _extractRestaurantFromPath(List<String> rawSegments) {
    final segments = rawSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;

    for (var i = 0; i < segments.length - 1; i++) {
      final current = segments[i].toLowerCase();
      if (current == "restaurant" ||
          current == "restaurants" ||
          current == "restaurants-home" ||
          current == "menu" ||
          current == "kiosk") {
        final next = segments[i + 1].trim();
        if (next.isNotEmpty) return next;
      }
    }

    return null;
  }
}

class _ResolvedWebRestaurantContext {
  final String? restaurantId;
  final String? orderType;

  const _ResolvedWebRestaurantContext({
    required this.restaurantId,
    required this.orderType,
  });
}
