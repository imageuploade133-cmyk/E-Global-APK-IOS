import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet/main.dart';

void main() {
  testWidgets('Initial route builds correctly and mounts the app', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: EGlobalWalletApp()));

    // Verify InitialRouteHandler exists
    expect(find.byType(InitialRouteHandler), findsOneWidget);
  });
}
