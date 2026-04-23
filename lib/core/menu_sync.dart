import 'package:flutter/foundation.dart';

class MenuSync {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void notifyUpdated() {
    revision.value = revision.value + 1;
  }
}
