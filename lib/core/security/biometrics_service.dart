import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';
import '../constants/app_strings.dart';

abstract class BiometricsService {
  Future<bool> isBiometricsAvailable();
  Future<List<BiometricType>> getAvailableBiometrics();
  Future<String> getPrimaryBiometricType();
  Future<bool> authenticate({String title, String subtitle, bool createIfMissing});
  Future<Map<String, dynamic>> authenticateWithResult({String title, String subtitle, bool createIfMissing});
  Future<bool> createBiometricCredential();
  Future<bool> enableBiometricLogin(SecureStorageService secureStorage);
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
      if (!canCheck && !isDeviceSupported) {
        return false;
      }
      final List<BiometricType> available = await getAvailableBiometrics();
      return available.isNotEmpty || isDeviceSupported;
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
  Future<String> getPrimaryBiometricType() async {
    final List<BiometricType> types = await getAvailableBiometrics();
    if (types.contains(BiometricType.face)) {
      return 'faceid';
    }
    return 'fingerprint';
  }

  @override
  Future<Map<String, dynamic>> authenticateWithResult({
    String? title,
    String? subtitle,
    bool createIfMissing = true,
  }) async {
    final String type = await getPrimaryBiometricType();
    final String resolvedTitle = title ?? (type == 'faceid' ? 'Face ID Verification' : 'Your Fingerprint');
    final String resolvedSubtitle = subtitle ?? (type == 'faceid' 
        ? 'Scan your face to verify your identity' 
        : 'Touch fingerprint sensor or move finger across scanner');

    try {
      final Map<dynamic, dynamic>? res =
          await _biometricChannel.invokeMethod<Map<dynamic, dynamic>>(
        'authenticateWithCryptoObject',
        <String, dynamic>{
          'title': resolvedTitle,
          'subtitle': resolvedSubtitle,
          'createIfMissing': createIfMissing,
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          cancelBiometricPrompt();
          return <dynamic, dynamic>{'success': false, 'error': 'Timeout', 'code': 'TIMEOUT'};
        },
      );

      if (res != null) {
        final bool success = res['success'] == true;
        final String? error = res['error']?.toString();
        final String? code = res['code']?.toString();

        if (success || code == 'USER_CANCELED' || code == 'LOCKOUT' || code == 'TIMEOUT' || code == 'NONE_ENROLLED') {
          return {
            'success': success,
            'error': error,
            'code': code,
          };
        }
      }
    } catch (_) {}

    try {
      final bool didAuth = await _auth.authenticate(
        localizedReason: resolvedTitle,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return {'success': didAuth, 'error': null, 'code': didAuth ? 'SUCCESS' : 'USER_CANCELED'};
    } catch (e) {
      final String errStr = e.toString();
      if (errStr.toLowerCase().contains('lockout') || errStr.toLowerCase().contains('too many')) {
        return {'success': false, 'error': 'Too many attempts. Please try again later.', 'code': 'LOCKOUT'};
      }
      return {'success': false, 'error': errStr, 'code': 'ERROR'};
    }
  }

  @override
  Future<bool> authenticate({
    String? title,
    String? subtitle,
    bool createIfMissing = true,
  }) async {
    final res = await authenticateWithResult(
      title: title,
      subtitle: subtitle,
      createIfMissing: createIfMissing,
    );
    return res['success'] == true;
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

    final bool credentialCreated = await createBiometricCredential();
    if (!credentialCreated) {
      await invalidateBiometricState(secureStorage);
      return false;
    }

    final bool authenticated = await authenticate(
      createIfMissing: true,
    );

    if (!authenticated) {
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
