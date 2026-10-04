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
  bool throwOnRead = false;

  @override
  Future<void> write(String key, String value) async {
    storage[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    if (throwOnRead && key == 'biometric_enrolled_token_v1') {
      throw Exception('KeyPermanentlyInvalidatedException: Biometrics changed');
    }
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
  group('BiometricsServiceImpl Tests', () {
    test('isBiometricsAvailable returns true when biometrics are supported and enrolled', () async {
      final mockAuth = MockLocalAuthentication(
        mockCanCheckBiometrics: true,
        mockIsDeviceSupported: true,
        mockEnrolledBiometrics: [BiometricType.fingerprint],
      );
      final service = BiometricsServiceImpl(auth: mockAuth);

      final available = await service.isBiometricsAvailable();
      expect(available, isTrue);
    });

    test('isBiometricsAvailable returns false when no biometrics are enrolled', () async {
      final mockAuth = MockLocalAuthentication(
        mockCanCheckBiometrics: true,
        mockIsDeviceSupported: true,
        mockEnrolledBiometrics: [],
      );
      final service = BiometricsServiceImpl(auth: mockAuth);

      final available = await service.isBiometricsAvailable();
      expect(available, isFalse);
    });

    test('validateBiometricEnrollment saves initial token when biometric is enabled', () async {
      final mockAuth = MockLocalAuthentication(
        mockEnrolledBiometrics: [BiometricType.fingerprint],
      );
      final service = BiometricsServiceImpl(auth: mockAuth);
      final mockStorage = MockSecureStorageService();
      mockStorage.storage['biometric_enabled'] = 'true';

      final isValid = await service.validateBiometricEnrollment(mockStorage);
      expect(isValid, isTrue);
      expect(mockStorage.storage['biometric_enrolled_token_v1'], 'valid_fingerprint');
    });

    test('validateBiometricEnrollment returns false when biometric_enabled is not true', () async {
      final mockAuth = MockLocalAuthentication(
        mockEnrolledBiometrics: [BiometricType.fingerprint],
      );
      final service = BiometricsServiceImpl(auth: mockAuth);
      final mockStorage = MockSecureStorageService();

      final isValid = await service.validateBiometricEnrollment(mockStorage);
      expect(isValid, isFalse);
    });

    test('validateBiometricEnrollment invalidates state if enrolled biometrics change type', () async {
      final mockStorage = MockSecureStorageService();
      mockStorage.storage['biometric_enabled'] = 'true';
      mockStorage.storage['biometric_enrolled_token_v1'] = 'valid_fingerprint';

      final mockAuthChanged = MockLocalAuthentication(
        mockEnrolledBiometrics: [BiometricType.face],
      );
      final service = BiometricsServiceImpl(auth: mockAuthChanged);

      final isValid = await service.validateBiometricEnrollment(mockStorage);
      expect(isValid, isFalse);
      expect(mockStorage.storage['biometric_enabled'], isNull);
      expect(mockStorage.storage['biometric_enrolled_token_v1'], isNull);
    });

    test('validateBiometricEnrollment invalidates state if platform secure key is invalidated', () async {
      final mockStorage = MockSecureStorageService();
      mockStorage.storage['biometric_enabled'] = 'true';
      mockStorage.storage['biometric_enrolled_token_v1'] = 'valid_fingerprint';
      mockStorage.throwOnRead = true;

      final mockAuth = MockLocalAuthentication(
        mockEnrolledBiometrics: [BiometricType.fingerprint],
      );
      final service = BiometricsServiceImpl(auth: mockAuth);

      final isValid = await service.validateBiometricEnrollment(mockStorage);
      expect(isValid, isFalse);
      expect(mockStorage.storage['biometric_enabled'], isNull);
      expect(mockStorage.storage['biometric_enrolled_token_v1'], isNull);
    });
  });
}
