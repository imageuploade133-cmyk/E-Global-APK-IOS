abstract class Failure {
  final String message;
  const Failure(this.message);
}

class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

class BiometricFailure extends Failure {
  const BiometricFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}
