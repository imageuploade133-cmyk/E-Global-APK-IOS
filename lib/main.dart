import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/utils/logger.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/presentation/screens/permissions_onboarding_screen.dart';
import 'features/auth/presentation/screens/biometric_login_screen.dart';
import 'features/wallet_webview/presentation/screens/webview_screen.dart';
import 'core/security/secure_storage_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    AppLogger.e('Background Firebase Messaging initialization skipped', e);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    AppLogger.e(
      'Firebase initialization skipped or failed. Ensure configuration files are present.',
      e,
    );
  }

  // Resolve the startup route before Flutter renders the first screen so a user
  // who already completed permissions never sees the onboarding page again.
  // The onboarding screen remains the safety fallback if the marker is absent.
  var initialRoute = '/permissions';
  try {
    const onboardingKey = 'eglobal_permissions_onboarding_completed_v1';
    final storage = SecureStorageServiceImpl();
    final completed = await storage.read(onboardingKey) == 'true';

    // Migration-safe: older installs may already have all required
    // permissions granted even if the completion marker was not persisted.
    bool requiredPermissionsGranted = true;
    for (final permission in <Permission>[
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
    ]) {
      final status = await permission.status;
      if (!(status.isGranted || status.isLimited || status.isRestricted)) {
        requiredPermissionsGranted = false;
        break;
      }
    }

    if (completed || requiredPermissionsGranted) {
      initialRoute = '/webview';
      if (!completed && requiredPermissionsGranted) {
        await storage.write(onboardingKey, 'true');
      }
    }
  } catch (e) {
    AppLogger.e('Failed to read permissions onboarding state; using safe fallback.', e);
  }

  runApp(
    ProviderScope(child: EGlobalWalletApp(initialRoute: initialRoute)),
  );
}

class EGlobalWalletApp extends ConsumerWidget {
  final String initialRoute;

  const EGlobalWalletApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'E-Global Pay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      initialRoute: initialRoute,
      routes: {
        '/webview': (context) => const WebviewScreen(),
        '/permissions': (context) => const PermissionsOnboardingScreen(),
        '/biometric_login': (context) => const BiometricLoginScreen(),
      },
    );
  }
}
