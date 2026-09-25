import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet/main.dart';
import 'package:wallet/core/services/core_providers.dart';
import 'package:wallet/core/services/push_notification_service.dart';

class FakePushNotificationService implements PushNotificationService {
  @override
  Stream<String> get onNotificationRedirectStream => const Stream.empty();

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Future<void> sendTokenToBackend(String token) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermission() async {}

  @override
  Future<String?> getFcmToken() async => null;

  @override
  void setWebViewController(dynamic controller) {}

  @override
  Future<void> unregisterTokenFromBackend() async {}
}

void main() {
  testWidgets('Initial route builds correctly and mounts the app', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(
            FakePushNotificationService(),
          ),
        ],
        child: const EGlobalWalletApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1600));

    // Verify EGlobalWalletApp mounts successfully
    expect(find.byType(EGlobalWalletApp), findsOneWidget);
  });
}
