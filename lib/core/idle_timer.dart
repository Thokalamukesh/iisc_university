import 'package:flutter/foundation.dart';

class IdleTimer {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static void pause() {
    enabled.value = false;
  }

  static void resume() {
    enabled.value = true;
  }
}
