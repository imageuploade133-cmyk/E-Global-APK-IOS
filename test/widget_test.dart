import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet/main.dart';

void main() {
  testWidgets('Splash screen has the app title and loading indicator', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: EGlobalWalletApp()));

    // Initial state verification
    expect(find.text('E-Global Wallet'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
