import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/notification_service.dart';
import 'features/auth/presentation/screens/biometric_login_screen.dart';
import 'features/auth/presentation/screens/permissions_onboarding_screen.dart';
import 'features/wallet_webview/presentation/screens/webview_screen.dart';
import 'features/offline/presentation/screens/offline_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notifications FIRST (before app starts)
  await NotificationService().initialize();
  
  // Set the app to true immersive full-screen mode immediately on boot
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Start with webview as default - all initialization is now deferred
  // Permissions, connectivity, and biometric checks happen asynchronously
  // without blocking the app startup
  const String initialRoute = '/webview';

  runApp(const ProviderScope(
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
      title: 'E-Global Pay',
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
