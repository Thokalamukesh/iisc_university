import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

void kioskLog(
  Object? message, {
  String tag = 'SELFX',
  Object? error,
  StackTrace? stackTrace,
}) {
  final text = message?.toString() ?? 'null';
  if (!kDebugMode) return;

  debugPrint('[$tag] $text');
  developer.log(
    text,
    name: tag,
    error: error,
    stackTrace: stackTrace,
  );
}

void kioskLogError(
  Object message, {
  String tag = 'SELFX',
  Object? error,
  StackTrace? stackTrace,
}) {
  kioskLog(
    message,
    tag: tag,
    error: error,
    stackTrace: stackTrace,
  );
}
