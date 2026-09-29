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
  Future<void> unregisterTokenFromBackend();
  void setWebViewController(InAppWebViewController controller);
}

class PushNotificationServiceImpl implements PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SecureStorageService _secureStorage;

  InAppWebViewController? _webViewController;
  String? _lastToken;
  bool _backendRegistrationInProgress = false;

  final StreamController<String> _redirectController =
      StreamController<String>.broadcast();

  PushNotificationServiceImpl({required SecureStorageService secureStorage})
    : _secureStorage = secureStorage;

  @override
  void setWebViewController(InAppWebViewController controller) {
    _webViewController = controller;
    final token = _lastToken;
    if (token != null) {
      _syncTokenWithWebView(token);
      unawaited(_registerTokenWithCurrentWebSession(token));
    }
  }

  Future<String?> _getAuthIdTokenFromWebView() async {
    final controller = _webViewController;
    if (controller == null) return null;
    try {
      final raw = await controller.evaluateJavascript(
        source: """
          (async function() {
            try {
              if (typeof window.__getFirebaseAuthToken === 'function') {
                return await window.__getFirebaseAuthToken();
              }
              if (window.firebase && window.firebase.auth && window.firebase.auth().currentUser) {
                return await window.firebase.auth().currentUser.getIdToken(true);
              }
              for (var i = 0; i < localStorage.length; i++) {
                var key = localStorage.key(i);
                if (key.indexOf('firebase:authUser') !== -1) {
                  var item = JSON.parse(localStorage.getItem(key));
                  if (item && item.stsTokenManager && item.stsTokenManager.accessToken) {
                    return item.stsTokenManager.accessToken;
                  }
                }
              }
            } catch(e) {}
            return null;
          })();
        """,
      );
      if (raw == null) return null;
      final value = raw.toString().trim();
      if (value.isEmpty || value == 'null' || value == 'undefined') return null;
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is String && decoded.isNotEmpty) return decoded;
        } catch (_) {}
      }
      return value;
    } catch (e) {
      AppLogger.w('Could not read Auth ID Token from WebView: $e');
      return null;
    }
  }

  Future<String?> _getActiveSessionIdFromWebView() async {
    final controller = _webViewController;
    if (controller == null) return null;
    try {
      final raw = await controller.evaluateJavascript(
        source: "window.localStorage.getItem('active_session_id')",
      );
      if (raw == null) return null;
      final value = raw.toString().trim();
      if (value.isEmpty || value == 'null' || value == 'undefined') return null;
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is String && decoded.isNotEmpty) return decoded;
        } catch (_) {}
      }
      return value;
    } catch (e) {
      AppLogger.w('Could not read active session ID from WebView: $e');
      return null;
    }
  }

  Future<void> _registerTokenWithCurrentWebSession(String token) async {
    if (_backendRegistrationInProgress) return;
    _backendRegistrationInProgress = true;
    try {
      const delays = <Duration>[
        Duration(milliseconds: 300),
        Duration(milliseconds: 700),
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 3),
        Duration(seconds: 5),
        Duration(seconds: 7),
        Duration(seconds: 10),
      ];
      for (var attempt = 0; attempt < delays.length; attempt++) {
        final idToken = await _getAuthIdTokenFromWebView();
        final sessionId = await _getActiveSessionIdFromWebView();

        if (idToken == null || idToken.isEmpty) {
          await Future<void>.delayed(delays[attempt]);
          continue;
        }

        final uri = Uri.parse('${AppStrings.baseUrl}api/fcm/register');
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        };
        if (sessionId != null && sessionId.isNotEmpty) {
          headers['X-Session-ID'] = sessionId;
        }

        final response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode({
            'token': token,
            'platform': Platform.isAndroid ? 'android' : 'ios',
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          AppLogger.i('FCM token registered successfully for active web session.');
          return;
        }
        AppLogger.w('Active-session FCM registration attempt ${attempt + 1} returned ${response.statusCode}.');
        await Future<void>.delayed(delays[attempt]);
      }
    } catch (e) {
      AppLogger.w('Active-session FCM registration failed: $e');
    } finally {
      _backendRegistrationInProgress = false;
    }
  }

  Future<void> _syncTokenWithWebView(String token) async {
    if (_webViewController != null) {
      try {
        AppLogger.i('Syncing FCM token via WebView JavaScript Bridge...');
        await _webViewController!.evaluateJavascript(
          source:
              """
          if (typeof window !== 'undefined') {
            window.__fcmToken = '$token';
            if (window.__syncFcmToken) {
              window.__syncFcmToken('$token');
            }
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
      await _initializeLocalNotifications();
      _setupFirebaseListeners();

      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationPayload(initialMessage.data);
      }

      _fcm.onTokenRefresh.listen((newToken) async {
        AppLogger.i('FCM token refreshed');
        await _secureStorage.write('fcm_token', newToken);
        await sendTokenToBackend(newToken);
      });

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
  Future<void> unregisterTokenFromBackend() async {
    try {
      final token = await getFcmToken();
      final idToken = await _getAuthIdTokenFromWebView();

      if (token != null && idToken != null && idToken.isNotEmpty) {
        try {
          final uri = Uri.parse('${AppStrings.baseUrl}api/fcm/unregister');
          final headers = <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          };
          final sessionId = await _getActiveSessionIdFromWebView();
          if (sessionId != null && sessionId.isNotEmpty) {
            headers['X-Session-ID'] = sessionId;
          }

          final response = await http.delete(
            uri,
            headers: headers,
            body: jsonEncode({'token': token}),
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            AppLogger.i('Native FCM token successfully unregistered from backend /api/fcm/unregister');
          } else {
            AppLogger.w('Backend /api/fcm/unregister returned status code: ${response.statusCode}');
          }
        } catch (netErr) {
          AppLogger.w('Native FCM token unregister network exception: $netErr');
        }
      }

      await _secureStorage.delete('fcm_token');
      _lastToken = null;
      AppLogger.i('FCM token association cleared locally');
    } catch (e) {
      AppLogger.e('Error during native unregisterTokenFromBackend', e);
    }
  }

  @override
  Future<void> sendTokenToBackend(String token) async {
    try {
      _lastToken = token;
      await _registerTokenWithCurrentWebSession(token);
      await _syncTokenWithWebView(token);
      AppLogger.i('FCM token cached and synchronized');
    } catch (e) {
      AppLogger.e('Error syncing FCM token', e);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');

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
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AppLogger.i(
        'Foreground notification received: ${message.notification?.title}',
      );

      if (_webViewController != null) {
        try {
          _webViewController!.evaluateJavascript(source: """
            (function() {
              try {
                if (typeof window !== 'undefined' && window.dispatchEvent) {
                  window.dispatchEvent(new CustomEvent('app-refresh'));
                }
              } catch(e) {}
            })();
          """);
        } catch (_) {}
      }

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
              priority: Priority.max,
              icon: android?.smallIcon ?? '@drawable/ic_notification',
              playSound: true,
              enableVibration: true,
              fullScreenIntent: true,
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
      final String type = (data['type'] ?? data['notification_type'] ?? '')
          .toString()
          .toLowerCase()
          .trim();

      String redirectPath = '';

      if (type == 'session_revoked') {
        AppLogger.w('Received session_revoked push notification. Clearing local token state.');
        _secureStorage.delete('fcm_token');
        _lastToken = null;
        _redirectController.add('notifications');
        return;
      }

      final txRef = (data['txRef'] ?? data['reference'] ?? data['transactionReference'] ?? '').toString().trim();
      if (txRef.isNotEmpty && RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(txRef)) {
        redirectPath = '?txRef=$txRef';
      } else {
        switch (type) {
          case 'deposit':
            redirectPath = 'deposit';
            break;
          case 'transaction':
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
            final rawPath = (data['path'] ?? '').toString().trim();
            redirectPath = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
            break;
        }
      }

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
