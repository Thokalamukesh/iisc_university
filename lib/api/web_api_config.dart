class WebApiConfig {
  static const String defaultBaseUrl = "http://127.0.0.1:8000/api/";
  static const String defaultRestaurantsUrl =
      "${defaultBaseUrl}pwa/groups-restaurants";

  static const String baseUrl = String.fromEnvironment(
    "SELFX_WEB_API_BASE_URL",
    defaultValue: defaultBaseUrl,
  );

  static const String allRestaurantsUrl = String.fromEnvironment(
    "SELFX_WEB_RESTAURANTS_URL",
    defaultValue: defaultRestaurantsUrl,
  );
}
