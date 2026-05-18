export 'kiosk_background_service_stub.dart'
    if (dart.library.html) 'kiosk_background_service_web.dart'
    if (dart.library.io) 'kiosk_background_service_io.dart';
