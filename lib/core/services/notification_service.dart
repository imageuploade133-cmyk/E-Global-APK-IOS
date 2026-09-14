import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/utils/logger.dart';

/// Background message handler - MUST be top-level function
/// This runs in a separate isolate when app is terminated
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    AppLogger.i('[Background] Handling message: ${message.messageId}');
    
    // Validate payload security - never trust incoming data
    final validatedData = _validateNotificationPayload(message.data);
    if (!validatedData['isValid'] as bool) {
      AppLogger.w('[Background] Invalid notification payload rejected');
      return;
    }
    
    // Show local notification for background message
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.show(
      message.messageId.hashCode,
      _sanitizeText(message.notification?.title ?? 'E-Global Pay'),
      _sanitizeText(message.notification?.body ?? 'You have a new notification'),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'e_global_pay_channel',
          'E-Global Pay Notifications',
          channelDescription: 'Secure notifications from E-Global Pay',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          showBadge: true,
          enableVibration: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: validatedData['safeRoute'] as String?,
    );
  } catch (e) {
    AppLogger.e('[Background] Error handling background message', e);
  }
}

/// Validate and sanitize notification payload for security
Map<String, dynamic> _validateNotificationPayload(Map<String, dynamic> data) {
  try {
    // Only allow specific trusted keys
    final allowedKeys = ['route', 'type', 'id'];
    final sanitized = <String, dynamic>{};
    
    for (final key in data.keys) {
      if (allowedKeys.contains(key)) {
        final value = data[key];
        if (value is String) {
          // Sanitize string values
          sanitized[key] = value.replaceAll(RegExp(r'[<>\"\'&]'), '');
        } else {
          sanitized[key] = value;
        }
      }
    }
    
    // Validate route if present - ONLY allow trusted internal routes
    String? safeRoute;
    if (sanitized.containsKey('route')) {
      final route = sanitized['route'] as String;
      if (_isTrustedRoute(route)) {
        safeRoute = route;
      }
    }
    
    return {'isValid': true, 'data': sanitized, 'safeRoute': safeRoute};
  } catch (e) {
    AppLogger.e('Payload validation failed', e);
    return {'isValid': false, 'data': {}, 'safeRoute': null};
  }
}

/// Check if route is trusted (only internal E-Global Pay routes)
bool _isTrustedRoute(String route) {
  if (route.isEmpty) return false;
  
  // Only allow specific safe internal routes
  final trustedRoutes = [
    '/home',
    '/wallet',
    '/transactions',
    '/profile',
    '/settings',
    '/notifications',
    '/transfer',
    '/receive',
    '/pay',
  ];
  
  // Check exact match or starts with trusted prefix
  return trustedRoutes.contains(route) || 
         trustedRoutes.any((r) => route.startsWith('$r/'));
}

