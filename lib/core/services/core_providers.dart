import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../security/secure_storage_service.dart';
import '../security/biometrics_service.dart';
import '../services/connectivity_service.dart';
import '../services/permission_service.dart';
import '../services/push_notification_service.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageServiceImpl();
});

final biometricServiceProvider = Provider<BiometricsService>((ref) {
  return BiometricsServiceImpl();
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityServiceImpl();
});

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionServiceImpl();
});

final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  return PushNotificationServiceImpl(
    secureStorage: ref.watch(secureStorageProvider),
  );
});
