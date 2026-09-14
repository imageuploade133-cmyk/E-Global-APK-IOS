import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/core/constants/app_strings.dart';

void main() {
  test('AppStrings.savedEmailKey is correctly defined', () {
    expect(AppStrings.savedEmailKey, 'remembered_user_email');
  });

  test('AppStrings.isTrustedWalletOrigin validates URLs correctly', () {
    expect(
      AppStrings.isTrustedWalletOrigin(
        Uri.parse('https://e-global-197077.vercel.app/login'),
      ),
      isTrue,
    );
    expect(
      AppStrings.isTrustedWalletOrigin(
        Uri.parse('http://e-global-197077.vercel.app/login'),
      ),
      isFalse,
    );
    expect(
      AppStrings.isTrustedWalletOrigin(
        Uri.parse('https://malicious-domain.com/login'),
      ),
      isFalse,
    );
  });
}
