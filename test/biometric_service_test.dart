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

    test('validateBiometricEnrollment saves initial signature and returns true', () async {
      final mockAuth = MockLocalAuthentication(
        mockEnrolledBiometrics: [BiometricType.fingerprint],
      );
      final service = BiometricsServiceImpl(auth: mockAuth);
      final mockStorage = MockSecureStorageService();

      final isValid = await service.validateBiometricEnrollment(mockStorage);
      expect(isValid, isTrue);
      expect(mockStorage.storage['biometric_enrolled_signature_v1'], 'fingerprint');
    });

    test('validateBiometricEnrollment invalidates state if enrolled biometrics change', () async {
      final mockStorage = MockSecureStorageService();
      mockStorage.storage['biometric_enabled'] = 'true';
      mockStorage.storage['biometric_enrolled_signature_v1'] = 'fingerprint';

      final mockAuthChanged = MockLocalAuthentication(
        mockEnrolledBiometrics: [BiometricType.face],
      );
      final service = BiometricsServiceImpl(auth: mockAuthChanged);

      final isValid = await service.validateBiometricEnrollment(mockStorage);
      expect(isValid, isFalse);
      expect(mockStorage.storage['biometric_enabled'], isNull);
      expect(mockStorage.storage['biometric_enrolled_signature_v1'], isNull);
    });
  });
}