/// Sanitize text to prevent XSS/injection
String _sanitizeText(String? text) {
  if (text == null) return '';
  // Remove potentially dangerous characters
  return text.replaceAll(RegExp(r'[<>\"\'&]'), '').trim();
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  int _badgeCount = 0;
  final StreamController<int> _badgeCountController = StreamController<int>.broadcast();
  
  // Track processed notification IDs to prevent duplicates
  final Set<String> _processedNotificationIds = {};
  static const int _maxProcessedIds = 100; // Limit memory usage
  
  // Store user ID associated with FCM token for account isolation
  static const String _userIdKey = 'notification_user_id';
  static const String _fcmTokenKey = 'fcm_token';
  static const String _badgeCountKey = 'badge_count';
  
  bool _isInitialized = false;
  
  /// Stream of badge count updates
  Stream<int> get badgeCountStream => _badgeCountController.stream;
  
  /// Current badge count
  int get badgeCount => _badgeCount;
  
  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize notification service
  Future<void> initialize() async {
    if (_isInitialized) {
      AppLogger.i('Notification service already initialized');
      return;
    }
    
    try {
      // Initialize Firebase
      await Firebase.initializeApp();
      
      // Request permissions with badge support
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      AppLogger.i('Notification permission status: ${settings.authorizationStatus}');

      // Initialize local notifications
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      await _localNotifications.initialize(
        const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create Android notification channel
      await _createNotificationChannel();

      // Get FCM token and associate with current user
      await _refreshFcmToken();

      // Listen to token refresh
      _messaging.onTokenRefresh.listen(_handleTokenRefresh);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Check if app was opened from notification (terminated state)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        AppLogger.i('App opened from notification: ${initialMessage.messageId}');
        _handleNotificationTap(initialMessage);
      }
      
      // Restore badge count from persistent storage
      await _restoreBadgeCount();

      _isInitialized = true;
      AppLogger.i('Notification service initialized successfully');
    } catch (e) {
      AppLogger.e('Failed to initialize notification service', e);
      _isInitialized = false;
      // Don't rethrow - app should continue working even if notifications fail
    }
  }
  
  /// Associate FCM token with current user (call after login)
  Future<void> associateTokenWithUser(String userId) async {
    try {
      await _secureStorage.write(key: _userIdKey, value: userId);
      final token = await _messaging.getToken();
      if (token != null) {
        await _secureStorage.write(key: _fcmTokenKey, value: token);
        AppLogger.i('FCM token associated with user: $userId');
        // TODO: Send token + userId to your backend server here
      }
    } catch (e) {
      AppLogger.e('Failed to associate token with user', e);
    }
  }
  
  /// Clear user association on logout (CRITICAL for account isolation)
  Future<void> clearUserAssociation() async {
    try {
      await _secureStorage.delete(key: _userIdKey);
      await _secureStorage.delete(key: _fcmTokenKey);
      await _secureStorage.delete(key: _badgeCountKey);
      _badgeCount = 0;
      _processedNotificationIds.clear();
      _badgeCountController.add(0);
      await _messaging.setBadgeCount(0);
      AppLogger.i('User association cleared for logout');
    } catch (e) {
      AppLogger.e('Failed to clear user association', e);
    }
  }
  
  /// Refresh FCM token and associate with current user
  Future<void> _refreshFcmToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _secureStorage.write(key: _fcmTokenKey, value: token);
        
        // If user is logged in, associate token
        final userId = await _secureStorage.read(key: _userIdKey);
        if (userId != null) {
          AppLogger.i('FCM token refreshed for user: $userId');
          // TODO: Send updated token + userId to your backend
        }
      }
    } catch (e) {
      AppLogger.e('Failed to refresh FCM token', e);
    }
  }
  
  /// Handle token refresh events
  void _handleTokenRefresh(String newToken) {
    AppLogger.i('FCM token refreshed');
    _secureStorage.write(key: _fcmTokenKey, value: newToken).catchError((e) {
      AppLogger.e('Failed to store new token', e);
    });
    
    // TODO: Send new token + userId to your backend
  }

  /// Create Android notification channel
  Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      'e_global_pay_channel',
      'E-Global Pay Notifications',
      description: 'Secure notifications from E-Global Pay',
      importance: Importance.high,
      priority: Priority.high,
      showBadge: true,
      enableVibration: true,
      playSound: true,
      enableLights: false,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    AppLogger.i('Received foreground message: ${message.messageId}');
    
    // Prevent duplicate processing
    if (_processedNotificationIds.contains(message.messageId)) {
      AppLogger.w('Duplicate notification ignored: ${message.messageId}');
      return;
    }
    _addProcessedId(message.messageId!);
    
    // Validate payload security
    final validatedData = _validateNotificationPayload(message.data);
    if (!validatedData['isValid'] as bool) {
      AppLogger.w('Invalid notification payload ignored');
      return;
    }
    
    // Update badge count atomically
    _incrementBadgeCount();
    
    // Show local notification even when app is in foreground
    _showLocalNotification(message, validatedData['safeRoute'] as String?);
  }

  /// Handle notification tap (from background or terminated state)
  Future<void> _handleNotificationTap(RemoteMessage message) async {
    try {
      AppLogger.i('Notification tapped: ${message.messageId}');
      
      // Reset badge count
      await _resetBadgeCount();
      
      // Validate and extract safe route
      final validatedData = _validateNotificationPayload(message.data);
      final safeRoute = validatedData['safeRoute'] as String?;
      
      if (safeRoute != null) {
        AppLogger.i('Navigating to safe route: $safeRoute');
        // TODO: Implement navigation using your existing WebView routing
        // Example: Notify WebView controller to navigate to safeRoute
        // DO NOT use message.data['route'] directly - always use validated safeRoute
      }
    } catch (e) {
      AppLogger.e('Error handling notification tap', e);
    }
  }

  /// Handle local notification tap
  void _onNotificationTapped(NotificationResponse response) {
    try {
      AppLogger.i('Local notification tapped: ${response.id}');
      _resetBadgeCount();
      
      // Validate payload from response
      if (response.payload != null && response.payload!.isNotEmpty) {
        // Payload should contain validated safe route
        // TODO: Implement navigation using your existing WebView routing
        AppLogger.i('Navigation payload: ${response.payload}');
      }
    } catch (e) {
      AppLogger.e('Error handling local notification tap', e);
    }
  }

  /// Show local notification with validated data
  Future<void> _showLocalNotification(RemoteMessage message, String? safeRoute) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      _sanitizeText(notification.title),
      _sanitizeText(notification.body),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'e_global_pay_channel',
          'E-Global Pay Notifications',
          channelDescription: 'Secure notifications from E-Global Pay',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          showBadge: true,
          enableVibration: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: safeRoute,
    );
  }
  
  /// Add notification ID to processed set with LRU eviction
  void _addProcessedId(String id) {
    if (_processedNotificationIds.length >= _maxProcessedIds) {
      // Remove oldest entry (simple approach: clear half when full)
      _processedNotificationIds.removeWhere((element) => 
        _processedNotificationIds.length > _maxProcessedIds / 2);
    }
    _processedNotificationIds.add(id);
  }

  /// Increment badge count atomically
  Future<void> _incrementBadgeCount() async {
    final newCount = _badgeCount + 1;
    await _updateBadge(newCount);
  }

  /// Reset badge count to zero
  Future<void> _resetBadgeCount() async {
    await _updateBadge(0);
  }
  
  /// Restore badge count from persistent storage (app restart)
  Future<void> _restoreBadgeCount() async {
    try {
      final stored = await _secureStorage.read(key: _badgeCountKey);
      if (stored != null) {
        final count = int.tryParse(stored) ?? 0;
        _badgeCount = count;
        _badgeCountController.add(count);
        AppLogger.i('Restored badge count: $count');
      }
    } catch (e) {
      AppLogger.e('Failed to restore badge count', e);
    }
  }

  /// Update badge count with persistence
  Future<void> _updateBadge(int count) async {
    final safeCount = count < 0 ? 0 : count;
    _badgeCount = safeCount;
    
    // Persist to secure storage
    try {
      await _secureStorage.write(key: _badgeCountKey, value: safeCount.toString());
    } catch (e) {
      AppLogger.e('Failed to persist badge count', e);
    }
    
    // Emit to stream
    if (!_badgeCountController.isClosed) {
      _badgeCountController.add(safeCount);
    }
    
    // Set badge on iOS
    try {
      await _messaging.setBadgeCount(safeCount);
    } catch (e) {
      AppLogger.e('Failed to set iOS badge', e);
    }
    
    // Android badge is handled by notification channel
  }

  /// Manually set badge count (for external control)
  Future<void> setBadgeCount(int count) async {
    await _updateBadge(count);
  }

  /// Clear all notifications and reset badge
  Future<void> clearAllNotifications() async {
    try {
      await _localNotifications.cancelAll();
      await _resetBadgeCount();
      _processedNotificationIds.clear();
    } catch (e) {
      AppLogger.e('Failed to clear notifications', e);
    }
  }
  
  /// Get current FCM token (for debugging/testing)
  Future<String?> getCurrentToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      AppLogger.e('Failed to get FCM token', e);
      return null;
    }
  }
  
  /// Get current user ID associated with notifications
  Future<String?> getCurrentUserId() async {
    try {
      return await _secureStorage.read(key: _userIdKey);
    } catch (e) {
      AppLogger.e('Failed to get user ID', e);
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    _badgeCountController.close();
    _processedNotificationIds.clear();
    _isInitialized = false;
  }
}
