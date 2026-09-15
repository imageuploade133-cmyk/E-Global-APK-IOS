abstract class Failure {
  final String message;
  constFailure(this.message);

  @override
  String toString() => message;
}

class NetworkFailure extends Failure {
  constNetworkFailure([super.message = 'No internet connection']);
}

class WebLoadFailure extends Failure {
  final int? statusCode;
  constWebLoadFailure(super.message, {this.statusCode});
}

class WebCrashFailure extends Failure {
  constWebCrashFailure([super.message = 'The page crashed or failed to load']);
}

class UnknownFailure extends Failure {
  constUnknownFailure([super.message = 'An unexpected error occurred']);
}
