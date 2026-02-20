class KioskConfig {
  // Stability over visuals for long-running kiosks.
  static const bool enableDecorativeAnimations = true;
  static const bool enableAutoScroll = true;
  static const bool enableSuccessAnimations = true;

  // Kiosk stability intervals.
  static const Duration memoryCacheClearInterval = Duration(minutes: 30);
  static const Duration maintenanceInterval = Duration(minutes: 20);
  static const Duration mediaRefreshInterval = Duration(minutes: 25);
  static const Duration activityCooldown = Duration(seconds: 30);
}
