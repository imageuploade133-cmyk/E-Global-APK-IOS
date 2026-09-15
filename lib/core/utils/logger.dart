import 'dart:developer' as developer;

class AppLogger {
  static void d(String message) {
    assert(() {
      developer.log('[DEBUG] $message', name: 'E-Global Pay');
      return true;
    }());
  }

  static void e(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      '[ERROR] $message',
      name: 'E-Global Wallet',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void i(String message) {
    developer.log('[INFO] $message', name: 'E-Global Pay');
  }

  static void w(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      '[WARN] $message',
      name: 'E-Global Pay',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
