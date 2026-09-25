import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet/main.dart';

void main() {
  testWidgets('Initial route builds correctly and mounts the app', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: EGlobalWalletApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1600));

    // Verify EGlobalWalletApp mounts successfully
    expect(find.byType(EGlobalWalletApp), findsOneWidget);
  });
}
