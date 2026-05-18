import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const double kTabletShortestSide = 600;

bool isTabletContext(BuildContext context) {
  return MediaQuery.of(context).size.shortestSide >= kTabletShortestSide;
}

bool isTabletAtStartup() {
  if (kIsWeb) return false;
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  if (dispatcher.views.isEmpty) return false;
  final FlutterView view = dispatcher.views.first;
  final dpr = view.devicePixelRatio <= 0 ? 1.0 : view.devicePixelRatio;
  final shortestDp = view.physicalSize.shortestSide / dpr;
  return shortestDp >= kTabletShortestSide;
}
