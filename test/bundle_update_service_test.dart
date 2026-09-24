import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/core/services/bundle_update_service.dart';

void main() {
  group('BundleUpdateService Unit Tests', () {
    test('isVersionNewer compares semantic versions correctly', () {
      expect(BundleUpdateService.isVersionNewer('1.0.1', '1.0.0'), isTrue);
      expect(BundleUpdateService.isVersionNewer('1.10.0', '1.9.0'), isTrue);
      expect(BundleUpdateService.isVersionNewer('2.0.0', '1.99.99'), isTrue);

      expect(BundleUpdateService.isVersionNewer('1.0.0', '1.0.0'), isFalse);
      expect(BundleUpdateService.isVersionNewer('1.0.0', '1.0.1'), isFalse);
      expect(BundleUpdateService.isVersionNewer('1.9.0', '1.10.0'), isFalse);
    });

    test('RemoteBundleManifest parses json correctly', () {
      final json = {
        'bundleVersion': '1.0.1',
        'bundleUrl': 'https://e-global-197077.vercel.app/mobile-bundles/1.0.1/bundle.zip',
        'sha256': 'a1b2c3d4e5f6',
        'size': 123456,
        'minAppVersion': '1.0.0',
      };

      final manifest = RemoteBundleManifest.fromJson(json);
      expect(manifest.bundleVersion, equals('1.0.1'));
      expect(manifest.bundleUrl, equals('https://e-global-197077.vercel.app/mobile-bundles/1.0.1/bundle.zip'));
      expect(manifest.sha256, equals('a1b2c3d4e5f6'));
      expect(manifest.size, equals(123456));
    });
  });
}
