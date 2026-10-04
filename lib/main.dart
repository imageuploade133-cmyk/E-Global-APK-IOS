import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/utils/logger.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/services/core_providers.dart';
import 'core/constants/app_strings.dart';
import 'core/security/biometrics_service.dart';
import 'core/security/secure_storage_service.dart';
import 'features/auth/presentation/screens/permissions_onboarding_screen.dart';
import 'features/auth/presentation/screens/biometric_login_screen.dart';
import 'features/wallet_webview/presentation/screens/webview_screen.dart';
import 'features/security/developer_mode_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    final FlutterLocalNotificationsPlugin localNotifications =
        FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('ic_notification');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await localNotifications.initialize(initSettings);

    final notification = message.notification;
    final data = message.data;

    final String title = notification?.title ??
        (data['title']?.toString()) ??
        'E-Global Pay';
    final String body = notification?.body ??
        (data['body'] ?? data['message'] ?? '') .toString();

    // Firebase Android SDK automatically displays system notifications when message.notification != null.
    // To prevent duplicate notifications, only show local notification for data-only push messages.
    if (notification == null && body.isNotEmpty) {
      String smallIcon = 'ic_notification';
      final customIcon = data['smallIcon']?.toString();
      if (customIcon != null && customIcon.isNotEmpty) {
        smallIcon = customIcon.replaceFirst('@drawable/', '');
      }

      await localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'eglobal_wallet_high_channel',
            'E-Global Wallet Notifications',
            channelDescription:
                'This channel is used for important wallet updates.',
            importance: Importance.max,
            priority: Priority.max,
            icon: smallIcon,
            playSound: true,
            enableVibration: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(data),
      );
    }
  } catch (e) {
    AppLogger.e('Error handling background push notification message', e);
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
      Permission.storage,
      Permission.photos,
    ]) {
      final status = await permission.status;
      if (!(status.isGranted || status.isLimited || status.isRestricted)) {
        requiredPermissionsGranted = false;
        break;
      }
    }

    if (completed || requiredPermissionsGranted) {
      if (!completed && requiredPermissionsGranted) {
        await storage.write(onboardingKey, 'true');
      }

      final biometricEnabledStr = await storage.read(AppStrings.biometricKey);
      final biometricEnabled = biometricEnabledStr == 'true';

      if (biometricEnabled) {
        final biometrics = BiometricsServiceImpl();
        final isValidBiometric =
            await biometrics.validateBiometricEnrollment(storage);
        if (isValidBiometric) {
          initialRoute = '/biometric_login';
        } else {
          initialRoute = '/webview';
        }
      } else {
        initialRoute = '/webview';
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPushNotificationsOnStartup();
    });
  }

  void _initPushNotificationsOnStartup() {
    try {
      final pushService = ref.read(pushNotificationServiceProvider);
      pushService.initialize();
    } catch (e) {
      AppLogger.e('Failed to initialize pushNotificationServiceProvider on app startup', e);
    }
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
