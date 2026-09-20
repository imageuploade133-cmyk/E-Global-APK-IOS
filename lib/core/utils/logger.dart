import 'package:flutter/foundation.dart';

class AppLogger {
  AppLogger._();

  static void debug(String message, {String? tag}) {
    if (kDebugMode) {
      debugPrint('[$tag ?? "APP"] $message');
    }
  }

  static void info(String message, {String? tag}) {
    debugPrint('ℹ [$tag ?? "APP"] $message');
  }

  static void warning(String message, {String? tag}) {
    debugPrint('⚠ [$tag ?? "APP"] $message');
  }

  static void error(String message, {String? tag, Object? error}) {
    debugPrint('✕ [$tag ?? "APP"] $message${error != null ? ' → $error' : ''}');
  }
}
