import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

abstract class BiometricsService {
  Future<bool> isBiometricsAvailable();
  Future<bool> authenticate();
}

class BiometricsServiceImpl implements BiometricsService {
  final LocalAuthentication _auth;

  BiometricsServiceImpl({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  @override
  Future<bool> isBiometricsAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Authenticate to access E-Global Pay securely',
      );
    } on PlatformException {
      return false;
    }
  }
}
