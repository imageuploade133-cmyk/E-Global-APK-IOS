import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';
import '../constants/app_strings.dart';

abstract class BiometricsService {
  Future<bool> isBiometricsAvailable();
  Future<List<BiometricType>> getAvailableBiometrics();
  Future<bool> authenticate({String title, String subtitle, bool createIfMissing});
  Future<bool> createBiometricCredential();
  Future<dynamic> enableBiometricLogin(SecureStorageService secureStorage);
  Future<bool> validateBiometricEnrollment(SecureStorageService secureStorage);
  Future<void> invalidateBiometricState(SecureStorageService secureStorage);
  Future<void> cancelBiometricPrompt();
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
  Future<bool> authenticate({
    String title = 'Biometric Authentication',
    String subtitle = 'Touch sensor to verify fingerprint',
    bool createIfMissing = false,
  }) async {
    try {
      final Map<dynamic, dynamic>? res =
          await _biometricChannel.invokeMethod<Map<dynamic, dynamic>>(
        'authenticateWithCryptoObject',
        <String, dynamic>{
          'title': title,
          'subtitle': subtitle,
          'createIfMissing': createIfMissing,
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          cancelBiometricPrompt();
          return <dynamic, dynamic>{'success': false, 'error': 'Timeout', 'code': 'TIMEOUT'};
        },
      );

      return res?['success'] == true;
    } catch (_) {
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
  Future<dynamic> enableBiometricLogin(SecureStorageService secureStorage) async {
    final bool available = await isBiometricsAvailable();
    if (!available) {
      await invalidateBiometricState(secureStorage);
      return {
        'success': false,
        'message': 'No enrolled biometrics found. Please set up a fingerprint or Face ID in device settings.'
      };
    }

    final bool credentialCreated = await createBiometricCredential();
    if (!credentialCreated) {
      await invalidateBiometricState(secureStorage);
      return {
        'success': false,
        'message': 'Unable to initialize secure biometric key on device.'
      };
    }

    final bool authenticated = await authenticate(
      title: 'Enable Biometric Login',
      subtitle: 'Touch sensor to verify fingerprint',
      createIfMissing: false,
    );

    if (!authenticated) {
      await invalidateBiometricState(secureStorage);
      return {
        'success': false,
        'message': 'Biometric verification was cancelled or failed.'
      };
    }

    await secureStorage.write(AppStrings.biometricKey, 'true');
    return {
      'success': true,
      'message': 'Biometric login enabled successfully.'
    };
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

  @override
  Future<void> cancelBiometricPrompt() async {
    try {
      await _biometricChannel.invokeMethod<bool>('cancelBiometricPrompt');
    } catch (_) {}
  }
}
