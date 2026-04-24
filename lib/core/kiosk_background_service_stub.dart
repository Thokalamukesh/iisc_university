Future<void> initializeKioskBackgroundService() async {}

void sendUiHeartbeat() {}

void sendUiReady() {}

void reportUiCrash(Object error, StackTrace stack) {}

void sendUiManualExit({Duration cooldown = const Duration(minutes: 10)}) {}

void stopKioskBackgroundService() {}
