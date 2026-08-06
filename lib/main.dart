import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/presentation/screens/permissions_onboarding_screen.dart';
import 'features/auth/presentation/screens/biometric_login_screen.dart';
import 'features/wallet_webview/presentation/screens/webview_screen.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Set the app to true immersive full-screen mode immediately on boot to remove system bars
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Set the system status bar and navigation bar to transparent with dark icons for a bleached, clean look.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  runApp(const ProviderScope(
    child: EGlobalWalletApp(initialRoute: '/permissions'),
  ));
}

class EGlobalWalletApp extends ConsumerWidget {
  final String initialRoute;

  const EGlobalWalletApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'E-Global Wallet',
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
