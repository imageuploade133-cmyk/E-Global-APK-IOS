import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:wallet/core/security/biometrics_service.dart';
import 'package:wallet/core/security/secure_storage_service.dart';

class MockLocalAuthentication implements LocalAuthentication {
  final bool mockCanCheckBiometrics;
  final bool mockIsDeviceSupported;
  final List<BiometricType> mockEnrolledBiometrics;
  final bool mockAuthenticateResult;

  MockLocalAuthentication({
    this.mockCanCheckBiometrics = true,
    this.mockIsDeviceSupported = true,
    this.mockEnrolledBiometrics = const [BiometricType.fingerprint],
    this.mockAuthenticateResult = true,
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
    return mockAuthenticateResult;
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

  group('BiometricsServiceImpl Enrollment Flow Tests', () {
    late MockSecureStorageService mockStorage;

    setUp(() {
      mockStorage = MockSecureStorageService();
    });

    test('1. Successful biometric authentication + native credential creation sets biometric_enabled=true', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'createBiometricKey') {
          return true;
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication(
        mockCanCheckBiometrics: true,
        mockIsDeviceSupported: true,
        mockEnrolledBiometrics: [BiometricType.fingerprint],
        mockAuthenticateResult: true,
      );
      final service = BiometricsServiceImpl(auth: mockAuth);

      final enabled = await service.enableBiometricLogin(mockStorage);

      expect(enabled, isTrue);
      expect(mockStorage.storage['biometric_enabled'], 'true');
    });

    test('2. Native credential creation failure keeps biometric_enabled unset', () async {
      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'createBiometricKey') {
          return false; // Native OS KeyStore/Keychain failed to generate key
        }
        if (methodCall.method == 'deleteBiometricKey') {
          return true;
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication(
        mockCanCheckBiometrics: true,
        mockIsDeviceSupported: true,
        mockEnrolledBiometrics: [BiometricType.fingerprint],
        mockAuthenticateResult: true,
      );
      final service = BiometricsServiceImpl(auth: mockAuth);

      final enabled = await service.enableBiometricLogin(mockStorage);

      expect(enabled, isFalse);
      expect(mockStorage.storage['biometric_enabled'], isNull);
    });

    test('3. Invalidated native credential deletes biometric state', () async {
      mockStorage.storage['biometric_enabled'] = 'true';
      bool deleteNativeKeyCalled = false;

      const channel = MethodChannel('com.eglobal.wallet/biometric_key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'validateBiometricKey') {
          return false; // Key invalidated because biometrics re-enrolled
        }
        if (methodCall.method == 'deleteBiometricKey') {
          deleteNativeKeyCalled = true;
          return true;
        }
        return null;
      });

      final mockAuth = MockLocalAuthentication(
        mockCanCheckBiometrics: true,
        mockIsDeviceSupported: true,
        mockEnrolledBiometrics: [BiometricType.fingerprint],
      );
      final service = BiometricsServiceImpl(auth: mockAuth);

      final isValid = await service.validateBiometricEnrollment(mockStorage);

      expect(isValid, isFalse);
      expect(mockStorage.storage['biometric_enabled'], isNull);
      expect(deleteNativeKeyCalled, isTrue);
    });

    test('4. Normal fallback returns false when biometric_enabled is false/unset', () async {
      final mockAuth = MockLocalAuthentication(
        mockCanCheckBiometrics: true,
        mockIsDeviceSupported: true,
        mockEnrolledBiometrics: [BiometricType.fingerprint],
      );
      final service = BiometricsServiceImpl(auth: mockAuth);

      final isValid = await service.validateBiometricEnrollment(mockStorage);
      expect(isValid, isFalse);
    });
  });
}
