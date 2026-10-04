import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';
import '../constants/app_strings.dart';

abstract class BiometricsService {
  Future<bool> isBiometricsAvailable();
  Future<List<BiometricType>> getAvailableBiometrics();
  Future<bool> authenticate();
  Future<bool> validateBiometricEnrollment(SecureStorageService secureStorage);
  Future<void> invalidateBiometricState(SecureStorageService secureStorage);
}

class BiometricsServiceImpl implements BiometricsService {
  final LocalAuthentication _auth;

  BiometricsServiceImpl({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  @override
  Future<bool> isBiometricsAvailable() async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isDeviceSupported) {
        return false;
      }
      final List<BiometricType> available = await getAvailableBiometrics();
      return available.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Authenticate to access E-Global Pay securely',
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> validateBiometricEnrollment(SecureStorageService secureStorage) async {
    final bool available = await isBiometricsAvailable();
    if (!available) {
      await invalidateBiometricState(secureStorage);
      return false;
    }

    final List<BiometricType> currentTypes = await getAvailableBiometrics();
    final String currentSig = currentTypes.map((t) => t.name).join(',');

    const sigKey = 'biometric_enrolled_signature_v1';
    final String? savedSig = await secureStorage.read(sigKey);

    if (savedSig == null) {
      await secureStorage.write(sigKey, currentSig);
      return true;
    } else if (savedSig != currentSig) {
      await invalidateBiometricState(secureStorage);
      return false;
    }

    return true;
  }

  @override
  Future<void> invalidateBiometricState(SecureStorageService secureStorage) async {
    await secureStorage.delete(AppStrings.biometricKey);
    await secureStorage.delete('biometric_enrolled_signature_v1');
  }
}
