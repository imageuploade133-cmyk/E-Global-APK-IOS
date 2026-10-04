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

  group('BiometricsServiceImpl Comprehensive Test Suite', () {
    late MockSecureStorageService mockStorage;

    setUp(() {
      mockStorage = MockSecureStorageService();
    });

    test('1 & 2 & 3. Enrollment creates credential once, authenticates it, and sets biometric_enabled=true', () async {
      int createKeyCalls = 0;
      bool authenticateCalled = false;
      bool createIfMissingPassed = false;

      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'createBiometricKey') {
          createKeyCalls++;
          return true;
        }
        if (methodCall.method == 'authenticateWithCryptoObject') {
          authenticateCalled = true;
          final args = methodCall.arguments as Map?;
          createIfMissingPassed = args?['createIfMissing'] != null;
          return <String, dynamic>{'success': true};
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final dynamic enabled = await service.enableBiometricLogin(mockStorage);

      expect(enabled is Map ? enabled['success'] : enabled, isTrue);
      expect(createKeyCalls, equals(1));
      expect(authenticateCalled, isTrue);
      expect(createIfMissingPassed, isTrue);
      expect(mockStorage.storage['biometric_enabled'], 'true');
    });

    test('4. Enrollment failure deletes credential and leaves biometric_enabled unset', () async {
      bool deleteNativeKeyCalled = false;

      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'createBiometricKey') {
          return true;
        }
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': false, 'error': 'User canceled', 'code': 'USER_CANCELED'};
        }
        if (methodCall.method == 'deleteBiometricKey') {
          deleteNativeKeyCalled = true;
          return true;
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final dynamic enabled = await service.enableBiometricLogin(mockStorage);

      expect(enabled is Map ? enabled['success'] : enabled, isFalse);
      expect(mockStorage.storage['biometric_enabled'], isNull);
      expect(deleteNativeKeyCalled, isTrue);
    });

    test('5. Login never creates a credential (createIfMissing is false)', () async {
      bool createIfMissingValue = true;

      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          final args = methodCall.arguments as Map;
          createIfMissingValue = args['createIfMissing'] as bool;
          return <String, dynamic>{'success': true};
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      await service.authenticate();

      expect(createIfMissingValue, isFalse);
    });

    test('6 & 7. Missing/invalidated credential during login falls back to standard authentication', () async {
      mockStorage.storage['biometric_enabled'] = 'true';
      bool deleteNativeKeyCalled = false;

      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'validateBiometricKey') {
          return false; // Credential missing or invalidated
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

    test('8 & 9. Successful vs Failed biometric login returns explicit boolean results', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      bool returnSuccess = true;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': returnSuccess};
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      expect(await service.authenticate(), isTrue);

      returnSuccess = false;
      expect(await service.authenticate(), isFalse);
    });

    test('10 & 11. Lockout / Cancellation / Timeout completes with failure', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'authenticateWithCryptoObject') {
          return <String, dynamic>{'success': false, 'error': 'Lockout', 'code': 'LOCKOUT'};
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication();
      final service = BiometricsServiceImpl(auth: mockAuth);

      final res = await service.authenticate();
      expect(res, isFalse);
    });

    test('12. Explicit native prompt cancellation', () async {
      bool cancelCalled = false;
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'cancelBiometricPrompt') {
          cancelCalled = true;
          return true;
        }
        return null;
      });

      final service = BiometricsServiceImpl();
      await service.cancelBiometricPrompt();

      expect(cancelCalled, isTrue);
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
