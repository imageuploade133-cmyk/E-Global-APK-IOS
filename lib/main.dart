import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'features/security/developer_mode_screen.dart';
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

  var initialRoute = '/permissions';
  try {
    const onboardingKey = 'eglobal_permissions_onboarding_completed_v1';
    final storage = SecureStorageServiceImpl();
    final completed = await storage.read(onboardingKey) == 'true';

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

class EGlobalWalletApp extends ConsumerStatefulWidget {
  final String initialRoute;

  const EGlobalWalletApp({super.key, required this.initialRoute});

  @override
  ConsumerState<EGlobalWalletApp> createState() => _EGlobalWalletAppState();
}

class _EGlobalWalletAppState extends ConsumerState<EGlobalWalletApp>
    with WidgetsBindingObserver {
  bool _isDevMode = false;
  Timer? _devModeTimer;
  static const _securityChannel = MethodChannel('com.eglobal.wallet/security');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDevMode();
    // Continuous monitoring loop while app is active
    _devModeTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkDevMode();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _devModeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDevMode();
    }
  }

  Future<void> _checkDevMode() async {
    try {
      final bool isDev = await _securityChannel.invokeMethod<bool>('isDeveloperModeEnabled') ?? false;
      if (mounted && _isDevMode != isDev) {
        setState(() {
          _isDevMode = isDev;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'E-Global Pay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        if (_isDevMode) {
          return DeveloperModeScreen(onRecheck: _checkDevMode);
        }
        return child ?? const SizedBox.shrink();
      },
      initialRoute: widget.initialRoute,
      routes: {
        '/webview': (context) => const WebviewScreen(),
        '/permissions': (context) => const PermissionsOnboardingScreen(),
        '/biometric_login': (context) => const BiometricLoginScreen(),
      },
    );
  }
}
