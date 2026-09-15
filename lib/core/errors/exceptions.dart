class AppException implements Exception {
  final String message;
  final dynamic originalError;
  const AppException(this.message, {this.originalError});

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException([super.message = 'No internet connection']);
}

class WebViewLoadException extends AppException {
  final int? statusCode;
  const WebViewLoadException(
    super.message, {
    super.originalError,
    this.statusCode,
  });
}
