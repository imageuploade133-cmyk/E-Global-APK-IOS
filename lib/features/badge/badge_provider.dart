import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/core_providers.dart';
import '../../core/services/push_notification_service.dart';

/// Provider for notification badge count
final badgeCountProvider = StateNotifierProvider<BadgeCountNotifier, int>((ref) {
  final pushService = ref.watch(pushNotificationServiceProvider);
  return BadgeCountNotifier(pushService);
});

class BadgeCountNotifier extends StateNotifier<int> {
  final PushNotificationService _pushService;

  BadgeCountNotifier(this._pushService) : super(0) {
    _init();
  }

  void _init() {
    state = _pushService.badgeCount;
    _pushService.badgeCountStream.listen((count) {
      state = count;
    });
  }

  /// Manually set badge count
  Future<void> setBadgeCount(int count) async {
    await _pushService.setBadgeCount(count);
    state = count < 0 ? 0 : count;
  }

  /// Reset badge count to zero (call when user reads notifications)
  Future<void> resetBadgeCount() async {
    await _pushService.resetBadgeCount();
    state = 0;
  }

  /// Increment badge count
  Future<void> incrementBadgeCount() async {
    await _pushService.incrementBadgeCount();
  }

  /// Get current badge count from persistent storage
  int get currentBadgeCount => state;
}
