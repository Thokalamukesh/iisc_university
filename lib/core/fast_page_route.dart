import 'package:flutter/material.dart';

/// Small route transition used by the customer web flow.
///
/// Flutter web route changes feel slow when every screen uses the default
/// material transition because it animates more frames while large menu widgets
/// are building. This fade keeps navigation lightweight and lets the next page
/// paint sooner on mobile browsers and low-end devices.
Route<T> fastPageRoute<T>(
  WidgetBuilder builder, {
  bool maintainState = true,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 120),
    reverseTransitionDuration: const Duration(milliseconds: 90),
    maintainState: maintainState,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
