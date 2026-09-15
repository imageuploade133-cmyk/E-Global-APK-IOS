class AppException implements Exception {
  final String message;
  final dynamic originalError;
  constAppException(this.message, {this.originalError});

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  constNetworkException([String message = 'No internet connection'])
      : super(message);
}

class WebViewLoadException extends AppException {
  final int? statusCode;
  constWebViewLoadException(
    super.message, {
    super.originalError,
    this.statusCode,
  });
}
