import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../constants/app_strings.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../security/secure_storage_service.dart';
import '../utils/logger.dart';

abstract class PushNotificationService {
  Future<void> initialize();
  Future<void> requestPermission();
  Future<String?> getFcmToken();
  Stream<String> get onTokenRefresh;
  Stream<String> get onNotificationRedirectStream;
  Future<void> sendTokenToBackend(String token);
  void setWebViewController(InAppWebViewController controller);
}

class PushNotificationServiceImpl implements PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SecureStorageService _secureStorage;

  InAppWebViewController? _webViewController;
  String? _lastToken;

  // Stream controller to broadcast destination paths to the WebView
  final StreamController<String> _redirectController =
      StreamController<String>.broadcast();

  PushNotificationServiceImpl({required SecureStorageService secureStorage})
    : _secureStorage = secureStorage;

  @override
  void setWebViewController(InAppWebViewController controller) {
    _webViewController = controller;
    if (_lastToken != null) {
      _syncTokenWithWebView(_lastToken!);
    }
  }

  Future<void> _syncTokenWithWebView(String token) async {
    if (_webViewController != null) {
      try {
        AppLogger.i('Syncing FCM token via WebView JavaScript Bridge...');
        await _webViewController!.evaluateJavascript(
          source:
              """
          if (typeof window !== 'undefined' && window.__syncFcmToken) {
            window.__syncFcmToken('$token');
          }
        """,
        );
      } catch (e) {
        AppLogger.e('Error evaluating sync JS in WebView', e);
      }
    }
  }

  @override
  Stream<String> get onNotificationRedirectStream => _redirectController.stream;

  @override
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  @override
  Future<void> initialize() async {
    try {
      // 1. Initialize local notifications for foreground heads-up displays
      await _initializeLocalNotifications();

      // 2. Setup Firebase notification handlers
      _setupFirebaseListeners();

      // 3. Check and process initial message if app was launched from a terminated state
      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationPayload(initialMessage.data);
      }

      // 4. Automatically listen and securely persist/refresh FCM token
      _fcm.onTokenRefresh.listen((newToken) async {
        AppLogger.i('FCM token refreshed');
        await _secureStorage.write('fcm_token', newToken);
        await sendTokenToBackend(newToken);
      });

      // Fetch current token silently
      final currentToken = await getFcmToken();
      if (currentToken != null) {
        AppLogger.i('FCM token initialized');
        await sendTokenToBackend(currentToken);
      }
    } catch (e) {
      AppLogger.e('Error initializing PushNotificationService', e);
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      final NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        AppLogger.i('User granted notification permissions.');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        AppLogger.i('User granted provisional notification permissions.');
      } else {
        AppLogger.i(
          'User declined or has not accepted notification permissions.',
        );
      }
    } catch (e) {
      AppLogger.e('Error requesting notification permission', e);
    }
  }

  @override
  Future<String?> getFcmToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _secureStorage.write('fcm_token', token);
      }
      return token;
    } catch (e) {
      AppLogger.e('Error retrieving FCM Token', e);
      return await _secureStorage.read('fcm_token');
    }
  }

  @override
  Future<void> sendTokenToBackend(String token) async {
    try {
      _lastToken = token;

      // 1. Direct native HTTP registration to backend /api/fcm/register with Firebase ID token authentication
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final idToken = await user.getIdToken();
          final uri = Uri.parse('${AppStrings.baseUrl}api/fcm/register');
          final response = await http.post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'token': token, 'platform': Platform.isAndroid ? 'android' : 'ios'}),
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            AppLogger.i('Native FCM token successfully registered directly with backend /api/fcm/register');
          } else {
            AppLogger.w('Backend /api/fcm/register returned status code: ${response.statusCode}');
          }
        } else {
          AppLogger.i('No authenticated user active yet. FCM token cached until user login.');
        }
      } catch (netErr) {
        AppLogger.w('Direct native FCM token registration network exception: $netErr');
      }

      // 2. Synchronize token with WebView JS Bridge if WebView is active
      await _syncTokenWithWebView(token);
      AppLogger.i('FCM token cached and synchronized');
    } catch (e) {
      AppLogger.e('Error syncing FCM token', e);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

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

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null) {
          _handleNotificationPayloadWithString(payload);
        }
      },
    );

    // Create standard Android High Importance Channel for Heads-Up Notifications
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'eglobal_wallet_high_channel',
        'E-Global Wallet Notifications',
        description: 'This channel is used for important wallet updates.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  void _setupFirebaseListeners() {
    // 1. Listen to messages in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AppLogger.i(
        'Foreground notification received: ${message.notification?.title}',
      );

      final notification = message.notification;
      final android = message.notification?.android;

      if (notification != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'eglobal_wallet_high_channel',
              'E-Global Wallet Notifications',
              channelDescription:
                  'This channel is used for important wallet updates.',
              importance: Importance.max,
              priority: Priority.high,
              icon: android?.smallIcon ?? '@mipmap/ic_launcher',
              playSound: true,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: jsonEncode(message.data),
        );
      }
    });

    // 2. Listen to notification taps when app is in background but running
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      AppLogger.i(
        'Notification tapped from background state: ${message.notification?.title}',
      );
      _handleNotificationPayload(message.data);
    });
  }

  static const Set<String> _allowedRoutes = {
    'notifications',
    'deposit',
    'transfers',
    'airtime',
    'data',
    'electricity',
    'cable-tv',
    'orders',
    'kyc',
    'security',
  };

  void _handleNotificationPayload(Map<String, dynamic> data) {
    try {
      // Extract route or notification type to map to the correct WebView sub-path
      final String type = (data['type'] ?? data['notification_type'] ?? '')
          .toString()
          .toLowerCase()
          .trim();

      String redirectPath = '';

      switch (type) {
        case 'deposit':
          redirectPath = 'deposit';
          break;
        case 'transfer':
        case 'incoming transfer':
        case 'incoming_transfer':
          redirectPath = 'transfers';
          break;
        case 'airtime':
          redirectPath = 'airtime';
          break;
        case 'data':
          redirectPath = 'data';
          break;
        case 'electricity':
          redirectPath = 'electricity';
          break;
        case 'cable tv':
        case 'cable_tv':
        case 'cable':
          redirectPath = 'cable-tv';
          break;
        case 'order':
        case 'order updates':
        case 'order_updates':
          redirectPath = 'orders';
          break;
        case 'kyc':
          redirectPath = 'kyc';
          break;
        case 'security':
        case 'security alerts':
        case 'security_alerts':
          redirectPath = 'security';
          break;
        default:
          final txRef = (data['txRef'] ?? data['reference'] ?? data['transactionReference'] ?? '').toString().trim();
          if (txRef.isNotEmpty && RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(txRef)) {
            redirectPath = '?txRef=$txRef';
          } else {
            final rawPath = (data['path'] ?? '').toString().trim();
            final cleanPath = rawPath.startsWith('/')
                ? rawPath.substring(1)
                : rawPath;
            redirectPath = cleanPath;
          }
          final cleanPath = rawPath.startsWith('/')
              ? rawPath.substring(1)
              : rawPath;
          redirectPath = cleanPath;
          break;
      }

      // Enforce route allow-list validation to prevent arbitrary open redirects
      final routeToCheck = redirectPath.startsWith('?') ? redirectPath.split('?').first : redirectPath;
      if (routeToCheck.isNotEmpty && !_allowedRoutes.contains(routeToCheck)) {
        AppLogger.e(
          'Rejected untrusted notification route path: $redirectPath',
        );
        redirectPath = 'notifications';
      }

      _redirectController.add(redirectPath);
    } catch (e) {
      AppLogger.e('Error mapping notification payload', e);
    }
  }

  void _handleNotificationPayloadWithString(String payloadString) {
    try {
      final Map<String, dynamic> data =
          jsonDecode(payloadString) as Map<String, dynamic>;
      _handleNotificationPayload(data);
    } catch (e) {
      AppLogger.e('Error processing JSON payload: $payloadString', e);
    }
  }
}
