import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/constants/app_strings.dart';
import 'core/services/core_providers.dart';
import 'features/auth/presentation/screens/biometric_login_screen.dart';
import 'features/wallet_webview/presentation/screens/webview_screen.dart';
import 'features/offline/presentation/screens/offline_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set the app to true immersive full-screen mode immediately on boot
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const ProviderScope(child: EGlobalWalletApp()));
}

class EGlobalWalletApp extends ConsumerWidget {
  const EGlobalWalletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'E-Global Wallet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      initialRoute: '/',
      routes: {
        '/': (context) => const InitialRouteHandler(),
        '/biometric_login': (context) => const BiometricLoginScreen(),
        '/webview': (context) => const WebviewScreen(),
        '/offline': (context) => const OfflineScreen(),
      },
    );
  }
}

/// Instant transparent routing handler that completely bypasses any splash screen.
/// It instantly determines connection and biometric states, rendering the target screen immediately.
class InitialRouteHandler extends ConsumerStatefulWidget {
  const InitialRouteHandler({super.key});

  @override
  ConsumerState<InitialRouteHandler> createState() => _InitialRouteHandlerState();
}

class _InitialRouteHandlerState extends ConsumerState<InitialRouteHandler> {
  Widget? _targetScreen;

  @override
  void initState() {
    super.initState();
    _determineInitialRoute();
  }

  Future<void> _determineInitialRoute() async {
    final connectivity = ref.read(connectivityServiceProvider);
    final secureStorage = ref.read(secureStorageProvider);
    final biometrics = ref.read(biometricServiceProvider);

    final isConnected = await connectivity.isConnected;
    if (!isConnected) {
      if (mounted) {
        setState(() {
          _targetScreen = const OfflineScreen();
        });
      }
      return;
    }

    final biometricEnabledStr = await secureStorage.read(AppStrings.biometricKey);
    final biometricEnabled = biometricEnabledStr == 'true';
    final hasBiometrics = await biometrics.isBiometricsAvailable();

    if (mounted) {
      setState(() {
        if (biometricEnabled && hasBiometrics) {
          _targetScreen = const BiometricLoginScreen();
        } else {
          _targetScreen = const WebviewScreen();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build a tiny centered spinner inside a transparent frame only while checking (usually less than 1 frame).
    return _targetScreen ?? const Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.shrink(),
    );
  }
}
