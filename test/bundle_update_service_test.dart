import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/core/services/bundle_update_service.dart';
import 'package:wallet/core/constants/bundle_public_key.dart';

void main() {
  group('BundleUpdateService Tests', () {
    final service = BundleUpdateService();

    test('isVersionNewer correctly compares version strings', () {
      expect(service.isVersionNewer('1.0.1', '1.0.0'), true);
      expect(service.isVersionNewer('1.1.0', '1.0.1'), true);
      expect(service.isVersionNewer('2.0.0', '1.9.9'), true);

      expect(service.isVersionNewer('1.0.0', '1.0.0'), false);
      expect(service.isVersionNewer('1.0.0', '1.0.1'), false);
      expect(service.isVersionNewer('0.9.9', '1.0.0'), false);
    });

    test('verifyRsaSignature verifies valid manifest signature with BundlePublicKey', () {
      final manifestJson = {
        'bundleVersion': '1.0.1',
        'bundleUrl': 'https://e-global-197077.vercel.app/mobile-bundles/1.0.1/bundle.zip',
        'sha256': 'b836b3db74e61d782faf7e9c151d8b03ea14ad5f0beea68204374c8429935598',
        'size': 4188863,
        'signature': 'TAvCVN/yuRW5We3fxMcvJvgU8jYTY7YZALfm3ndrgx6Dr22QdkoqVCS4uwm7UfC3HVsAWwIO0PHY6rsK0Z0KOEtNyaLBdlmt6VNXZloZU45qjTJMPs8LoPHr6edzB6x/yQxvqm/GPkO+P5yLoC0D78vMxwY+ZStmTSdNH07nS4Exa5uWFW0y2JOqf5eusP9MMiRLj00xV5abSPTX63L96JUGFcTpIi+ZyAr1A6hbAmC+tS6KvtbJPE8ncCMXrs2uhoTfzs6XE5mopQIcfEJobMmAjxzzsDOXGGUJdsBQBrRMBvdeaOI2ALJMtKGLzu1fituwgfGV7dFf4Wii+1bD+w==',
      };

      final manifest = RemoteBundleManifest.fromJson(manifestJson);
      final signablePayload = '${manifest.bundleVersion}|${manifest.bundleUrl}|${manifest.sha256}|${manifest.size}';

      final isValid = service.verifyRsaSignature(
        payload: signablePayload,
        signatureBase64: manifest.signature,
        publicKeyPem: BundlePublicKey.pem,
      );

      expect(isValid, true);
    });

    test('verifyRsaSignature rejects tampered manifest signature', () {
      final signablePayload = '1.0.1|https://e-global-197077.vercel.app/mobile-bundles/1.0.1/bundle.zip|tampered_hash|4188863';
      final tamperedSignature = 'TAvCVN/yuRW5We3fxMcvJvgU8jYTY7YZALfm3ndrgx6Dr22QdkoqVCS4uwm7UfC3HVsAWwIO0PHY6rsK0Z0KOEtNyaLBdlmt6VNXZloZU45qjTJMPs8LoPHr6edzB6x/yQxvqm/GPkO+P5yLoC0D78vMxwY+ZStmTSdNH07nS4Exa5uWFW0y2JOqf5eusP9MMiRLj00xV5abSPTX63L96JUGFcTpIi+ZyAr1A6hbAmC+tS6KvtbJPE8ncCMXrs2uhoTfzs6XE5mopQIcfEJobMmAjxzzsDOXGGUJdsBQBrRMBvdeaOI2ALJMtKGLzu1fituwgfGV7dFf4Wii+1bD+w==';

      final isValid = service.verifyRsaSignature(
        payload: signablePayload,
        signatureBase64: tamperedSignature,
        publicKeyPem: BundlePublicKey.pem,
      );

      expect(isValid, false);
    });
  });
}
