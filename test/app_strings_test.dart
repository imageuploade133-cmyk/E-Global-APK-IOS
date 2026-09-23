import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/core/constants/app_strings.dart';

void main() {
  group('AppStrings & Origin Validation Tests', () {
    test('bundleVersion is defined authoritative version 1.0.0', () {
      expect(AppStrings.bundleVersion, equals('1.0.0'));
    });

    test('isTrustedWalletOrigin trusts exact localhost local bundle origin', () {
      expect(AppStrings.isTrustedWalletOrigin(Uri.parse('http://localhost:8080/')), isTrue);
      expect(AppStrings.isTrustedWalletOrigin(Uri.parse('http://127.0.0.1:8080/')), isTrue);
    });

    test('isTrustedWalletOrigin trusts exact production Vercel origin', () {
      expect(AppStrings.isTrustedWalletOrigin(Uri.parse('https://e-global-197077.vercel.app/')), isTrue);
      expect(AppStrings.isTrustedWalletOrigin(Uri.parse('https://e-global-197077.vercel.app/auth/login')), isTrue);
    });

    test('isTrustedWalletOrigin rejects untrusted origins and substring spoofing', () {
      expect(AppStrings.isTrustedWalletOrigin(Uri.parse('http://e-global-197077.vercel.app/')), isFalse);
      expect(AppStrings.isTrustedWalletOrigin(Uri.parse('https://evil-e-global-197077.vercel.app/')), isFalse);
      expect(AppStrings.isTrustedWalletOrigin(Uri.parse('http://localhost.evil.com/')), isFalse);
      expect(AppStrings.isTrustedWalletOrigin(Uri.parse('https://example.com/')), isFalse);
    });
  });
}
