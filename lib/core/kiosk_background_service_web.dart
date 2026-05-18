// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> initializeKioskBackgroundService() async {}

void stopKioskBackgroundService() {}

void sendUiHeartbeat() {}

void sendUiReady() {
  html.window.console.info('[SELFX][WEB] Flutter first frame ready.');
  html.window.dispatchEvent(html.Event('selfx-flutter-ready'));
}

void reportUiCrash(Object error, StackTrace stack) {
  html.window.console.error('[SELFX][WEB] Flutter crash: $error');
  html.window.console.error('[SELFX][WEB] Flutter stack: $stack');
  html.window.dispatchEvent(html.CustomEvent('selfx-flutter-error', detail: {
    'message': error.toString(),
    'stack': stack.toString(),
  }));
}

void sendUiManualExit({Duration cooldown = const Duration(minutes: 10)}) {}
