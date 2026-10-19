import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/core/constants/app_strings.dart';

void main() {
  test('AppStrings.savedEmailKey is correctly defined', () {
    expect(AppStrings.savedEmailKey, 'remembered_user_email');
  });

  test('AppStrings.isTrustedWalletOrigin validates URLs correctly', () {
    expect(
      AppStrings.isTrustedWalletOrigin(
        Uri.parse('https://eglobalpayfram.emakemrnd.com.ng/login'),
      ),
      isTrue,
    );
    expect(
      AppStrings.isTrustedWalletOrigin(
        Uri.parse('http://eglobalpayfram.emakemrnd.com.ng/login'),
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
