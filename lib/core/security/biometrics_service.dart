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

  static const String _biometricTokenKey = 'biometric_enrolled_token_v1';

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

    final String? isEnabledStr = await secureStorage.read(AppStrings.biometricKey);
    final bool isEnabled = isEnabledStr == 'true';

    if (!isEnabled) {
      return false;
    }

    try {
      final List<BiometricType> currentTypes = await getAvailableBiometrics();
      final String currentSig = currentTypes.map((t) => t.name).join(',');

      final String? storedToken = await secureStorage.read(_biometricTokenKey);

      if (storedToken == null) {
        // Initial token generation when biometric login is active
        await secureStorage.write(_biometricTokenKey, 'valid_$currentSig');
        return true;
      }

      if (storedToken != 'valid_$currentSig') {
        // Biometric types or platform key changed
        await invalidateBiometricState(secureStorage);
        return false;
      }

      return true;
    } catch (e) {
      // Platform security key invalidation (e.g. KeyPermanentlyInvalidatedException or Keychain invalidation)
      await invalidateBiometricState(secureStorage);
      return false;
    }
  }

  @override
  Future<void> invalidateBiometricState(SecureStorageService secureStorage) async {
    try {
      await secureStorage.delete(AppStrings.biometricKey);
      await secureStorage.delete(_biometricTokenKey);
    } catch (_) {}
  }
}
