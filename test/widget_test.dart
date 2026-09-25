import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/core/constants/app_strings.dart';

void main() {
  test('EGlobalWalletApp configuration and strings', () {
    expect(AppStrings.appName, equals('E-Global Pay'));
    expect(AppStrings.packageIdentifier, equals('com.eglobal.wallet'));
  });
}
