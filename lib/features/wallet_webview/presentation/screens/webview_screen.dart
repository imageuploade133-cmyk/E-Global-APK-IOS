import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/services/bundle_update_service.dart';
import 'package:wallet/core/services/core_providers.dart';
import 'package:wallet/core/utils/logger.dart';
import '../widgets/download_progress_bar.dart';
import '../widgets/webview_error_overlay.dart';
import '../controllers/webview_controller.dart';

class WebviewScreen extends ConsumerStatefulWidget {
  const WebviewScreen({super.key});

  @override
  ConsumerState<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends ConsumerState<WebviewScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  InAppLocalhostServer? _localhostServer;
  bool _localhostServerStarted = false;

  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<String>? _redirectSubscription;
  bool _isOnline = false;
  bool _connectivityInitialized = false;
  String? _pendingRedirectPath;
  String _currentUrl = AppStrings.localHostBaseUrl;
  String _lastSuccessfulUrl = AppStrings.localHostBaseUrl;
  String? _offlineNavigationOriginUrl;
  bool _offlineNavigationInProgress = false;
  bool _offlineNavigationRestoring = false;
  final Set<String> _successfullyLoadedUrls = <String>{
    AppStrings.localHostBaseUrl,
    AppStrings.baseUrl,
  };

  double _downloadProgress = 0.0;
  String _downloadingFileName = '';
  bool _isDownloading = false;

  bool _hasLoadError = false;
  bool _isCrashing = false;
  bool _isUserRetrying = false;
  Timer? _loadingTimeoutTimer;

  int _loadAttemptId = 0;
  int? _recoveryAttemptId;
  bool _mainFrameLoading = false;
  bool _recoveryCompleted = false;
  String? _loadingMainFrameUrl;

  // Bleached Clean White constant color to eliminate layout flashes
  static const Color bleachWhite = Colors.white;

  bool _isInBackground = false;
  bool _hasRestoredSystemUi = false;
  Timer? _startupGuardTimer;

