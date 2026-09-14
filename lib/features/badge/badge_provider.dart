import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/notification_service.dart';

/// Provider for notification badge count
final badgeCountProvider = StateNotifierProvider<BadgeCountNotifier, int>((ref) {
  return BadgeCountNotifier();
});

class BadgeCountNotifier extends StateNotifier<int> {
  BadgeCountNotifier() : super(0) {
    _init();
  }

  void _init() {
    // Listen to badge count updates from notification service
    NotificationService().badgeCountStream.listen((count) {
      state = count;
    });
  }

  /// Manually set badge count
  Future<void> setBadgeCount(int count) async {
    await NotificationService().setBadgeCount(count);
    state = count < 0 ? 0 : count;
  }

  /// Reset badge count to zero (call when user reads notifications)
  Future<void> resetBadgeCount() async {
    await NotificationService().setBadgeCount(0);
    state = 0;
  }

  /// Increment badge count
  Future<void> incrementBadgeCount() async {
    final newCount = state + 1;
    await NotificationService().setBadgeCount(newCount);
    state = newCount;
  }
  
  /// Get current badge count from persistent storage
  int get currentBadgeCount => state;
}
