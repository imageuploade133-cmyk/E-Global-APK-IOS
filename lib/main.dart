import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_colors.dart';
import 'core/constants/app_strings.dart';
import 'core/services/connectivity_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'features/offline/offline_screen.dart';
import 'features/wallet_webview/presentation/screens/webview_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ProviderScope(
      child: EGlobalWalletApp(),
    ),
  );
}

/// Root app widget. Handles startup splash, initial connectivity check,
/// and switches between the offline screen and the main WebView.
class EGlobalWalletApp extends ConsumerStatefulWidget {
  const EGlobalWalletApp({super.key});

  @override
  ConsumerState<EGlobalWalletApp> createState() => _EGlobalWalletAppState();
}

class _EGlobalWalletAppState extends ConsumerState<EGlobalWalletApp> {
  bool _isAppReady = false;
  bool _isOnline = true; // optimistic — will be updated by the check

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    AppLogger.info('App starting up...', tag: 'App');

    // Immediately check connectivity so we can block the app if offline
    final connected = await ConnectivityService.hasConnection();
    AppLogger.info(
      'Initial connectivity check: ${connected ? "online" : "offline"}',
      tag: 'App',
    );

    if (mounted) {
      setState(() {
        _isAppReady = true;
        _isOnline = connected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show splash while the connectivity check is in flight
    if (!_isAppReady) {
      return const SplashScreen();
    }

    // Once ready, choose the home screen based on connectivity
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: _isOnline
          ? const WebviewScreen()
          : OfflineScreen(onRetry: _retryFromSplash),
    );
  }

  Future<void> _retryFromSplash() async {
    final connected = await ConnectivityService.hasConnection();
    if (mounted) {
      setState(() {
        _isOnline = connected;
      });
    }
  }
}

/// Minimal splash shown during startup connectivity check.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                size: 44,
                color: AppColors.onPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppStrings.appName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 8),
            const CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
