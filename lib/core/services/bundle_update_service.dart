import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/constants/bundle_public_key.dart';
import 'package:wallet/core/utils/logger.dart';

class RemoteBundleManifest {
  final String bundleVersion;
  final String bundleUrl;
  final String sha256;
  final int size;
  final String signature;
  final List<String> requiredFiles;

  RemoteBundleManifest({
    required this.bundleVersion,
    required this.bundleUrl,
    required this.sha256,
    required this.size,
    required this.signature,
    required this.requiredFiles,
  });

  factory RemoteBundleManifest.fromJson(Map<String, dynamic> json) {
    return RemoteBundleManifest(
      bundleVersion: json['bundleVersion'] as String? ?? '1.0.0',
      bundleUrl: json['bundleUrl'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      signature: json['signature'] as String? ?? '',
      requiredFiles: (json['requiredFiles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['index.html'],
    );
  }
}

class BundleUpdateService {
  final String manifestUrl;

  BundleUpdateService({
    this.manifestUrl = 'https://e-global-197077.vercel.app/mobile-bundles/manifest.json',
  });

  bool isVersionNewer(String remote, String current) {
    try {
      final rParts = remote.split('.').map((e) => int.parse(e)).toList();
      final cParts = current.split('.').map((e) => int.parse(e)).toList();

      final maxLength = rParts.length > cParts.length ? rParts.length : cParts.length;
      for (int i = 0; i < maxLength; i++) {
        final r = i < rParts.length ? rParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (r > c) return true;
        if (r < c) return false;
      }
    } catch (e) {
      AppLogger.e('Error comparing version strings', e);
    }
    return false;
  }

  bool verifyRsaSignature({
    required String payload,
    required String signatureBase64,
    required String publicKeyPem,
  }) {
    try {
      if (signatureBase64.isEmpty || publicKeyPem.isEmpty) return false;

      // Extract Base64 key content from PEM
      final pemClean = publicKeyPem
          .replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '')
          .replaceAll(RegExp(r'\s+'), '');

      final keyBytes = base64.decode(pemClean);
      final asn1Parser = ASN1Parser(keyBytes);
      final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
      final publicKeyBitString = topLevelSeq.elements![1] as ASN1BitString;

      final publicKeyAsn1Parser = ASN1Parser(Uint8List.fromList(publicKeyBitString.stringValues!));
      final publicKeySeq = publicKeyAsn1Parser.nextObject() as ASN1Sequence;
      final modulus = (publicKeySeq.elements![0] as ASN1Integer).integer!;
      final exponent = (publicKeySeq.elements![1] as ASN1Integer).integer!;

      final rsaPublicKey = RSAPublicKey(modulus, exponent);
      final signer = Signer('SHA-256/RSA')
        ..init(false, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));

      final payloadBytes = Uint8List.fromList(utf8.encode(payload));
      final sigBytes = base64.decode(signatureBase64);

      final signature = RSASignature(sigBytes);
      return signer.verifySignature(payloadBytes, signature);
    } catch (e) {
      AppLogger.e('RSA signature verification exception', e);
      return false;
    }
  }

  Future<Directory> _getUpdatesBaseDir() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final updatesDir = Directory('${appDocDir.path}/web_bundles');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    return updatesDir;
  }

  Future<File> _getActiveMetadataFile() async {
    final baseDir = await _getUpdatesBaseDir();
    return File('${baseDir.path}/active_bundle.json');
  }

  Future<File> _getFailedVersionsFile() async {
    final baseDir = await _getUpdatesBaseDir();
    return File('${baseDir.path}/failed_versions.json');
  }

