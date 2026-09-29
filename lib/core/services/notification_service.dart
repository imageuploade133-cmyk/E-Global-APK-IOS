import 'dart:async';
import 'push_notification_service.dart';

/// Legacy compatibility wrapper delegating to authoritative PushNotificationService.
/// Prevents duplicate FCM initialization, foreground listeners, or background isolates.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  PushNotificationService? _pushService;

  void attachPushNotificationService(PushNotificationService service) {
    _pushService = service;
  }

  Stream<int> get badgeCountStream =>
      _pushService?.badgeCountStream ?? const Stream<int>.empty();

  int get badgeCount => _pushService?.badgeCount ?? 0;

  bool get isInitialized => true;

  Future<void> initialize() async {
    if (_pushService != null) {
      await _pushService!.initialize();
    }
  }

  Future<void> associateTokenWithUser(String userId) async {
    final token = await _pushService?.getFcmToken();
    if (token != null && _pushService != null) {
      await _pushService!.sendTokenToBackend(token);
    }
  }

  Future<void> clearUserAssociation() async {
    if (_pushService != null) {
      await _pushService!.unregisterTokenFromBackend();
    }
  }

  Future<void> setBadgeCount(int count) async {
    if (_pushService != null) {
      await _pushService!.setBadgeCount(count);
    }
  }

  Future<void> resetBadgeCount() async {
    if (_pushService != null) {
      await _pushService!.resetBadgeCount();
    }
  }

  Future<void> clearAllNotifications() async {
    if (_pushService != null) {
      await _pushService!.resetBadgeCount();
    }
  }

  Future<String?> getCurrentToken() async {
    return await _pushService?.getFcmToken();
  }

  void dispose() {}
}
