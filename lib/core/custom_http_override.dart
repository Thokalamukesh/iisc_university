import 'dart:io';
import 'package:api_selfxo_project/core/kiosk_log.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        return true; // Accept all SSL certificates
      };
  }
}