  Future<List<String>> _getFailedVersions() async {
    try {
      final file = await _getFailedVersionsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = json.decode(content);
        if (list is List) {
          return list.map((e) => e.toString()).toList();
        }
      }
    } catch (e) {
      AppLogger.e('Error reading failed versions', e);
    }
    return [];
  }

  Future<void> _recordFailedVersion(String version) async {
    try {
      final failed = await _getFailedVersions();
      if (!failed.contains(version)) {
        failed.add(version);
        final file = await _getFailedVersionsFile();
        await file.writeAsString(json.encode(failed), flush: true);
      }
    } catch (e) {
      AppLogger.e('Error recording failed version', e);
    }
  }

  Future<String> getActiveVersion() async {
    try {
      final metaFile = await _getActiveMetadataFile();
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        final version = jsonMap['activeVersion'] as String?;
        final path = jsonMap['activePath'] as String?;
        if (version != null && path != null && await Directory(path).exists()) {
          final indexHtml = File('$path/index.html');
          if (await indexHtml.exists()) {
            return version;
          }
        }
      }
    } catch (e) {
      AppLogger.e('Error getting active version', e);
    }
    return AppStrings.bundleVersion;
  }

  Future<String?> getActiveBundlePath() async {
    try {
      final metaFile = await _getActiveMetadataFile();
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        final path = jsonMap['activePath'] as String?;
        if (path != null) {
          final dir = Directory(path);
          final indexHtml = File('${dir.path}/index.html');
          if (await dir.exists() && await indexHtml.exists()) {
            return dir.path;
          } else {
            AppLogger.e('Active bundle path missing index.html, rolling back');
            final version = jsonMap['activeVersion'] as String? ?? 'unknown';
            await rollbackToPreviousBundle(version);
          }
        }
      }
    } catch (e) {
      AppLogger.e('Error checking active bundle path', e);
    }
    return null; // Fallback to assets/web/
  }

  Future<void> checkForUpdatesInBackground() async {
    try {
      final uri = Uri.parse(manifestUrl);
      if (!AppStrings.isTrustedWalletOrigin(uri)) {
        AppLogger.e('Rejected update check: Untrusted manifest origin $uri');
        return;
      }

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.e('Manifest fetch returned non-200 status: ${response.statusCode}');
        return;
      }

      final jsonMap = json.decode(response.body) as Map<String, dynamic>;
      final manifest = RemoteBundleManifest.fromJson(jsonMap);

      if (manifest.bundleUrl.isEmpty || manifest.sha256.isEmpty) {
        AppLogger.e('Invalid remote manifest missing bundleUrl or sha256');
        return;
      }

      final signablePayload =
          '${manifest.bundleVersion}|${manifest.bundleUrl}|${manifest.sha256}|${manifest.size}';
      final isSignatureValid = verifyRsaSignature(
        payload: signablePayload,
        signatureBase64: manifest.signature,
        publicKeyPem: BundlePublicKey.pem,
      );

      if (!isSignatureValid) {
        AppLogger.e(
          'Security alert: Manifest RSA digital signature verification failed for version ${manifest.bundleVersion}!',
        );
        return;
      }

      final bundleUri = Uri.parse(manifest.bundleUrl);
      if (bundleUri.scheme.toLowerCase() != 'https' ||
          !AppStrings.isTrustedWalletOrigin(bundleUri)) {
        AppLogger.e('Rejected remote bundleUrl: Untrusted host ${bundleUri.host}');
        return;
      }

      final currentVersion = await getActiveVersion();
      if (!isVersionNewer(manifest.bundleVersion, currentVersion)) {
        AppLogger.i(
          'No newer bundle version available (current: $currentVersion, remote: ${manifest.bundleVersion})',
        );
        return;
      }

      final failedVersions = await _getFailedVersions();
      if (failedVersions.contains(manifest.bundleVersion)) {
        AppLogger.i(
          'Suppressed download of previously failed version ${manifest.bundleVersion}',
        );
        return;
      }

      AppLogger.i('Downloading newer web bundle v${manifest.bundleVersion}...');
      await _downloadAndActivateBundle(manifest, currentVersion);
    } catch (e) {
      AppLogger.e('Background bundle update check failed', e);
    }
  }

  Future<void> _downloadAndActivateBundle(
    RemoteBundleManifest manifest,
    String currentVersion,
  ) async {
    File? tempZip;
    Directory? extractedDir;
    try {
      final baseDir = await _getUpdatesBaseDir();
      final tempZipPath = '${baseDir.path}/temp_${manifest.bundleVersion}.zip';
      tempZip = File(tempZipPath);
      if (await tempZip.exists()) await tempZip.delete();

      final request = http.Request('GET', Uri.parse(manifest.bundleUrl));
      final response =
          await http.Client().send(request).timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode} downloading bundle zip');
      }

      final sink = tempZip.openWrite();
      int downloadedBytes = 0;

      await for (final chunk in response.stream) {
        downloadedBytes += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      if (manifest.size > 0 && downloadedBytes != manifest.size) {
        throw Exception(
          'Downloaded size ($downloadedBytes) does not match expected size (${manifest.size})',
        );
      }

      final bytes = await tempZip.readAsBytes();
      final computedDigest = sha256.convert(bytes).toString().toLowerCase();

      if (computedDigest != manifest.sha256.toLowerCase()) {
        throw Exception(
          'SHA-256 checksum mismatch (computed: $computedDigest, expected: ${manifest.sha256})',
        );
      }

      extractedDir =
          Directory('${baseDir.path}/extracted_${manifest.bundleVersion}');
      if (await extractedDir.exists()) await extractedDir.delete(recursive: true);
      await extractedDir.create(recursive: true);

      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final filename = file.name;
        if (filename.contains('../') ||
            filename.contains('..\\') ||
            filename.startsWith('/')) {
          throw Exception('Security violation: Path traversal detected in zip archive');
        }

        if (file.isFile) {
          final outFile = File('${extractedDir.path}/$filename');
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>, flush: true);
        } else {
          await Directory('${extractedDir.path}/$filename').create(recursive: true);
        }
      }

      final indexHtml = File('${extractedDir.path}/index.html');
      if (!await indexHtml.exists()) {
        throw Exception(
          'Validation error: Extracted bundle is missing required entrypoint index.html',
        );
      }

      final targetBundleDir =
          Directory('${baseDir.path}/bundle_${manifest.bundleVersion}');
      if (await targetBundleDir.exists()) await targetBundleDir.delete(recursive: true);
      await extractedDir.rename(targetBundleDir.path);

      final currentPath = (await _getActiveMetadataFile()).existsSync()
          ? (json.decode(await (await _getActiveMetadataFile()).readAsString())
              as Map<String, dynamic>)['activePath'] as String?
          : null;

      final activeMeta = {
        'activeVersion': manifest.bundleVersion,
        'activePath': targetBundleDir.path,
        'previousVersion': currentVersion,
        'previousPath': currentPath,
        'activatedAt': DateTime.now().toIso8601String(),
      };

      final metaFile = await _getActiveMetadataFile();
      await metaFile.writeAsString(json.encode(activeMeta), flush: true);

      if (await tempZip.exists()) await tempZip.delete();

      AppLogger.i(
        'Successfully verified and atomically activated web bundle v${manifest.bundleVersion}',
      );
    } catch (e) {
      AppLogger.e('Bundle download/activation failed', e);
      await _recordFailedVersion(manifest.bundleVersion);
      if (tempZip != null && await tempZip.exists()) {
        try {
          await tempZip.delete();
        } catch (_) {}
      }
      if (extractedDir != null && await extractedDir.exists()) {
        try {
          await extractedDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> rollbackToPreviousBundle(String failedVersion) async {
    try {
      await _recordFailedVersion(failedVersion);
      final metaFile = await _getActiveMetadataFile();

      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        final jsonMap = json.decode(content) as Map<String, dynamic>;
        final previousPath = jsonMap['previousPath'] as String?;
        final previousVersion =
            jsonMap['previousVersion'] as String? ?? AppStrings.bundleVersion;

        if (previousPath != null &&
            await Directory(previousPath).exists() &&
            await File('$previousPath/index.html').exists()) {
          final activeMeta = {
            'activeVersion': previousVersion,
            'activePath': previousPath,
            'previousVersion': null,
            'previousPath': null,
            'rolledBackAt': DateTime.now().toIso8601String(),
          };
          await metaFile.writeAsString(json.encode(activeMeta), flush: true);
          AppLogger.i(
            'Successfully rolled back to previous bundle version $previousVersion',
          );
          return;
        }
      }

      if (await metaFile.exists()) {
        await metaFile.delete();
      }
      AppLogger.i('Rolled back to built-in assets/web/ bundle');
    } catch (e) {
      AppLogger.e('Error performing rollback', e);
    }
  }
}
