import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/utils/logger.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/presentation/screens/permissions_onboarding_screen.dart';
import 'features/auth/presentation/screens/biometric_login_screen.dart';
import 'features/auth/presentation/screens/native_login_screen.dart';
import 'features/shell/presentation/screens/main_shell_screen.dart';
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

/// Firebase and other service initialization must never block Flutter's first
/// frame. Blocking before runApp can leave the native splash visible indefinitely.
Future<void> _initializeFirebaseInBackground() async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 8));
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    AppLogger.e(
      'Firebase initialization skipped or timed out. Ensure configuration files are present.',
      e,
    );
  }
}

void main() {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Keep the native splash visible until the wallet WebView has actually
  // rendered its first successful page. This prevents a white Flutter frame
  // from appearing between native startup and the local wallet bundle.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Never await Firebase, secure storage, permissions, connectivity, or
  // network work before runApp().
  unawaited(_initializeFirebaseInBackground());

  runApp(
    const ProviderScope(
      child: EGlobalWalletApp(),
    ),
  );
}

class EGlobalWalletApp extends ConsumerWidget {
  const EGlobalWalletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'E-Global Pay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const StartupRouter(),
      routes: {
        '/home': (context) => const MainShellScreen(),
        '/login': (context) => const NativeLoginScreen(),
        '/webview': (context) => const WebviewScreen(),
        '/permissions': (context) => const PermissionsOnboardingScreen(),
        '/biometric_login': (context) => const BiometricLoginScreen(),
      },
    );
  }
}

/// Resolves the first user-facing screen natively on the first frame.
class StartupRouter extends StatefulWidget {
  const StartupRouter({super.key});

  @override
  State<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<StartupRouter> {
  String? _route;

  static const _onboardingKey =
      'eglobal_permissions_onboarding_completed_v1';

  @override
  void initState() {
    super.initState();
    // Do not remove the native splash here. The WebView screen removes it
    // only after the local wallet page reaches a successful load state.
    unawaited(_resolveStartupRoute());
  }

  Future<void> _resolveStartupRoute() async {
    try {
      final storage = SecureStorageServiceImpl();

      final completedFuture = storage.read(_onboardingKey);
      final permissionFutures = <Future<PermissionStatus>>[
        Permission.camera.status,
        Permission.microphone.status,
        Permission.locationWhenInUse.status,
      ];

      final values = await Future.wait<dynamic>([
        completedFuture,
        ...permissionFutures,
      ]).timeout(const Duration(milliseconds: 1500));

      final completed = values[0] == 'true';
      final statuses = values
          .skip(1)
          .cast<PermissionStatus>()
          .toList(growable: false);

      final requiredPermissionsGranted = statuses.every(
        (status) =>
            status.isGranted || status.isLimited || status.isRestricted,
      );

      if (!completed && !requiredPermissionsGranted) {
        if (mounted) {
          setState(() => _route = '/permissions');
        }
        return;
      }

      // Check Firebase Auth or local secure token for session state safely
      User? currentUser;
      try {
        currentUser = FirebaseAuth.instance.currentUser;
      } catch (_) {}

      final savedCredentials = await storage.read('secure_wallet_credentials');

      if (currentUser != null || (savedCredentials != null && savedCredentials.isNotEmpty)) {
        if (mounted) {
          setState(() => _route = '/home');
        }
      } else {
        if (mounted) {
          setState(() => _route = '/login');
        }
      }
    } catch (e) {
      AppLogger.e(
        'Startup route resolution timed out; mounting login screen.',
        e,
      );
      if (mounted) {
        setState(() => _route = '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;

    if (route == '/permissions') {
      return const PermissionsOnboardingScreen();
    }

    if (route == '/home') {
      return const MainShellScreen();
    }

    if (route == '/login') {
      return const NativeLoginScreen();
    }

    if (route == '/webview') {
      return const WebviewScreen();
    }

    // Instant Flutter frame
    return const Scaffold(
      backgroundColor: Colors.white,
      body: ColoredBox(color: Colors.white),
    );
  }
}
