import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:wallet/core/security/biometrics_service.dart';
import 'package:wallet/core/security/secure_storage_service.dart';

class MockLocalAuthentication implements LocalAuthentication {
  final bool mockCanCheckBiometrics;
  final bool mockIsDeviceSupported;
  final List<BiometricType> mockEnrolledBiometrics;

  MockLocalAuthentication({
    this.mockCanCheckBiometrics = true,
    this.mockIsDeviceSupported = true,
    this.mockEnrolledBiometrics = const [BiometricType.fingerprint],
  });

  @override
  Future<bool> get canCheckBiometrics async => mockCanCheckBiometrics;

  @override
  Future<bool> isDeviceSupported() async => mockIsDeviceSupported;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      mockEnrolledBiometrics;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    return true;
  }

  @override
  Future<bool> stopAuthentication() async => true;
}

class MockSecureStorageService implements SecureStorageService {
  final Map<String, String> storage = {};

  @override
  Future<void> write(String key, String value) async {
    storage[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return storage[key];
  }

  @override
  Future<void> delete(String key) async {
    storage.remove(key);
  }

  @override
  Future<bool> hasKey(String key) async {
    return storage.containsKey(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BiometricsServiceImpl Comprehensive Unit Tests', () {
    late MockSecureStorageService mockStorage;

    setUp(() {
      mockStorage = MockSecureStorageService();
    });

    test('1. Enrollment success: native crypto auth + native key creation sets biometric_enabled=true', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': true};
        }
        if (methodCall.method == 'createBiometricKey') {
          return true;
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final enabled = await service.enableBiometricLogin(mockStorage);

      expect(enabled, isTrue);
      expect(mockStorage.storage['biometric_enabled'], 'true');
    });

    test('2. Enrollment authentication failure keeps biometric_enabled unset', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': false, 'error': 'Failed', 'code': 'AUTHENTICATION_FAILED'};
        }
        if (methodCall.method == 'deleteBiometricKey') {
          return true;
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final enabled = await service.enableBiometricLogin(mockStorage);

      expect(enabled, isFalse);
      expect(mockStorage.storage['biometric_enabled'], isNull);
    });

    test('3. Credential creation failure keeps biometric_enabled unset', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': true};
        }
        if (methodCall.method == 'createBiometricKey') {
          return false; // Native OS KeyStore / Keychain failed
        }
        if (methodCall.method == 'deleteBiometricKey') {
          return true;
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final enabled = await service.enableBiometricLogin(mockStorage);

      expect(enabled, isFalse);
      expect(mockStorage.storage['biometric_enabled'], isNull);
    });

    test('4. Native biometric cancellation returns false without throwing', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': false, 'error': 'User canceled', 'code': 'USER_CANCELED'};
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final result = await service.authenticate();
      expect(result, isFalse);
    });

    test('5. Native authentication lockout error returns false', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': false, 'error': 'Too many attempts', 'code': 'LOCKOUT'};
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final result = await service.authenticate();
      expect(result, isFalse);
    });

    test('6 & 7. Invalidated / missing native credential deletes biometric state', () async {
      mockStorage.storage['biometric_enabled'] = 'true';
      bool deleteNativeKeyCalled = false;

      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'validateBiometricKey') {
          return false; // Key invalidated by OS
        }
        if (methodCall.method == 'deleteBiometricKey') {
          deleteNativeKeyCalled = true;
          return true;
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final isValid = await service.validateBiometricEnrollment(mockStorage);

      expect(isValid, isFalse);
      expect(mockStorage.storage['biometric_enabled'], isNull);
      expect(deleteNativeKeyCalled, isTrue);
    });

    test('8. Biometric disabled state returns false when biometric_enabled is false/unset', () async {
      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final isValid = await service.validateBiometricEnrollment(mockStorage);
      expect(isValid, isFalse);
    });

    test('9. Successful biometric login returns true', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': true};
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final result = await service.authenticate();
      expect(result, isTrue);
    });

    test('10. Failed biometric login returns false', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': false, 'error': 'Failed', 'code': 'AUTHENTICATION_FAILED'};
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final result = await service.authenticate();
      expect(result, isFalse);
    });
  });
}