  void _restoreSystemUi() {
    if (_hasRestoredSystemUi) return;
    _hasRestoredSystemUi = true;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    try {
      FlutterNativeSplash.remove();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startLocalhostServer();
    _initConnectivity();
    _initPushNotifications();
  }

  Future<void> _startLocalhostServer() async {
    try {
      final updateService = BundleUpdateService();
      final activeBundlePath = await updateService.getActiveBundlePath();

      final documentRoot = activeBundlePath ?? 'assets/web';
      AppLogger.i('InAppLocalhostServer starting with documentRoot: $documentRoot');

      _localhostServer = InAppLocalhostServer(
        documentRoot: documentRoot,
        port: 8080,
      );

      if (!_localhostServer!.isRunning()) {
        await _localhostServer!.start();
      }

      if (mounted) {
        setState(() {
          _localhostServerStarted = true;
        });
      }

      // Non-blocking background check for remote bundle updates
      updateService.checkForUpdatesInBackground();
    } catch (e) {
      AppLogger.e('Failed to start InAppLocalhostServer', e);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _redirectSubscription?.cancel();
    _loadingTimeoutTimer?.cancel();
    _startupGuardTimer?.cancel();
    if (_localhostServer != null && _localhostServer!.isRunning()) {
      _localhostServer!.close();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_isInBackground && mounted) {
        setState(() {
          _isInBackground = true;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isInBackground && mounted) {
        setState(() {
          _isInBackground = false;
        });
      }
    }
  }

  Future<void> _initConnectivity() async {
    final connectivity = ref.read(connectivityServiceProvider);
    final initialConnectivity = await connectivity.isConnected;
    _isOnline = initialConnectivity;
    _connectivityInitialized = true;
    if (mounted) {
      setState(() {});
    }

    _connectivitySubscription = connectivity.onConnectivityChanged.listen((
      isConnected,
    ) {
      if (mounted) {
        setState(() {
          _isOnline = isConnected;
        });
        _handleConnectivityChange(isConnected);
      }
    });
  }

  Future<void> _initPushNotifications() async {
    final pushService = ref.read(pushNotificationServiceProvider);

    _redirectSubscription = pushService.onNotificationRedirectStream.listen((
      path,
    ) {
      _handleNotificationRedirect(path);
    });

    await pushService.initialize();
  }

  String _buildRedirectUrl(String path) {
    final baseUrl = AppStrings.localHostBaseUrl;
    final cleanBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$cleanBase$cleanPath';
  }

  void _handleNotificationRedirect(String path) {
    if (_webViewController != null && path.isNotEmpty) {
      final fullUrl = _buildRedirectUrl(path);
      _startLoadingTimer();
      _webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(fullUrl)));
    } else {
      _pendingRedirectPath = path;
    }
  }

  void _startLoadingTimer() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        AppLogger.e('Page loading timed out');
        _restoreSystemUi();
        final wasUserRetrying = _isUserRetrying;
        _mainFrameLoading = false;
        _recoveryAttemptId = null;
        setState(() {
          _hasLoadError = true;
          _isCrashing = false;
          _isUserRetrying = false;
        });
        if (wasUserRetrying) {
          HapticFeedback.vibrate();
        }
      }
    });
  }

  void _stopLoadingTimer() {
    _loadingTimeoutTimer?.cancel();
  }

  Future<void> _triggerNativeHaptic([String type = 'default']) async {
    try {
      await const MethodChannel('com.eglobal.wallet/haptics').invokeMethod<void>(
        'vibrate',
        {'type': type},
      );
    } catch (_) {
      try {
        if (type == 'pin' || type == 'keypress') {
          await HapticFeedback.lightImpact();
        } else if (type == 'heavy' || type == 'impact') {
          await HapticFeedback.heavyImpact();
        } else {
          await HapticFeedback.mediumImpact();
          await HapticFeedback.vibrate();
        }
      } catch (_) {}
    }
  }

  Future<void> _checkConnectionAndReload() async {
    await _triggerNativeHaptic();

    final recoveryAttemptId = ++_loadAttemptId;
    _recoveryAttemptId = recoveryAttemptId;
    _recoveryCompleted = false;
    _mainFrameLoading = true;

    if (mounted) {
      setState(() {
        _isUserRetrying = true;
        _hasLoadError = false;
      });
    }

    final connectivity = ref.read(connectivityServiceProvider);
    final isConnected = await connectivity.isConnected;

    if (!isConnected) {
      if (mounted && _recoveryAttemptId == recoveryAttemptId) {
        _mainFrameLoading = false;
        setState(() {
          _isOnline = false;
          _hasLoadError = true;
          _isUserRetrying = false;
        });
      }
      return;
    }

    if (!mounted || _recoveryAttemptId != recoveryAttemptId) return;

    setState(() {
      _isOnline = true;
      _isUserRetrying = true;
    });
    _startLoadingTimer();
    final controller = _webViewController;
    if (controller != null && _recoveryAttemptId == recoveryAttemptId) {
      await controller.setSettings(
        settings: InAppWebViewSettings(
          cacheMode: CacheMode.LOAD_DEFAULT,
          networkAvailable: true,
        ),
      );
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(_currentUrl)),
      );
    }
  }

  Future<void> _handleConnectivityChange(bool isConnected) async {
    if (_webViewController != null) {
      await _webViewController!.setSettings(
        settings: InAppWebViewSettings(
          cacheMode: CacheMode.LOAD_CACHE_ELSE_NETWORK,
          networkAvailable: isConnected,
        ),
      );
    }
  }

  CacheMode _getCurrentCacheMode() {
    return CacheMode.LOAD_CACHE_ELSE_NETWORK;
  }

  void _showRuntimePermissionDeniedDialog(Permission permission) {
    final name = _getPermissionName(permission);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$name is required for this feature. Please grant it when prompted or in App Settings.',
        ),
        action: SnackBarAction(
          label: 'Settings',
          textColor: Colors.orange,
          onPressed: () async {
            await openAppSettings();
          },
        ),
      ),
    );
  }

  String _getPermissionName(Permission permission) {
    if (permission == Permission.camera) return 'Camera Access';
    if (permission == Permission.microphone) return 'Microphone Access';
    if (permission == Permission.location ||
        permission == Permission.locationWhenInUse) {
      return 'Location Services';
    }
    if (permission == Permission.storage) return 'Storage Access';
    if (permission == Permission.photos) return 'Photo Library';
    if (permission == Permission.contacts) return 'Contacts Access';
    if (permission == Permission.notification) return 'Real-time Alerts';
    return permission.toString();
  }

  Future<PermissionResponse?> _handlePermissionRequest(
    InAppWebViewController controller,
    PermissionRequest permissionRequest,
  ) async {
    final List<Permission> permissionsToRequest = [];

    for (final resource in permissionRequest.resources) {
      final resourceName = resource.toString().toUpperCase();
      if (resourceName.contains('AUDIO_CAPTURE') ||
          resourceName.contains('MICROPHONE')) {
        permissionsToRequest.add(Permission.microphone);
      }
      if (resourceName.contains('VIDEO_CAPTURE') ||
          resourceName.contains('CAMERA')) {
        permissionsToRequest.add(Permission.camera);
      }
    }

    if (permissionsToRequest.isNotEmpty) {
      for (final perm in permissionsToRequest) {
        final status = await perm.request();
        if (!status.isGranted && !status.isLimited && !status.isRestricted) {
          _showRuntimePermissionDeniedDialog(perm);
          return PermissionResponse(
            resources: permissionRequest.resources,
            action: PermissionResponseAction.DENY,
          );
        }
      }
    }

    return PermissionResponse(
      resources: permissionRequest.resources,
      action: PermissionResponseAction.GRANT,
    );
  }

  String _sanitizeFileName(String rawName, [String? mimeType]) {
    var name = rawName.split('?').first.split('#').first;
    name = name.replaceAll(RegExp(r'[\\/:\*\?"<>\|]'), '_');
    name = name.replaceAll(RegExp(r'^\.+'), '');
    if (name.trim().isEmpty) name = 'downloaded_file';

    if (!name.contains('.')) {
      final ext = _getExtensionFromMimeType(mimeType);
      if (ext.isNotEmpty) {
        name = '$name$ext';
      }
    }
    return name;
  }

  String _getExtensionFromMimeType(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) return '';
    final mime = mimeType.toLowerCase().split(';').first.trim();
    switch (mime) {
      case 'application/pdf':
        return '.pdf';
      case 'image/png':
        return '.png';
      case 'image/jpeg':
      case 'image/jpg':
        return '.jpg';
      case 'image/webp':
        return '.webp';
      case 'text/csv':
        return '.csv';
      case 'text/plain':
        return '.txt';
      case 'application/json':
        return '.json';
      case 'application/zip':
        return '.zip';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return '.docx';
      case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        return '.xlsx';
      case 'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        return '.pptx';
      default:
        return '';
    }
  }

  String? _parseContentDispositionFileName(String? contentDisposition) {
    if (contentDisposition == null || contentDisposition.isEmpty) return null;
    try {
      final utf8Match = RegExp(
        r'''filename\*\s*=\s*(?:utf-8|UTF-8)['"]*['"]*(?:[^'\n]*)['"]*['"]*([^;\n]+)''',
        caseSensitive: false,
      ).firstMatch(contentDisposition);
      if (utf8Match != null) {
        var rawMatch = utf8Match.group(1)?.trim() ?? '';
        rawMatch = rawMatch.replaceAll(RegExp(r"^['']+|['']+$"), '');
        if (rawMatch.isNotEmpty) {
          return Uri.decodeComponent(rawMatch);
        }
      }

      final stdMatch = RegExp(
        r'''filename\s*=\s*(?:"([^"]+)"|'([^']+)'|([^;\n]+))''',
        caseSensitive: false,
      ).firstMatch(contentDisposition);
      if (stdMatch != null) {
        final rawMatch = stdMatch.group(1) ?? stdMatch.group(2) ?? stdMatch.group(3);
        if (rawMatch != null && rawMatch.trim().isNotEmpty) {
          return rawMatch.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handleDownload(
    String url,
    String? userAgent,
    String? contentDisposition,
    String? mimeType,
    int contentLength,
  ) async {
    File? partialFile;
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.toLowerCase() != 'https' && uri.scheme.toLowerCase() != 'http') {
        AppLogger.e('Rejected insecure download request');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Insecure downloads are blocked.')),
          );
        }
        return;
      }

      final isOfficialHost = AppStrings.isTrustedWalletOrigin(uri);
      final isTrustedGateway = AppStrings.isTrustedGatewayOrigin(uri);

      if (!isOfficialHost && !isTrustedGateway) {
        AppLogger.e('Rejected download request from untrusted origin host');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download rejected: Untrusted domain.'),
            ),
          );
        }
        return;
      }

      final client = HttpClient();
      final request = await client.getUrl(uri);
      if (userAgent != null && userAgent.isNotEmpty) {
        request.headers.set('User-Agent', userAgent);
      }

      if (_webViewController != null) {
        try {
          final cookieManager = CookieManager.instance();
          final cookies = await cookieManager.getCookies(
            url: WebUri(uri.toString()),
          );
          if (cookies.isNotEmpty) {
            final cookieHeader = cookies
                .map((c) => '${c.name}=${c.value}')
                .join('; ');
            request.headers.set('Cookie', cookieHeader);
          }
        } catch (e) {
          AppLogger.e('Error forwarding cookies for download', e);
        }
      }

      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP Error ${response.statusCode} while downloading file.',
        );
      }

      final cdFileName = _parseContentDispositionFileName(
        response.headers.value('content-disposition') ?? contentDisposition,
      );
      final rawFileName = cdFileName ??
          (uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : 'downloaded_file');
      final effectiveMimeType =
          response.headers.value('content-type') ?? mimeType;
      final fileName = _sanitizeFileName(rawFileName, effectiveMimeType);

      setState(() {
        _isDownloading = true;
        _downloadingFileName = fileName;
        _downloadProgress = 0.1;
      });

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/temp_$fileName';
      partialFile = File(tempPath);

      await partialFile.parent.create(recursive: true);
      final sink = partialFile.openWrite();

      final total = response.contentLength > 0
          ? response.contentLength
          : contentLength;
      int received = 0;

      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && mounted) {
          setState(() {
            _downloadProgress = (received / total).clamp(0.0, 1.0);
          });
        }
      }
      await sink.flush();
      await sink.close();

      String targetOpenPath = tempPath;
      String displaySavedName = fileName;

      if (Platform.isAndroid) {
        const channel = MethodChannel('com.eglobal.wallet/mediastore');
        final String? publicSavedPath = await channel.invokeMethod<String>(
          'saveToDownloads',
          {
            'tempFilePath': tempPath,
            'fileName': fileName,
            'mimeType': effectiveMimeType ?? '*/*',
          },
        );
        if (publicSavedPath != null && publicSavedPath.isNotEmpty) {
          targetOpenPath = publicSavedPath;
          displaySavedName = fileName;
        } else {
          throw Exception('Failed to save file to MediaStore Downloads');
        }
      } else {
        final dirPath = await _getDownloadDirectoryPath();
        var filePath = '$dirPath/$fileName';
        var fileCounter = 1;
        final dotIdx = fileName.lastIndexOf('.');
        final baseName = dotIdx != -1 ? fileName.substring(0, dotIdx) : fileName;
        final extName = dotIdx != -1 ? fileName.substring(dotIdx) : '';

        while (await File(filePath).exists()) {
          filePath = '$dirPath/${baseName}_$fileCounter$extName';
          fileCounter++;
        }

        final targetFile = File(filePath);
        await partialFile.copy(targetFile.path);
        try {
          await partialFile.delete();
        } catch (_) {}
        targetOpenPath = targetFile.path;
        displaySavedName = filePath.split('/').last;
      }

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: $displaySavedName'),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.orange,
              onPressed: () async {
                await OpenFilex.open(targetOpenPath);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (partialFile != null && await partialFile.exists()) {
        try {
          await partialFile.delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
        AppLogger.e('Download error', e);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Download failed: Network error or non-200 server response.',
            ),
          ),
        );
      }
    }
  }

  Future<String> _getDownloadDirectoryPath() async {
    final appDocs = await getApplicationDocumentsDirectory();
    final path = '${appDocs.path}/eglobal_downloads';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  Future<void> _handleShare(String text) async {
    try {
      final sanitizedText = _sanitizeStringForDisplayOrShare(text);
      await Share.share(sanitizedText, subject: 'E-Global Pay Receipt');
    } catch (e) {
      AppLogger.e('Error sharing text', e);
    }
  }

  String _sanitizeStringForDisplayOrShare(String input) {
    var result = input;
    result = result.replaceAll(AppStrings.baseUrl, '');
    result = result.replaceAll(AppStrings.localHostBaseUrl, '');
    result = result.replaceAll('https://e-global-197077.vercel.app/', '');
    result = result.replaceAll('https://e-global-197077.vercel.app', '');
    result = result.replaceAll('e-global-197077.vercel.app', '');
    result = result.replaceAll('http://localhost:8080/', '');
    result = result.replaceAll('http://localhost:8080', '');
    result = result.replaceAll('localhost:8080', '');
    return result;
  }

  Future<void> _handleBase64Share(String base64Data, String fileName) async {
    try {
      final cleanBase64 = base64Data.contains(',')
          ? base64Data.split(',').last
          : base64Data;

      const maxBase64Length = 100 * 1024 * 1024;
      if (cleanBase64.length > maxBase64Length) {
        AppLogger.e('Base64 share payload exceeds maximum memory safety threshold');
        return;
      }

      final safeName = _sanitizeFileName(fileName);
      final bytes = base64.decode(cleanBase64);

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$safeName';
      final file = File(tempPath);
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([
        XFile(tempPath),
      ], text: 'E-Global Pay Receipt');
    } catch (e) {
      AppLogger.e('Error sharing base64 receipt', e);
    }
  }

  Future<void> _handleUrlShare(String url, String fileName) async {
    File? tempFile;
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.toLowerCase() != 'https' && uri.scheme.toLowerCase() != 'http') {
        AppLogger.e('Rejected insecure receipt share URL');
        return;
      }

      if (!AppStrings.isTrustedWalletOrigin(uri)) {
        AppLogger.e('Rejected receipt share from untrusted host: ${uri.host}');
        return;
      }

      final safeName = _sanitizeFileName(fileName);
      final client = HttpClient();
      final request = await client.getUrl(uri);

      if (_webViewController != null) {
        final cookieManager = CookieManager.instance();
        final cookies = await cookieManager.getCookies(
          url: WebUri(uri.toString()),
        );
        if (cookies.isNotEmpty) {
          final cookieHeader = cookies
              .map((c) => '${c.name}=${c.value}')
              .join('; ');
          request.headers.set('Cookie', cookieHeader);
        }
      }

      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP Error ${response.statusCode} while fetching share receipt.',
        );
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$safeName';
      tempFile = File(tempPath);

      final sink = tempFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      await Share.shareXFiles([
        XFile(tempPath),
      ], text: 'E-Global Pay Receipt');
    } catch (e) {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      AppLogger.e('Error sharing URL receipt', e);
    }
  }

  Future<void> _handlePopInvocation(bool didPop) async {
    if (didPop) return;

    if (_webViewController != null && await _webViewController!.canGoBack()) {
      await _webViewController!.goBack();
      return;
    }

    if (!mounted) return;

    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.power_settings_new_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Exit Application',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to close E-Global Pay? Any unsaved operations may be lost.',
          style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Exit Now',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (shouldExit ?? false) {
      await _triggerNativeHaptic();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      SystemNavigator.pop();
    }
  }

  Widget _buildSensitiveOfflineErrorUi() {
    return WebviewErrorOverlay(
      title: 'Unable to connect',
      subtitle: 'No internet connection. Please try again.',
      isRetrying: _isUserRetrying,
      onRetry: _checkConnectionAndReload,
    );
  }

  Future<bool> _isCurrentUrlTrusted(InAppWebViewController controller) async {
    try {
      final currentUrl = await controller.getUrl();
      if (currentUrl == null) return false;
      return AppStrings.isTrustedWalletOrigin(currentUrl);
    } catch (e) {
      AppLogger.e('Error validating URL origin', e);
      return false;
    }
  }

  Future<void> _injectSecurityAndAutofillScripts(
    InAppWebViewController controller,
  ) async {
    try {
      await controller.evaluateJavascript(source: """
        (function() {
          function applyFormSecurityAndUI() {
            if (!document.getElementById('eglobal-hide-scrollbars')) {
              var style = document.createElement('style');
              style.id = 'eglobal-hide-scrollbars';
              style.innerHTML = `
                *::-webkit-scrollbar,
                ::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }
                * {
                  scrollbar-width: none !important;
                  -ms-overflow-style: none !important;
                  -webkit-touch-callout: none !important;
                }
              `;
              (document.head || document.documentElement).appendChild(style);
            }

            var forms = document.querySelectorAll('form');
            forms.forEach(function(f) {
              f.setAttribute('autocomplete', 'off');
            });
            var inputs = document.querySelectorAll('input');
            inputs.forEach(function(i) {
              i.setAttribute('autocomplete', 'off');
              i.setAttribute('autofill', 'off');
              i.setAttribute('data-lpignore', 'true');
              var t = (i.type || '').toLowerCase();
              var n = (i.name || '').toLowerCase();
              var id = (i.id || '').toLowerCase();
              if (t === 'password' || n.includes('pass') || n.includes('pin') || id.includes('pin')) {
                i.setAttribute('autocomplete', 'new-password');
              } else if (n.includes('otp') || id.includes('otp') || i.getAttribute('autocomplete') === 'one-time-code') {
                i.setAttribute('autocomplete', 'one-time-code');
              }
            });
          }
          applyFormSecurityAndUI();
          if (document.readyState !== 'complete') {
            window.addEventListener('load', applyFormSecurityAndUI);
          }
        })();
      """);
    } catch (e) {
      AppLogger.e('Error injecting form security script', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final webViewNotifier = ref.read(webViewProvider.notifier);

    if (!_connectivityInitialized || !_localhostServerStarted) {
      return const Scaffold(
        backgroundColor: bleachWhite,
        body: ColoredBox(color: bleachWhite),
      );
    }

    if (!_isOnline && _hasLoadError) {
      return Scaffold(
        backgroundColor: bleachWhite,
        body: _buildSensitiveOfflineErrorUi(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        await _handlePopInvocation(didPop);
      },
      child: Scaffold(
        backgroundColor: bleachWhite,
        body: Container(
          color: bleachWhite,
          child: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
                  top: true,
                  bottom: true,
                  child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri(AppStrings.localHostBaseUrl),
                  ),
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    UserScript(
                      source: """
                        (function() {
                          var PROD_API_BASE = "https://e-global-197077.vercel.app";

                          // Intercept window.fetch to route relative /api/ requests to live Vercel backend
                          if (window.fetch) {
                            var origFetch = window.fetch;
                            window.fetch = function(input, init) {
                              var urlStr = typeof input === 'string'
                                ? input
                                : (input && input.url) ? input.url : '';
                              if (typeof urlStr === 'string' && (urlStr.startsWith('/api/') || urlStr.startsWith('/cpanel/api/'))) {
                                var newUrl = PROD_API_BASE + urlStr;
                                if (typeof input === 'string') {
                                  input = newUrl;
                                } else if (input && input.url) {
                                  input = new Request(newUrl, input);
                                }
                              }
                              return origFetch.call(this, input, init);
                            };
                          }

                          // Intercept XMLHttpRequest to route relative /api/ requests to live Vercel backend
                          if (window.XMLHttpRequest) {
                            var origOpen = XMLHttpRequest.prototype.open;
                            XMLHttpRequest.prototype.open = function(method, url, async, user, pass) {
                              if (typeof url === 'string' && (url.startsWith('/api/') || url.startsWith('/cpanel/api/'))) {
                                url = PROD_API_BASE + url;
                              }
                              return origOpen.call(this, method, url, async, user, pass);
                            };
                          }

                          var style = document.createElement('style');
                          style.id = 'eglobal-hide-scrollbars';
                          style.innerHTML = `
                            html, body, div, p, span, iframe, section, article, nav, aside, main, header, footer, form, input, textarea, select {
                              scrollbar-width: none !important;
                              -ms-overflow-style: none !important;
                              -webkit-touch-callout: none !important;
                            }
                            *::-webkit-scrollbar,
                            ::-webkit-scrollbar {
                              display: none !important;
                              width: 0 !important;
                              height: 0 !important;
                              background: transparent !important;
                            }
                            ::-webkit-scrollbar-thumb {
                              display: none !important;
                              width: 0px !important;
                              height: 0px !important;
                            }
                            ::-webkit-scrollbar-track {
                              display: none !important;
                              width: 0px !important;
                              height: 0px !important;
                            }
                          `;
                          (document.head || document.documentElement).appendChild(style);

                          function triggerPinHaptic() {
                            try {
                              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                                window.flutter_inappwebview.callHandler('triggerHaptic', 'pin');
                              }
                            } catch(e) {}
                          }

                          if (navigator && navigator.vibrate) {
                            var origVibrate = navigator.vibrate.bind(navigator);
                            navigator.vibrate = function(pattern) {
                              triggerPinHaptic();
                              return origVibrate(pattern);
                            };
                          }

                          function isPinRelated(el) {
                            if (!el) return false;
                            var tag = (el.tagName || '').toLowerCase();
                            var type = (el.type || '').toLowerCase();
                            var id = (el.id || '').toLowerCase();
                            var name = (el.name || '').toLowerCase();
                            var cls = (el.className || '').toString().toLowerCase();
                            var placeholder = (el.getAttribute('placeholder') || '').toLowerCase();
                            var autocomplete = (el.getAttribute('autocomplete') || '').toLowerCase();

                            if (type === 'password' || type === 'tel' || type === 'number') {
                              return true;
                            }
                            var pinKeywords = ['pin', 'otp', 'passcode', 'access', 'txn', 'transaction', 'code', 'digit', 'keypad', 'security'];
                            for (var i = 0; i < pinKeywords.length; i++) {
                              var kw = pinKeywords[i];
                              if (id.includes(kw) || name.includes(kw) || cls.includes(kw) || placeholder.includes(kw) || autocomplete.includes(kw)) {
                                return true;
                              }
                            }
                            return false;
                          }

                          document.addEventListener('keydown', function(e) {
                            if (isPinRelated(e.target) || isPinRelated(document.activeElement)) {
                              triggerPinHaptic();
                            }
                          }, true);

                          document.addEventListener('input', function(e) {
                            if (isPinRelated(e.target) || isPinRelated(document.activeElement)) {
                              triggerPinHaptic();
                            }
                          }, true);

                          function handlePointer(e) {
                            var target = e.target;
                            while (target && target !== document.body) {
                              if (isPinRelated(target) || (target.tagName === 'BUTTON' && isPinRelated(target.parentElement))) {
                                triggerPinHaptic();
                                break;
                              }
                              target = target.parentElement;
                            }
                          }

                          document.addEventListener('touchstart', handlePointer, { passive: true, capture: true });
                          document.addEventListener('click', handlePointer, true);
                        })();
                      """,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ]),
                  initialSettings: InAppWebViewSettings(
                    useShouldOverrideUrlLoading: true,
                    mediaPlaybackRequiresUserGesture: false,
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    databaseEnabled: true,
                    cacheEnabled: true,
                    useOnDownloadStart: true,
                    allowsLinkPreview: false,
                    safeBrowsingEnabled: true,
                    disableDefaultErrorPage: true,
                    saveFormData: false,
                    disableContextMenu: true,
                    mixedContentMode:
                        MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    scrollbarFadingEnabled: false,
                    scrollBarStyle: ScrollBarStyle.SCROLLBARS_INSIDE_OVERLAY,
                    scrollBarDefaultDelayBeforeFade: 0,
                    scrollBarFadeDuration: 0,
                    verticalScrollbarThumbColor: Colors.transparent,
                    verticalScrollbarTrackColor: Colors.transparent,
                    horizontalScrollbarThumbColor: Colors.transparent,
                    horizontalScrollbarTrackColor: Colors.transparent,
                    disallowOverScroll: true,
                    overScrollMode: OverScrollMode.NEVER,
                    hardwareAcceleration: true,
                    cacheMode: _getCurrentCacheMode(),
                    networkAvailable: _isOnline,
                    transparentBackground: false,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    supportZoom: false,
                    thirdPartyCookiesEnabled: false,
                    sharedCookiesEnabled: true,
                    allowFileAccess: false,
                    allowFileAccessFromFileURLs: false,
                    allowUniversalAccessFromFileURLs: false,
                  ),
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final uri = navigationAction.request.url;
                    if (uri == null) return NavigationActionPolicy.CANCEL;

                    final scheme = uri.scheme.toLowerCase();
                    final urlString = uri.toString();
                    final path = uri.path.toLowerCase();

                    if (navigationAction.isForMainFrame == true &&
                        (scheme == 'http' || scheme == 'https')) {
                      final connectivity = ref.read(connectivityServiceProvider);
                      final isConnectedNow = await connectivity.isConnected;
                      if (mounted && _isOnline != isConnectedNow) {
                        setState(() => _isOnline = isConnectedNow);
                      }

                      final normalizedTarget = uri.toString();
                      final isPreviouslyLoaded =
                          _successfullyLoadedUrls.contains(normalizedTarget);
                      final isHistoryNavigation =
                          navigationAction.navigationType ==
                          NavigationType.BACK_FORWARD;

                      if (!isConnectedNow &&
                          !isPreviouslyLoaded &&
                          !isHistoryNavigation &&
                          !AppStrings.isTrustedWalletOrigin(uri)) {
                        _offlineNavigationOriginUrl = _lastSuccessfulUrl;
                        _offlineNavigationInProgress = false;
                        _offlineNavigationRestoring = false;
                        _stopLoadingTimer();
                        if (mounted) {
                          setState(() {
                            _hasLoadError = true;
                            _isCrashing = false;
                            _isUserRetrying = false;
                          });
                        }
                        return NavigationActionPolicy.CANCEL;
                      }


                    if (!_isOnline) {
                      final sensitiveKeywords = [
                        'transfer',
                        'deposit',
                        'withdraw',
                        'airtime',
                        'data',
                        'electricity',
                        'cable',
                        'bill',
                        'kyc',
                        'pin',
                        'otp',
                      ];
                      if (sensitiveKeywords.any((keyword) => path.contains(keyword))) {
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Active internet connection required for financial operations.'),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                    }

                    if (urlString.startsWith('share:') ||
                        urlString.startsWith('eglobal://share')) {
                      final queryParams = uri.queryParameters;
                      final text =
                          queryParams['text'] ??
                          queryParams['data'] ??
                          urlString.replaceFirst('share:', '');
                      await _handleShare(Uri.decodeComponent(text));
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (AppStrings.isTrustedWalletOrigin(uri)) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (scheme == 'tel' ||
                        scheme == 'mailto' ||
                        scheme == 'sms' ||
                        scheme == 'whatsapp') {
                      try {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (e) {
                        AppLogger.e(
                          'Could not launch external protocol: $scheme',
                          e,
                        );
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (AppStrings.isTrustedGatewayOrigin(uri)) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (scheme == 'https' || scheme == 'http') {
                      try {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (e) {
                        AppLogger.e(
                          'Could not launch external URL in browser',
                          e,
                        );
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    AppLogger.e(
                      'Blocked unsafe/unknown navigation request to: $urlString',
                    );
                    return NavigationActionPolicy.CANCEL;
                  }

                  return NavigationActionPolicy.ALLOW;
                  },
                  onWebViewCreated: (controller) {
                    _webViewController = controller;

                    final pushService = ref.read(
                      pushNotificationServiceProvider,
                    );
                    pushService.setWebViewController(controller);

                    controller.addJavaScriptHandler(
                      handlerName: 'triggerHaptic',
                      callback: (args) async {
                        final type = (args.isNotEmpty && args[0] is String)
                            ? args[0] as String
                            : 'pin';
                        await _triggerNativeHaptic(type);
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'vibrate',
                      callback: (args) async {
                        final type = (args.isNotEmpty && args[0] is String)
                            ? args[0] as String
                            : 'pin';
                        await _triggerNativeHaptic(type);
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'pinKeypress',
                      callback: (args) async {
                        await _triggerNativeHaptic('pin');
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'unregisterFcmToken',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e('Rejected unregisterFcmToken from untrusted origin');
                          return;
                        }
                        final pushService = ref.read(pushNotificationServiceProvider);
                        await pushService.unregisterTokenFromBackend();
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'getFcmToken',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected getFcmToken from untrusted origin',
                          );
                          return null;
                        }
                        return await pushService.getFcmToken();
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'requestNotificationPermission',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected requestNotificationPermission from untrusted origin',
                          );
                          return;
                        }
                        final pushService = ref.read(
                          pushNotificationServiceProvider,
                        );
                        await pushService.requestPermission();
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'share',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected share request from untrusted origin',
                          );
                          return;
                        }
                        if (args.isNotEmpty) {
                          final shareData = args[0];
                          if (shareData is String) {
                            await _handleShare(shareData);
                          } else if (shareData is Map) {
                            final text = shareData['text'] as String?;
                            final url = shareData['url'] as String?;
                            final base64Data = shareData['base64'] as String?;
                            final fileName = shareData['fileName'] as String?;

                            if (base64Data != null) {
                              await _handleBase64Share(
                                base64Data,
                                fileName ?? 'receipt.png',
                              );
                            } else if (url != null) {
                              await _handleUrlShare(
                                url,
                                fileName ?? 'receipt.png',
                              );
                            } else if (text != null) {
                              await _handleShare(text);
                            }
                          }
                        }
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'requestMicrophonePermission',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected requestMicrophonePermission from untrusted origin',
                          );
                          return false;
                        }
                        final status = await Permission.microphone.request();
                        if (!status.isGranted) {
                          _showRuntimePermissionDeniedDialog(Permission.microphone);
                          return false;
                        }
                        return true;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'downloadBase64File',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected downloadBase64File from untrusted origin',
                          );
                          return false;
                        }
                        if (args.isEmpty || args[0] is! Map) return false;

                        try {
                          final data = Map<String, dynamic>.from(args[0] as Map);
                          final rawData = data['data'] as String?;
                          final requestedName = data['fileName'] as String?;
                          final requestedMime = data['mimeType'] as String?;

                          if (rawData == null || rawData.trim().isEmpty) return false;

                          final commaIndex = rawData.indexOf(',');
                          final cleanBase64 = commaIndex >= 0
                              ? rawData.substring(commaIndex + 1)
                              : rawData;
                          if (cleanBase64.isEmpty) return false;

                          final bytes = base64.decode(cleanBase64);
                          final fileName = _sanitizeFileName(
                            requestedName ?? 'downloaded_file',
                            requestedMime,
                          );

                          final tempDir = await getTemporaryDirectory();
                          final tempPath = '${tempDir.path}/temp_$fileName';
                          final tempFile = File(tempPath);
                          await tempFile.writeAsBytes(bytes, flush: true);

                          String savedPath;
                          if (Platform.isAndroid) {
                            const channel = MethodChannel(
                              'com.eglobal.wallet/mediastore',
                            );
                            final publicPath =
                                await channel.invokeMethod<String>(
                              'saveToDownloads',
                              {
                                'tempFilePath': tempPath,
                                'fileName': fileName,
                                'mimeType': requestedMime ?? '*/*',
                              },
                            );
                            if (publicPath == null || publicPath.isEmpty) {
                              throw Exception(
                                'Failed to save generated file to Downloads',
                              );
                            }
                            savedPath = publicPath;
                          } else {
                            final dirPath = await _getDownloadDirectoryPath();
                            var filePath = '$dirPath/$fileName';
                            var counter = 1;
                            final dot = fileName.lastIndexOf('.');
                            final baseName =
                                dot > 0 ? fileName.substring(0, dot) : fileName;
                            final extension =
                                dot > 0 ? fileName.substring(dot) : '';

                            while (await File(filePath).exists()) {
                              filePath =
                                  '$dirPath/${baseName}_$counter$extension';
                              counter++;
                            }

                            final target = File(filePath);
                            await tempFile.copy(target.path);
                            await tempFile.delete();
                            savedPath = target.path;
                          }

                          AppLogger.i(
                            'Generated file saved successfully: $fileName',
                          );
                          return {
                            'success': true,
                            'fileName': fileName,
                            'path': savedPath,
                          };
                        } catch (e) {
                          AppLogger.e('Generated file download failed', e);
                          return false;
                        }
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'requestContactsPermission',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected requestContactsPermission from untrusted origin',
                          );
                          return false;
                        }
                        final status = await Permission.contacts.request();
                        if (!status.isGranted && !status.isLimited) {
                          _showRuntimePermissionDeniedDialog(Permission.contacts);
                          return false;
                        }
                        return true;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'pickContact',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e('Rejected pickContact request from untrusted origin');
                          return null;
                        }
                        try {
                          final status = await Permission.contacts.request();
                          if (!status.isGranted && !status.isLimited) {
                            _showRuntimePermissionDeniedDialog(Permission.contacts);
                            return null;
                          }

                          final contact = await FlutterContacts.openExternalPick();
                          if (contact == null) return null;

                          final fullContact = await FlutterContacts.getContact(contact.id);
                          final selected = fullContact ?? contact;

                          final name = selected.displayName.trim();
                          final phones = selected.phones.map((p) => p.number.replaceAll(RegExp(r'\s+'), '')).where((p) => p.isNotEmpty).toList();
                          final emails = selected.emails.map((e) => e.address.trim()).where((e) => e.isNotEmpty).toList();

                          return {
                            'displayName': name,
                            'primaryPhone': phones.isNotEmpty ? phones.first : '',
                            'phones': phones,
                            'primaryEmail': emails.isNotEmpty ? emails.first : '',
                            'emails': emails,
                          };
                        } catch (e) {
                          AppLogger.e('Error picking contact', e);
                          return null;
                        }
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'getRememberedEmail',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected getRememberedEmail from untrusted origin',
                          );
                          return '';
                        }
                        final secureStorage = ref.read(secureStorageProvider);
                        return (await secureStorage.read(
                              AppStrings.savedEmailKey,
                            )) ??
                            '';
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'saveRememberedEmail',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected saveRememberedEmail from untrusted origin',
                          );
                          return;
                        }
                        if (args.isNotEmpty && args[0] is String) {
                          final email = (args[0] as String).trim();
                          if (email.isNotEmpty && email.contains('@')) {
                            final secureStorage = ref.read(
                              secureStorageProvider,
                            );
                            await secureStorage.write(
                              AppStrings.savedEmailKey,
                              email,
                            );
                            AppLogger.i(
                              'Securely stored remembered user email address',
                            );
                          }
                        }
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'clearRememberedEmail',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected clearRememberedEmail from untrusted origin',
                          );
                          return;
                        }
                        final secureStorage = ref.read(secureStorageProvider);
                        await secureStorage.delete(AppStrings.savedEmailKey);
                        AppLogger.i('Cleared remembered user email address');
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'shareReceipt',
                      callback: (args) async {
                        if (!await _isCurrentUrlTrusted(controller)) {
                          AppLogger.e(
                            'Rejected shareReceipt request from untrusted origin',
                          );
                          return;
                        }
                        if (args.isNotEmpty) {
                          final receiptData = args[0];
                          if (receiptData is String) {
                            await _handleShare(receiptData);
                          } else if (receiptData is Map) {
                            final text = receiptData['text'] as String?;
                            final base64 = receiptData['base64'] as String?;
                            final fileName = receiptData['fileName'] as String?;
                            if (base64 != null) {
                              await _handleBase64Share(
                                base64,
                                fileName ?? 'receipt.pdf',
                              );
                            } else if (text != null) {
                              await _handleShare(text);
                            }
                          }
                        }
                      },
                    );

                    if (_pendingRedirectPath != null) {
                      final path = _pendingRedirectPath!;
                      _pendingRedirectPath = null;
                      _handleNotificationRedirect(path);
                    }
                  },
                  onLoadStart: (controller, url) {
                    _loadAttemptId++;
                    _mainFrameLoading = true;
                    _loadingMainFrameUrl = url?.toString();
                    if (_isUserRetrying) {
                      _recoveryAttemptId = _loadAttemptId;
                      _recoveryCompleted = false;
                    }

                    if (url != null && !_offlineNavigationInProgress) {
                      _currentUrl = url.toString();
                    }
                    _startLoadingTimer();
                    webViewNotifier.setLoading(true);
                    webViewNotifier.setError(false);
                  },
                  onLoadStop: (controller, url) async {
                    _stopLoadingTimer();
                    webViewNotifier.setLoading(false);

                    final completedAttemptId = _loadAttemptId;
                    final completedRecoveryId = _recoveryAttemptId;
                    _mainFrameLoading = false;
                    _loadingMainFrameUrl = null;

                    final urlString = url?.toString().toLowerCase() ?? '';
                    final isErrorUrl = urlString.isEmpty ||
                        urlString.startsWith('about:') ||
                        urlString.startsWith('chrome-error:') ||
                        urlString.contains('net::err_');

                    final isTrustedUrl = url != null &&
                        (AppStrings.isTrustedWalletOrigin(url) ||
                         AppStrings.isTrustedGatewayOrigin(url));

                    final fullyLoadedTrustedPage = !isErrorUrl && isTrustedUrl;

                    if (fullyLoadedTrustedPage) {
                      final loadedUrl = url.toString();
                      _successfullyLoadedUrls.add(loadedUrl);
                      _lastSuccessfulUrl = loadedUrl;
                    }

                    final connectivity = ref.read(connectivityServiceProvider);
                    final isConnected = await connectivity.isConnected;

                    if (mounted &&
                        _offlineNavigationInProgress &&
                        !_offlineNavigationRestoring &&
                        !isErrorUrl &&
                        isTrustedUrl) {
                      _offlineNavigationInProgress = false;
                      _offlineNavigationOriginUrl = null;
                      _currentUrl = url.toString();
                      _lastSuccessfulUrl = url.toString();
                      setState(() {
                        _isOnline = false;
                        _hasLoadError = false;
                        _isCrashing = false;
                        _isUserRetrying = false;
                      });
                    }

                    if (mounted) {
                      final isValidRecovery = completedRecoveryId != null &&
                          completedRecoveryId == completedAttemptId &&
                          !_recoveryCompleted &&
                          !isErrorUrl &&
                          isTrustedUrl;

                      if (_hasLoadError) {
                        if (isValidRecovery) {
                          _recoveryCompleted = true;
                          _recoveryAttemptId = null;
                          _offlineNavigationInProgress = false;
                          _offlineNavigationRestoring = false;
                          _currentUrl = url.toString();
                          _lastSuccessfulUrl = url.toString();
                          setState(() {
                            _hasLoadError = false;
                            _isCrashing = false;
                            _isUserRetrying = false;
                          });
                          await controller.setSettings(
                            settings: InAppWebViewSettings(
                              cacheMode: CacheMode.LOAD_CACHE_ELSE_NETWORK,
                              networkAvailable: true,
                            ),
                          );
                        } else {
                          setState(() {
                            _isOnline = isConnected;
                            _hasLoadError = true;
                            _isUserRetrying = false;
                          });
                        }
                      } else if (isErrorUrl || !isTrustedUrl) {
                        setState(() {
                          _isOnline = isConnected;
                          _hasLoadError = true;
                        });
                      } else {
                        _currentUrl = url.toString();
                        _lastSuccessfulUrl = url.toString();
                        _offlineNavigationInProgress = false;
                        _offlineNavigationRestoring = false;
                        setState(() {
                          _isOnline = isConnected;
                        });
                      }
                    }

                      _restoreSystemUi();
                    await _injectSecurityAndAutofillScripts(controller);
                  },
                  onProgressChanged: (controller, progress) {
                    webViewNotifier.setProgress(progress / 100);
                  },
                  onReceivedError: (controller, request, error) async {
                    AppLogger.e(
                      'WebView error handled: ${error.description}',
                    );
                    if (request.isForMainFrame == true) {
                      _restoreSystemUi();

                      if (_offlineNavigationInProgress && !_offlineNavigationRestoring) {
                        _offlineNavigationRestoring = true;
                        _offlineNavigationInProgress = false;
                        _stopLoadingTimer();
                        final previousUrl = _offlineNavigationOriginUrl;
                        if (previousUrl != null) {
                          try {
                            if (await controller.canGoBack()) {
                              await controller.goBack();
                              return;
                            }
                            await controller.loadUrl(
                              urlRequest: URLRequest(url: WebUri(previousUrl)),
                            );
                            return;
                          } catch (e) {
                            AppLogger.e('Failed to restore page', e);
                          }
                        }
                        if (mounted) {
                          setState(() {
                            _hasLoadError = true;
                            _isUserRetrying = false;
                          });
                        }
                        return;
                      }

                      if (_isUserRetrying) return;
                      if (!_mainFrameLoading) return;

                      final attemptAtCallback = _loadAttemptId;
                      final loadingUrlAtCallback = _loadingMainFrameUrl;
                      final requestUrl = request.url.toString();

                      _stopLoadingTimer();
                      final connectivity = ref.read(connectivityServiceProvider);
                      final isConnected = await connectivity.isConnected;

                      if (mounted &&
                          _mainFrameLoading &&
                          _loadAttemptId == attemptAtCallback &&
                          _loadingMainFrameUrl == loadingUrlAtCallback &&
                          (loadingUrlAtCallback == null ||
                              requestUrl == loadingUrlAtCallback)) {
                        _mainFrameLoading = false;
                        _recoveryAttemptId = null;
                        setState(() {
                          _isOnline = isConnected;
                          _hasLoadError = true;
                          _isCrashing = false;
                          _isUserRetrying = false;
                        });
                      }
                    }
                  },
                  onReceivedHttpError: (controller, request, errorResponse) async {
                    AppLogger.e(
                      'WebView HTTP error handled: ${errorResponse.statusCode}',
                    );
                    if ((request.isForMainFrame == true) &&
                        (errorResponse.statusCode ?? 200) >= 400) {
                      _restoreSystemUi();
                      if (_offlineNavigationInProgress && !_offlineNavigationRestoring) {
                        _offlineNavigationRestoring = true;
                        _offlineNavigationInProgress = false;
                        _stopLoadingTimer();
                        final previousUrl = _offlineNavigationOriginUrl;
                        if (previousUrl != null) {
                          try {
                            if (await controller.canGoBack()) {
                              await controller.goBack();
                              return;
                            }
                            await controller.loadUrl(
                              urlRequest: URLRequest(url: WebUri(previousUrl)),
                            );
                            return;
                          } catch (e) {
                            AppLogger.e('Failed to restore page', e);
                          }
                        }
                        if (mounted) {
                          setState(() {
                            _hasLoadError = true;
                            _isUserRetrying = false;
                          });
                        }
                        return;
                      }

                      if (_isUserRetrying) return;
                      if (!_mainFrameLoading) return;

                      final attemptAtCallback = _loadAttemptId;
                      final loadingUrlAtCallback = _loadingMainFrameUrl;
                      final requestUrl = request.url.toString();

                      _stopLoadingTimer();
                      _restoreSystemUi();
                      final connectivity = ref.read(connectivityServiceProvider);
                      final isConnected = await connectivity.isConnected;

                      if (mounted &&
                          _mainFrameLoading &&
                          _loadAttemptId == attemptAtCallback &&
                          _loadingMainFrameUrl == loadingUrlAtCallback &&
                          (loadingUrlAtCallback == null ||
                              requestUrl == loadingUrlAtCallback)) {
                        _mainFrameLoading = false;
                        _recoveryAttemptId = null;
                        setState(() {
                          _isOnline = isConnected;
                          _hasLoadError = true;
                          _isCrashing = false;
                          _isUserRetrying = false;
                        });
                      }
                    }
                  },
                  onReceivedServerTrustAuthRequest: (controller, challenge) async {
                    AppLogger.e(
                      'WebView SSL/Trust authentication requested for host: ${challenge.protectionSpace.host}',
                    );
                    return ServerTrustAuthResponse(
                      action: ServerTrustAuthResponseAction.CANCEL,
                    );
                  },
                  onJsAlert: (controller, jsAlertRequest) async {
                    final msg = _sanitizeStringForDisplayOrShare(
                      jsAlertRequest.message ?? '',
                    );
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        title: const Text(
                          'E-Global Pay',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content: Text(msg),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'OK',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    return JsAlertResponse(
                      action: JsAlertResponseAction.CONFIRM,
                    );
                  },
                  onJsConfirm: (controller, jsConfirmRequest) async {
                    final msg = _sanitizeStringForDisplayOrShare(
                      jsConfirmRequest.message ?? '',
                    );
                    final bool? result = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        title: const Text(
                          'E-Global Pay',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content: Text(msg),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text(
                              'Confirm',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    return JsConfirmResponse(
                      action: (result ?? false)
                          ? JsConfirmResponseAction.CONFIRM
                          : JsConfirmResponseAction.CANCEL,
                    );
                  },
                  onJsPrompt: (controller, jsPromptRequest) async {
                    final msg = _sanitizeStringForDisplayOrShare(
                      jsPromptRequest.message ?? '',
                    );
                    final TextEditingController textController =
                        TextEditingController(
                          text: jsPromptRequest.defaultValue,
                        );
                    final String? result = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        title: const Text(
                          'E-Global Pay',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(msg),
                            const SizedBox(height: 8),
                            TextField(controller: textController),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(null),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop(textController.text),
                            child: const Text(
                              'OK',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    return JsPromptResponse(
                      value: result,
                      action: result != null
                          ? JsPromptResponseAction.CONFIRM
                          : JsPromptResponseAction.CANCEL,
                    );
                  },
                  onPermissionRequest: (controller, request) async {
                    return await _handlePermissionRequest(controller, request);
                  },
                  onDownloadStartRequest: (controller, request) async {
                    await _handleDownload(
                      request.url.toString(),
                      request.userAgent,
                      request.contentDisposition,
                      request.mimeType,
                      request.contentLength,
                    );
                  },
                ),
              ),
              ),
              if (_hasLoadError || _isCrashing)
                Positioned.fill(
                  child: _buildSensitiveOfflineErrorUi(),
                ),
              if (_isDownloading)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DownloadProgressBar(
                    progress: _downloadProgress,
                    fileName: _downloadingFileName,
                  ),
                ),
              if (_isInBackground)
                Positioned.fill(
                  child: Container(
                    color: AppColors.primary,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/logo.png',
                            width: 52,
                            height: 52,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            AppStrings.appName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
