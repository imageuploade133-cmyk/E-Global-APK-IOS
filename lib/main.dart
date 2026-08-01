import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/constants/app_strings.dart';
import 'core/security/secure_storage_service.dart';
import 'core/security/biometrics_service.dart';
import 'core/services/connectivity_service.dart';
import 'features/auth/presentation/screens/biometric_login_screen.dart';
import 'features/auth/presentation/screens/permissions_onboarding_screen.dart';
import 'features/wallet_webview/presentation/screens/webview_screen.dart';
import 'features/offline/presentation/screens/offline_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set the app to true immersive full-screen mode immediately on boot
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Dynamic permission checklist based on OS platform for absolute compatibility
  final List<Permission> requiredPermissions = Platform.isAndroid
      ? [
          Permission.camera,
          Permission.microphone,
          Permission.locationWhenInUse,
          Permission.storage,
          Permission.notification,
        ]
      : [
          Permission.camera,
          Permission.microphone,
          Permission.locationWhenInUse,
          Permission.photos,
          Permission.notification,
        ];

  bool hasAllPermissions = true;
  for (final permission in requiredPermissions) {
    final status = await permission.status;
    final isGranted = status.isGranted || status.isLimited || status.isRestricted;
    if (!isGranted) {
      hasAllPermissions = false;
      break;
    }
  }

  String initialRoute = '/webview';

  if (!hasAllPermissions) {
    initialRoute = '/permissions';
  } else {
    final connectivity = ConnectivityServiceImpl();
    final isConnected = await connectivity.isConnected;

    if (!isConnected) {
      initialRoute = '/offline';
    } else {
      final secureStorage = SecureStorageServiceImpl();
      final biometricEnabledStr = await secureStorage.read(AppStrings.biometricKey);
      final biometricEnabled = biometricEnabledStr == 'true';

      final biometrics = BiometricsServiceImpl();
      final hasBiometrics = await biometrics.isBiometricsAvailable();

      if (biometricEnabled && hasBiometrics) {
        initialRoute = '/biometric_login';
      }
    }
  }

  runApp(ProviderScope(
    child: EGlobalWalletApp(initialRoute: initialRoute),
  ));
}

class EGlobalWalletApp extends ConsumerWidget {
  final String initialRoute;

  const EGlobalWalletApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Note: ProviderScope is required to watch the themeProvider
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'E-Global Wallet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      initialRoute: initialRoute,
      routes: {
        '/permissions': (context) => const PermissionsOnboardingScreen(),
        '/biometric_login': (context) => const BiometricLoginScreen(),
        '/webview': (context) => const WebviewScreen(),
        '/offline': (context) => const OfflineScreen(),
      },
    );
  }
}
