import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:wallet/core/utils/logger.dart';

/// Persistence mechanism for non-sensitive cached application data.
/// Sensitive credentials and tokens remain stored in SecureStorageServiceImpl.
class LocalCacheService {
  static final LocalCacheService _instance = LocalCacheService._internal();
  factory LocalCacheService() => _instance;
  LocalCacheService._internal();

  Future<File> _getCacheFile(String key) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/app_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/$key.json');
  }

  Future<void> save(String key, Map<String, dynamic> data) async {
    try {
      final file = await _getCacheFile(key);
      await file.writeAsString(json.encode(data), flush: true);
    } catch (e) {
      AppLogger.e('Error saving local cache for key $key', e);
    }
  }

  Future<Map<String, dynamic>?> read(String key) async {
    try {
      final file = await _getCacheFile(key);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return json.decode(content) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      AppLogger.e('Error reading local cache for key $key', e);
    }
    return null;
  }

  Future<void> clear(String key) async {
    try {
      final file = await _getCacheFile(key);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      AppLogger.e('Error clearing local cache for key $key', e);
    }
  }
}
