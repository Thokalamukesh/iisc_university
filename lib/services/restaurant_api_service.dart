import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:api_selfxo_project/api/web_api_config.dart';
import 'package:api_selfxo_project/core/image_url.dart';

enum RestaurantApiErrorType {
  timeout,
  noInternet,
  server,
  badResponse,
  unknown,
}

class RestaurantApiException implements Exception {
  final RestaurantApiErrorType type;
  final String message;
  final int? statusCode;
  final Object? cause;

  const RestaurantApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.cause,
  });

  @override
  String toString() => message;
}

class RestaurantApiService {
  RestaurantApiService._();

  static final RestaurantApiService instance = RestaurantApiService._();

  static const int _maxAttempts = 3;
  static const int _defaultBranchId = 1;
  static const String _restaurantsUrl = WebApiConfig.allRestaurantsUrl;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 30),
      headers: const {
        "Accept": "application/json",
      },
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  Future<List<Map<String, dynamic>>> fetchRestaurants() async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final selectedBranchId = await _selectedBranchId();
        final queryParameters = _restaurantQueryParameters(selectedBranchId);
        kioskLog(
          'GET $_restaurantsUrl attempt $attempt/$_maxAttempts',
          tag: 'WEB_RESTAURANTS',
        );

        final response = await _dio.get(
          _restaurantsUrl,
          queryParameters: queryParameters,
        );
        final statusCode = response.statusCode ?? 0;

        if (statusCode >= 500) {
          throw RestaurantApiException(
            type: RestaurantApiErrorType.server,
            statusCode: statusCode,
            message: "Restaurant server error ($statusCode).",
          );
        }
        if (statusCode >= 400) {
          throw RestaurantApiException(
            type: RestaurantApiErrorType.badResponse,
            statusCode: statusCode,
            message: "Restaurant request failed ($statusCode).",
          );
        }

        final restaurants = _extractRestaurantList(
          response.data,
          selectedBranchId: selectedBranchId,
        );
        if (restaurants.isEmpty) {
          throw const RestaurantApiException(
            type: RestaurantApiErrorType.badResponse,
            message: "Restaurant response did not contain any restaurants.",
          );
        }

        kioskLog(
          'Loaded ${restaurants.length} restaurants',
          tag: 'WEB_RESTAURANTS',
        );
        return restaurants;
      } on RestaurantApiException catch (e) {
        final shouldRetry = e.type == RestaurantApiErrorType.server;
        if (!shouldRetry || attempt == _maxAttempts) rethrow;
        await _waitBeforeRetry(attempt, e.message);
      } on DioException catch (e) {
        final mapped = _mapDioException(e);
        final shouldRetry = _shouldRetryDioException(e);
        if (!shouldRetry || attempt == _maxAttempts) {
          throw mapped;
        }
        await _waitBeforeRetry(attempt, mapped.message);
      } catch (e) {
        throw RestaurantApiException(
          type: RestaurantApiErrorType.unknown,
          message: "Unable to load restaurants. Please try again.",
          cause: e,
        );
      }
    }

    throw const RestaurantApiException(
      type: RestaurantApiErrorType.unknown,
      message: "Unable to load restaurants. Please try again.",
    );
  }

  Future<List<Map<String, dynamic>>> fetchRestaurantGroups() async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        kioskLog(
          'GET $_restaurantsUrl groups attempt $attempt/$_maxAttempts',
          tag: 'WEB_RESTAURANTS',
        );

        final response = await _dio.get(_restaurantsUrl);
        final statusCode = response.statusCode ?? 0;

        if (statusCode >= 500) {
          throw RestaurantApiException(
            type: RestaurantApiErrorType.server,
            statusCode: statusCode,
            message: "Restaurant group server error ($statusCode).",
          );
        }
        if (statusCode >= 400) {
          throw RestaurantApiException(
            type: RestaurantApiErrorType.badResponse,
            statusCode: statusCode,
            message: "Restaurant group request failed ($statusCode).",
          );
        }

        final groups = _extractRestaurantGroups(response.data);
        if (groups.isEmpty) {
          throw const RestaurantApiException(
            type: RestaurantApiErrorType.badResponse,
            message: "Restaurant response did not contain any blocks.",
          );
        }

        kioskLog(
          'Loaded ${groups.length} restaurant groups',
          tag: 'WEB_RESTAURANTS',
        );
        return groups;
      } on RestaurantApiException catch (e) {
        final shouldRetry = e.type == RestaurantApiErrorType.server;
        if (!shouldRetry || attempt == _maxAttempts) rethrow;
        await _waitBeforeRetry(attempt, e.message);
      } on DioException catch (e) {
        final mapped = _mapDioException(e);
        final shouldRetry = _shouldRetryDioException(e);
        if (!shouldRetry || attempt == _maxAttempts) {
          throw mapped;
        }
        await _waitBeforeRetry(attempt, mapped.message);
      } catch (e) {
        throw RestaurantApiException(
          type: RestaurantApiErrorType.unknown,
          message: "Unable to load blocks. Please try again.",
          cause: e,
        );
      }
    }

    throw const RestaurantApiException(
      type: RestaurantApiErrorType.unknown,
      message: "Unable to load blocks. Please try again.",
    );
  }

  List<Map<String, dynamic>> _extractRestaurantList(
    dynamic raw, {
    required int selectedBranchId,
  }) {
    final rawList = raw is List
        ? raw
        : raw is Map
            ? (raw["data"] ?? raw["restaurants"] ?? raw["items"])
            : null;
    if (rawList is! List) return const [];

    final restaurants = <Map<String, dynamic>>[];
    for (final item in rawList.whereType<Map>()) {
      final groupedRestaurants = item["restaurants"];
      if (groupedRestaurants is List) {
        if (!_matchesGroup(item, selectedBranchId)) {
          continue;
        }
        for (final restaurant in groupedRestaurants.whereType<Map>()) {
          restaurants.add(_mapGroupRestaurant(
            group: item,
            restaurant: restaurant,
          ));
        }
        continue;
      }

      final locations = item["locations"];
      if (locations is List) {
        for (final location in locations.whereType<Map>()) {
          if (!_matchesBranch(location, selectedBranchId)) continue;

          final nestedRestaurants = location["restaurants"];
          if (nestedRestaurants is! List) {
            if (_hasLocationRestaurant(location)) {
              restaurants.add(_mapGroupedRestaurant(
                cityGroup: item,
                location: location,
                restaurant: _restaurantFromLocation(location),
              ));
            }
            continue;
          }

          for (final restaurant in nestedRestaurants.whereType<Map>()) {
            restaurants.add(_mapGroupedRestaurant(
              cityGroup: item,
              location: location,
              restaurant: restaurant,
            ));
          }
        }
        continue;
      }

      final restaurant = item.map((key, value) => MapEntry("$key", value));
      restaurants.add({
        ...restaurant,
        "logo_url": _restaurantLogoUrl(
          restaurant["logo_url"] ?? restaurant["logo"],
        ),
      });
    }

    return restaurants;
  }

  List<Map<String, dynamic>> _extractRestaurantGroups(dynamic raw) {
    final rawList = raw is List
        ? raw
        : raw is Map
            ? (raw["data"] ?? raw["groups"] ?? raw["items"])
            : null;
    if (rawList is! List) return const [];

    final groups = <Map<String, dynamic>>[];
    for (final item in rawList.whereType<Map>()) {
      final restaurants = item["restaurants"];
      if (restaurants is! List) continue;

      final mappedGroup = item.map((key, value) => MapEntry("$key", value));
      mappedGroup["restaurants"] = restaurants.whereType<Map>().map((restaurant) {
        final mappedRestaurant =
            restaurant.map((key, value) => MapEntry("$key", value));
        mappedRestaurant["logo_url"] = _restaurantLogoUrl(
          mappedRestaurant["logo_url"] ?? mappedRestaurant["logo"],
        );
        return mappedRestaurant;
      }).toList();
      groups.add(mappedGroup);
    }

    return groups;
  }

  Map<String, dynamic> _mapGroupRestaurant({
    required Map group,
    required Map restaurant,
  }) {
    final mappedRestaurant =
        restaurant.map((key, value) => MapEntry("$key", value));
    final mappedGroup = group.map((key, value) => MapEntry("$key", value));
    final groupId = mappedGroup["group_id"] ?? mappedGroup["id"];
    final groupName = mappedGroup["group_name"] ?? mappedGroup["name"];
    final restaurantId =
        mappedRestaurant["restaurant_id"] ?? mappedRestaurant["id"];
    final hash = mappedRestaurant["hash"] ?? mappedRestaurant["slug"];

    return {
      ...mappedRestaurant,
      "id": restaurantId,
      "restaurant_id": restaurantId,
      "restaurantId": restaurantId,
      "hash": hash,
      "restaurant_hash": hash,
      "branch_id": groupId,
      "branch_name": groupName,
      "group_id": groupId,
      "group_name": groupName,
      "logo_url": _restaurantLogoUrl(
        mappedRestaurant["logo_url"] ?? mappedRestaurant["logo"],
      ),
    };
  }

  Map<String, dynamic> _mapGroupedRestaurant({
    required Map cityGroup,
    required Map location,
    required Map restaurant,
  }) {
    final mappedRestaurant =
        restaurant.map((key, value) => MapEntry("$key", value));
    final mappedLocation =
        location.map((key, value) => MapEntry("$key", value));
    final mappedCity = cityGroup.map((key, value) => MapEntry("$key", value));
    final restaurantId =
        mappedRestaurant["restaurant_id"] ?? mappedRestaurant["id"];
    final hash = mappedRestaurant["hash"] ?? mappedRestaurant["slug"];

    return {
      ...mappedRestaurant,
      "id": restaurantId,
      "restaurant_id": restaurantId,
      "restaurantId": restaurantId,
      "hash": hash,
      "restaurant_hash": hash,
      "city": mappedCity["city"],
      "branch_id": mappedLocation["branch_id"],
      "branch_name": mappedLocation["branch_name"],
      "address": mappedLocation["address"],
      "logo_url": _restaurantLogoUrl(
        mappedRestaurant["logo_url"] ?? mappedRestaurant["logo"],
      ),
    };
  }

  bool _matchesBranch(Map location, int selectedBranchId) {
    final rawBranchId = location["branch_id"] ?? location["branchId"];
    final branchId = rawBranchId is int
        ? rawBranchId
        : int.tryParse(rawBranchId?.toString().trim() ?? "");
    return branchId == null || branchId == selectedBranchId;
  }

  bool _matchesGroup(Map group, int selectedBranchId) {
    final rawGroupId = group["group_id"] ?? group["groupId"] ?? group["id"];
    final groupId = rawGroupId is int
        ? rawGroupId
        : int.tryParse(rawGroupId?.toString().trim() ?? "");
    return groupId == null || groupId == selectedBranchId;
  }

  bool get _isPwaGroupsRestaurantsEndpoint {
    final endpoint = Uri.tryParse(_restaurantsUrl);
    return endpoint?.path.endsWith("/pwa/groups-restaurants") ?? false;
  }

  bool _hasLocationRestaurant(Map location) {
    return location["restaurant_id"] != null ||
        location["restaurant_name"] != null ||
        location["restaurant_hash"] != null;
  }

  Map<String, dynamic> _restaurantFromLocation(Map location) {
    return {
      "restaurant_id": location["restaurant_id"],
      "id": location["restaurant_id"],
      "name": location["restaurant_name"],
      "hash": location["restaurant_hash"],
      "logo": location["restaurant_logo"],
    };
  }

  Future<int> _selectedBranchId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt("branch_id") ??
        int.tryParse(prefs.getString("branch_id")?.trim() ?? "") ??
        _defaultBranchId;
  }

  Map<String, dynamic>? _restaurantQueryParameters(int selectedBranchId) {
    final endpoint = Uri.tryParse(_restaurantsUrl);
    if (endpoint?.queryParameters.containsKey("branch_id") ?? false) {
      return null;
    }
    if (_isPwaGroupsRestaurantsEndpoint) {
      return null;
    }

    return {
      "branch_id": selectedBranchId,
    };
  }

  String _restaurantLogoUrl(dynamic value) {
    final raw = value?.toString().trim() ?? "";
    if (raw.isEmpty) return "";
    if (raw.startsWith("http://") ||
        raw.startsWith("https://") ||
        raw.startsWith("//") ||
        raw.startsWith("data:")) {
      return normalizeImageUrl(raw);
    }

    final endpoint = Uri.tryParse(_restaurantsUrl);
    if (endpoint != null && endpoint.hasScheme && endpoint.host.isNotEmpty) {
      final port = endpoint.hasPort ? ":${endpoint.port}" : "";
      final origin = "${endpoint.scheme}://${endpoint.host}$port";
      final path = raw.startsWith("/") ? raw.substring(1) : raw;
      final resolvedPath = path.contains("/") ? path : "storage/$path";
      return Uri.encodeFull("$origin/$resolvedPath");
    }

    return normalizeImageUrl(raw);
  }

  RestaurantApiException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return RestaurantApiException(
          type: RestaurantApiErrorType.timeout,
          message: "Restaurant server took too long to respond.",
          cause: e,
        );
      case DioExceptionType.connectionError:
        return RestaurantApiException(
          type: RestaurantApiErrorType.noInternet,
          message:
              "No internet connection or restaurant server is unreachable.",
          cause: e,
        );
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        return RestaurantApiException(
          type: (statusCode ?? 0) >= 500
              ? RestaurantApiErrorType.server
              : RestaurantApiErrorType.badResponse,
          statusCode: statusCode,
          message: statusCode == null
              ? "Restaurant request failed."
              : "Restaurant request failed ($statusCode).",
          cause: e,
        );
      case DioExceptionType.cancel:
        return RestaurantApiException(
          type: RestaurantApiErrorType.unknown,
          message: "Restaurant request was cancelled.",
          cause: e,
        );
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return RestaurantApiException(
          type: RestaurantApiErrorType.unknown,
          message: "Unable to load restaurants. Please try again.",
          cause: e,
        );
    }
  }

  bool _shouldRetryDioException(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }

    final statusCode = e.response?.statusCode ?? 0;
    return statusCode >= 500;
  }

  Future<void> _waitBeforeRetry(int attempt, String reason) async {
    final delay = Duration(milliseconds: 500 * attempt);
    kioskLog(
      'Restaurant request retrying in ${delay.inMilliseconds}ms: $reason',
      tag: 'WEB_RESTAURANTS',
    );
    await Future.delayed(delay);
  }
}
