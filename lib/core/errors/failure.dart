abstract class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => message;
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection']);
}

class WebLoadFailure extends Failure {
  final int? statusCode;
  const WebLoadFailure(super.message, {this.statusCode});
}

class WebCrashFailure extends Failure {
  const WebCrashFailure([super.message = 'The page crashed or failed to load']);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'An unexpected error occurred']);
}
