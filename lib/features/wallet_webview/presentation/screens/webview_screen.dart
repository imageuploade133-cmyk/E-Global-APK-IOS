import 'dart:io';
import 'dart:async';
import 'dart:convert';
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
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/services/core_providers.dart';
import 'package:wallet/core/utils/logger.dart';
import '../widgets/download_progress_bar.dart';
import '../controllers/webview_controller.dart';

class WebviewScreen extends ConsumerStatefulWidget {
  const WebviewScreen({super.key});

  @override
  ConsumerState<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends ConsumerState<WebviewScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<String>? _redirectSubscription;
  bool _isOnline = true;
  String? _pendingRedirectPath;

  double _downloadProgress = 0.0;
  String _downloadingFileName = '';
  bool _isDownloading = false;

  // Bleached Clean White constant color to eliminate black/white/colored layout flashes
  static const int _maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB max limit

  static const Color bleachWhite = Colors.white;

  // Base64 logo to render perfectly offline inside local HTML loaders
  String _logoBase64 = '';

  bool _isInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _loadLogoAsset();
    _initConnectivity();
    _initPushNotifications();

    // Safety fallback: Ensure native splash screen is always removed after a short timeout under all circumstances
    Timer(const Duration(seconds: 3), () {
      try {
        FlutterNativeSplash.remove();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _redirectSubscription?.cancel();
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

  Future<void> _loadLogoAsset() async {
    try {
      final bytes = await rootBundle.load('assets/images/logo.png');
      final list = bytes.buffer.asUint8List();
      if (mounted) {
        setState(() {
          _logoBase64 = base64Encode(list);
        });
      }
    } catch (e) {
      AppLogger.e('Error converting logo to base64', e);
    }
  }

  Future<void> _initConnectivity() async {
    final connectivity = ref.read(connectivityServiceProvider);
    _isOnline = await connectivity.isConnected;
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

    // Register the redirect listener FIRST so we catch any initial broadcasted messages on bootup
    _redirectSubscription = pushService.onNotificationRedirectStream.listen((
      path,
    ) {
      _handleNotificationRedirect(path);
    });

    // Initialize Push notifications (including processing initial messages)
    await pushService.initialize();
  }

  String _buildRedirectUrl(String path) {
    final baseUrl = AppStrings.baseUrl;
    final cleanBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$cleanBase$cleanPath';
  }

  void _handleNotificationRedirect(String path) {
    if (_webViewController != null && path.isNotEmpty) {
      final fullUrl = _buildRedirectUrl(path);
      _webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(fullUrl)));
    } else {
      _pendingRedirectPath = path;
    }
  }

  Future<void> _handleConnectivityChange(bool isConnected) async {
    if (_webViewController != null) {
      final cacheMode = isConnected
          ? CacheMode.LOAD_DEFAULT
          : CacheMode.LOAD_CACHE_ELSE_NETWORK;
      await _webViewController!.setSettings(
        settings: InAppWebViewSettings(cacheMode: cacheMode),
      );
    }
  }

  CacheMode _getCurrentCacheMode() {
    return _isOnline
        ? CacheMode.LOAD_DEFAULT
        : CacheMode.LOAD_CACHE_ELSE_NETWORK;
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
    if (permission == Permission.notification) return 'Real-time Alerts';
    return permission.toString();
  }

  Future<PermissionResponse?> _handlePermissionRequest(
    InAppWebViewController controller,
    PermissionRequest permissionRequest,
  ) async {
    final List<Permission> permissionsToRequest = [];

    for (final resource in permissionRequest.resources) {
      if (resource.toString().contains('AUDIO_CAPTURE') ||
          resource.toString().contains('microphone')) {
        permissionsToRequest.add(Permission.microphone);
      } else if (resource.toString().contains('VIDEO_CAPTURE') ||
          resource.toString().contains('camera')) {
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

  static const Set<String> _allowedFileExtensions = {
    '.pdf',
    '.png',
    '.jpg',
    '.jpeg',
    '.docx',
    '.xlsx',
    '.pptx',
    '.txt',
    '.csv',
    '.zip',
  };

  String _sanitizeFileName(String rawName) {
    var name = rawName.split('?').first.split('#').first;
    name = name.replaceAll(RegExp(r'[\\/:\*\?"<>\|]'), '_');
    name = name.replaceAll(RegExp(r'^\.+'), '');
    if (name.trim().isEmpty) name = 'downloaded_receipt';

    // Verify file extension safety
    final lower = name.toLowerCase();
    final hasAllowedExt = _allowedFileExtensions.any(
      (ext) => lower.endsWith(ext),
    );
    if (!hasAllowedExt) {
      name = '$name.pdf';
    }
    return name;
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
      if (uri.scheme.toLowerCase() != 'https') {
        AppLogger.e('Rejected insecure download URL: $url');
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
        AppLogger.e('Rejected download from untrusted host: ${uri.host}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download rejected: Untrusted domain.'),
            ),
          );
        }
        return;
      }

      final permissionService = ref.read(permissionServiceProvider);
      final hasStoragePermission = await permissionService
          .requestStoragePermission();
      if (!hasStoragePermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required for downloading.'),
            ),
          );
        }
        return;
      }

      final rawFileName = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'receipt.pdf';
      final fileName = _sanitizeFileName(rawFileName);

      setState(() {
        _isDownloading = true;
        _downloadingFileName = fileName;
        _downloadProgress = 0.1;
      });

      final client = HttpClient();
      final request = await client.getUrl(uri);
      if (userAgent != null && userAgent.isNotEmpty) {
        request.headers.set('User-Agent', userAgent);
      }
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP Error ${response.statusCode} while downloading file.',
        );
      }

      final dirPath = await _getDownloadDirectoryPath();
      final filePath = '$dirPath/$fileName';
      partialFile = File(filePath);

      await partialFile.parent.create(recursive: true);
      final sink = partialFile.openWrite();

      final total = response.contentLength > 0
          ? response.contentLength
          : contentLength;
      int received = 0;

      await for (final chunk in response) {
        received += chunk.length;
        if (received > _maxFileSizeBytes) {
          await sink.close();
          throw Exception('Download size exceeds maximum 25MB limit.');
        }
        sink.add(chunk);
        if (total > 0 && mounted) {
          setState(() {
            _downloadProgress = (received / total).clamp(0.0, 1.0);
          });
        }
      }
      await sink.flush();
      await sink.close();

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: $fileName'),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.orange,
              onPressed: () async {
                await OpenFilex.open(filePath);
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
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/eglobal_downloads';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  Future<void> _handleShare(String text) async {
    try {
      final sanitizedText = text
          .replaceAll(AppStrings.baseUrl, '')
          .replaceAll('https://e-global-197077.vercel.app/', '');
      await Share.share(sanitizedText, subject: 'E-Global Wallet Receipt');
    } catch (e) {
      AppLogger.e('Error sharing text', e);
    }
  }

  Future<void> _handleBase64Share(String base64Data, String fileName) async {
    try {
      final cleanBase64 = base64Data.contains(',')
          ? base64Data.split(',').last
          : base64Data;

      // Validate base64 payload size prior to decoding to prevent OOM
      if (cleanBase64.length > (_maxFileSizeBytes * 4 / 3)) {
        AppLogger.e('Base64 share payload exceeds maximum allowed size (25MB)');
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
      ], text: 'E-Global Wallet Receipt');
    } catch (e) {
      AppLogger.e('Error sharing base64 receipt', e);
    }
  }

  Future<void> _handleUrlShare(String url, String fileName) async {
    File? tempFile;
    try {
      final uri = Uri.parse(url);
      if (uri.scheme.toLowerCase() != 'https') {
        AppLogger.e('Rejected insecure receipt share URL: $url');
        return;
      }

      if (!AppStrings.isTrustedWalletOrigin(uri)) {
        AppLogger.e('Rejected receipt share from untrusted host: ${uri.host}');
        return;
      }

      final safeName = _sanitizeFileName(fileName);
      final client = HttpClient();
      final request = await client.getUrl(uri);

      // Retrieve and forward WebView session cookies to support authenticated receipt downloads
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
      int received = 0;

      await for (final chunk in response) {
        received += chunk.length;
        if (received > _maxFileSizeBytes) {
          await sink.close();
          throw Exception('Receipt file size exceeds maximum 25MB limit.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      await Share.shareXFiles([
        XFile(tempPath),
      ], text: 'E-Global Wallet Receipt');
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
          'Are you sure you want to close E-Global Wallet? Any unsaved operations may be lost.',
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
      SystemNavigator.pop();
    }
  }

  Future<bool> _isCurrentUrlTrusted(InAppWebViewController controller) async {
    try {
      final currentUrl = await controller.getUrl();
      if (currentUrl == null) return false;
      final expectedUri = Uri.parse(AppStrings.baseUrl);
      return currentUrl.scheme == 'https' &&
          currentUrl.host.toLowerCase() == expectedUri.host.toLowerCase();
    } catch (e) {
      AppLogger.e('Error validating URL origin', e);
      return false;
    }
  }

  // Fallback to beautiful branded screen if WebView fails to load, preventing Chromium Webpage not available from showing
  void _loadElegantFallback() {
    final cleanLogoBase64 = _logoBase64.replaceAll(
      RegExp(r'[^A-Za-z0-9+/=]'),
      '',
    );
    final logoSrc = cleanLogoBase64.isNotEmpty
        ? "data:image/png;base64,$cleanLogoBase64"
        : "";

    _webViewController?.loadData(
      data:
          """
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <title>Loading</title>
        <style>
          body {
            background-color: #ffffff;
            margin: 0;
            padding: 0;
            height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            overflow: hidden;
            font-family: system-ui, -apple-system, BlinkMacSystemFont, Roboto, sans-serif;
          }
          .loader-container {
            position: relative;
            display: flex;
            justify-content: center;
            align-items: center;
            width: 100px;
            height: 100px;
          }
          .gradient-spinner {
            width: 72px;
            height: 72px;
            border-radius: 50%;
            padding: 4px;
            background: conic-gradient(from 0deg, #f67c01, #ffcc80, transparent 65%);
            -webkit-mask: radial-gradient(farthest-side, transparent calc(100% - 5px), #000 0);
            mask: radial-gradient(farthest-side, transparent calc(100% - 5px), #000 0);
            animation: spin 1s linear infinite;
          }
          .logo-icon {
            position: absolute;
            width: 36px;
            height: 36px;
            object-fit: contain;
          }
          @keyframes spin {
            to { transform: rotate(360deg); }
          }
        </style>
      </head>
      <body>
        <div class="loader-container">
          <div class="gradient-spinner"></div>
          ${logoSrc.isNotEmpty ? '<img class="logo-icon" src="$logoSrc" alt="Logo" />' : ''}
        </div>
        <div style="position: absolute; bottom: 40px; text-align: center;">
          <p style="color: #666; font-size: 14px; margin-bottom: 12px;">Connection problem. Check your internet.</p>
          <button id="retryBtn" style="background-color: #f67c01; color: white; border: none; padding: 10px 20px; border-radius: 8px; font-weight: bold; cursor: pointer;">Try Again</button>
        </div>
        <script>
          document.getElementById('retryBtn').addEventListener('click', function() {
            window.location.href = "${AppStrings.baseUrl}";
          });
        </script>
      </body>
      </html>
    """,
      baseUrl: WebUri(AppStrings.baseUrl),
    );
  }

  @override
  Widget build(BuildContext context) {
    final webViewNotifier = ref.read(webViewProvider.notifier);

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
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri(AppStrings.baseUrl),
                  ),
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
                    // Enforce HTTPS-only content security and disallow mixed HTTP content
                    mixedContentMode:
                        MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    // Robust 100% offline support cache configuration
                    cacheMode: _getCurrentCacheMode(),
                    // Remove all window/viewport margins, backgrounds, and styling issues
                    transparentBackground: true,
                    // Enable high fidelity viewport dynamic scaling for smaller devices
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    supportZoom: false,
                    // Restrict third-party cookies by default to protect cross-site user sessions
                    thirdPartyCookiesEnabled: false,
                    sharedCookiesEnabled: true,
                    // Disallow local file system access from web context
                    allowFileAccess: false,
                    allowFileAccessFromFileURLs: false,
                    allowUniversalAccessFromFileURLs: false,
                  ),
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final uri = navigationAction.request.url;
                    if (uri == null) return NavigationActionPolicy.CANCEL;

                    final scheme = uri.scheme.toLowerCase();
                    final urlString = uri.toString();

                    // Handle native share triggers safely
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

                    // Always allow internal navigation within the primary wallet domain
                    if (AppStrings.isTrustedWalletOrigin(uri)) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    // Handle standard safe external communications (tel, mailto, whatsapp, SMS)
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

                    // Allow trusted third-party payment provider / KYC host gateways
                    if (AppStrings.isTrustedGatewayOrigin(uri)) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    // For all other external HTTPS URLs, open in the external system browser to avoid untrusted web takeover
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

                    // Block file://, javascript:, data:, and unknown schemes
                    AppLogger.e(
                      'Blocked unsafe/unknown navigation request to: $urlString',
                    );
                    return NavigationActionPolicy.CANCEL;
                  },
                  onWebViewCreated: (controller) {
                    _webViewController = controller;

                    // Register the controller with pushNotificationService for dynamic JavaScript callbacks
                    final pushService = ref.read(
                      pushNotificationServiceProvider,
                    );
                    pushService.setWebViewController(controller);

                    // Expose 'getFcmToken' handler to the web app with strict origin check
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

                    // Expose 'requestNotificationPermission' handler to the web app with strict origin check
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

                    // Expose generic 'share' handler to the web app with origin validation
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

                    // Expose receipt-specific 'shareReceipt' handler to the web app with origin validation
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

                    // Execute any pending redirect from cold boot / terminated state
                    if (_pendingRedirectPath != null) {
                      final path = _pendingRedirectPath!;
                      _pendingRedirectPath = null;
                      _handleNotificationRedirect(path);
                    }
                  },
                  onLoadStart: (controller, url) {
                    webViewNotifier.setLoading(true);
                    webViewNotifier.setError(false);
                  },
                  onLoadStop: (controller, url) async {
                    webViewNotifier.setLoading(false);

                    // Dismiss the native splash screen seamlessly once the page has fully loaded
                    FlutterNativeSplash.remove();
                  },
                  onProgressChanged: (controller, progress) {
                    webViewNotifier.setProgress(progress / 100);
                  },
                  onReceivedError: (controller, request, error) {
                    // Suppress all browser errors and ignore load errors.
                    // This guarantees that the user is always presented with the last cached/rendered page
                    // and never sees any default browser error pages containing raw web URLs or standard crash alerts.
                    AppLogger.e(
                      'WebView silent non-blocking error handled: ${error.description}',
                    );

                    if (request.isForMainFrame ?? true) {
                      _loadElegantFallback();
                    }
                  },
                  onReceivedHttpError: (controller, request, errorResponse) {
                    AppLogger.e(
                      'WebView HTTP error handled: ${errorResponse.statusCode}',
                    );
                    if (request.isForMainFrame ?? true) {
                      _loadElegantFallback();
                    }
                  },
                  onReceivedServerTrustAuthRequest: (controller, challenge) async {
                    AppLogger.e(
                      'WebView SSL/Trust authentication requested for host: ${challenge.protectionSpace.host}',
                    );
                    // Return cancel to safely handle SSL errors / protect connection in production
                    return ServerTrustAuthResponse(
                      action: ServerTrustAuthResponseAction.CANCEL,
                    );
                  },
                  onJsAlert: (controller, jsAlertRequest) async {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        title: const Text(
                          'E-Global Wallet',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content: Text(jsAlertRequest.message ?? ''),
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
                    final bool? result = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        title: const Text(
                          'E-Global Wallet',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content: Text(jsConfirmRequest.message ?? ''),
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
                          'E-Global Wallet',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(jsPromptRequest.message ?? ''),
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
                            width: 100,
                            height: 100,
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
