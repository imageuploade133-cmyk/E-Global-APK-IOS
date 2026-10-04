import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';
import '../constants/app_strings.dart';

abstract class BiometricsService {
  Future<bool> isBiometricsAvailable();
  Future<List<BiometricType>> getAvailableBiometrics();
  Future<bool> authenticate();
  Future<bool> createBiometricCredential();
  Future<bool> enableBiometricLogin(SecureStorageService secureStorage);
  Future<bool> validateBiometricEnrollment(SecureStorageService secureStorage);
  Future<void> invalidateBiometricState(SecureStorageService secureStorage);
}

class BiometricsServiceImpl implements BiometricsService {
  final LocalAuthentication _auth;
  final MethodChannel _biometricChannel;

  BiometricsServiceImpl({
    LocalAuthentication? auth,
    MethodChannel? biometricChannel,
  })  : _auth = auth ?? LocalAuthentication(),
        _biometricChannel =
            biometricChannel ?? const MethodChannel('com.eglobal.wallet/biometric_key');

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
  Future<bool> createBiometricCredential() async {
    try {
      final bool created =
          await _biometricChannel.invokeMethod<bool>('createBiometricKey') ??
              false;
      return created;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> enableBiometricLogin(SecureStorageService secureStorage) async {
    final bool available = await isBiometricsAvailable();
    if (!available) {
      await invalidateBiometricState(secureStorage);
      return false;
    }

    final bool authenticated = await authenticate();
    if (!authenticated) {
      await invalidateBiometricState(secureStorage);
      return false;
    }

    final bool credentialCreated = await createBiometricCredential();
    if (!credentialCreated) {
      await invalidateBiometricState(secureStorage);
      return false;
    }

    await secureStorage.write(AppStrings.biometricKey, 'true');
    return true;
  }

  @override
  Future<bool> validateBiometricEnrollment(
      SecureStorageService secureStorage) async {
    final bool available = await isBiometricsAvailable();
    if (!available) {
      await invalidateBiometricState(secureStorage);
      return false;
    }

    final String? isEnabledStr =
        await secureStorage.read(AppStrings.biometricKey);
    final bool isEnabled = isEnabledStr == 'true';

    if (!isEnabled) {
      return false;
    }

    try {
      final bool isValidNativeKey = await _biometricChannel
              .invokeMethod<bool>('validateBiometricKey') ??
          false;

      if (!isValidNativeKey) {
        // Platform KeyStore / Keychain invalidated key because biometric enrollment changed
        await invalidateBiometricState(secureStorage);
        return false;
      }

      return true;
    } catch (e) {
      await invalidateBiometricState(secureStorage);
      return false;
    }
  }

  @override
  Future<void> invalidateBiometricState(
      SecureStorageService secureStorage) async {
    try {
      await secureStorage.delete(AppStrings.biometricKey);
      await _biometricChannel.invokeMethod<bool>('deleteBiometricKey');
    } catch (_) {}
  }
}
