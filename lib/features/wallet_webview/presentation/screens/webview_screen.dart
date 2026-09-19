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
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/services/core_providers.dart';
import 'package:wallet/core/utils/logger.dart';
import '../../../offline/offline_screen.dart';
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
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<String>? _redirectSubscription;
  bool _isOnline = true;
  String? _pendingRedirectPath;

  double _downloadProgress = 0.0;
  String _downloadingFileName = '';
  bool _isDownloading = false;

  bool _hasLoadError = false;
  bool _isCrashing = false;
  Timer? _loadingTimeoutTimer;

  // Bleached Clean White constant color to eliminate black/white/colored layout flashes
  static const int _maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB max limit

  static const Color bleachWhite = Colors.white;

  bool _isInBackground = false;
  bool _hasRestoredSystemUi = false;

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
    _initConnectivity();
    _initPushNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _redirectSubscription?.cancel();
    _loadingTimeoutTimer?.cancel();
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
          if (isConnected && _hasLoadError) {
            _hasLoadError = false;
            _isCrashing = false;
          }
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
      _startLoadingTimer();
      _webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(fullUrl)));
    } else {
      _pendingRedirectPath = path;
    }
  }

  void _startLoadingTimer() {
    _loadingTimeoutTimer?.cancel();
    // If page load takes longer than 20 seconds, hide webview and show try again overlay
    _loadingTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && (_hasLoadError == false)) {
        AppLogger.e('Page loading timed out (slow connection)');
        setState(() {
          _hasLoadError = true;
          _isCrashing = false;
        });
      }
    });
  }

  void _stopLoadingTimer() {
    _loadingTimeoutTimer?.cancel();
  }

  Future<void> _checkConnectionAndReload() async {
    final connectivity = ref.read(connectivityServiceProvider);
    final isConnected = await connectivity.isConnected;
    setState(() {
      _isOnline = isConnected;
    });

    if (!isConnected) {
      return;
    }

    if (mounted) {
      setState(() {
        _hasLoadError = false;
        _isCrashing = false;
      });
      _startLoadingTimer();
      if (_webViewController != null) {
        await _webViewController!.reload();
      }
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

      // Storage permission check omitted for internal app documents directory on modern SDKs (Android 10+ / iOS)
      // to avoid unnecessary 'restricted' errors or OS denials.

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
      final sanitizedText = _sanitizeStringForDisplayOrShare(text);
      await Share.share(sanitizedText, subject: 'E-Global Pay Receipt');
    } catch (e) {
      AppLogger.e('Error sharing text', e);
    }
  }

  String _sanitizeStringForDisplayOrShare(String input) {
    var result = input;
    result = result.replaceAll(AppStrings.baseUrl, '');
    result = result.replaceAll('https://e-global-197077.vercel.app/', '');
    result = result.replaceAll('https://e-global-197077.vercel.app', '');
    result = result.replaceAll('e-global-197077.vercel.app', '');
    return result;
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
      ], text: 'E-Global Pay Receipt');
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

  Future<void> _injectSecurityAndAutofillScripts(
    InAppWebViewController controller,
  ) async {
    try {
      await controller.evaluateJavascript(source: """
        (function() {
          function applyFormSecurityAndUI() {
            // Disable scrollbars globally via CSS
            if (!document.getElementById('eglobal-hide-scrollbars')) {
              var style = document.createElement('style');
              style.id = 'eglobal-hide-scrollbars';
              style.innerHTML = `
                ::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }
                * {
                  scrollbar-width: none !important;
                  -ms-overflow-style: none !important;
                  -webkit-touch-callout: none !important;
                }
              `;
              (document.head || document.documentElement).appendChild(style);
            }

            // Disable form autofill globally
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

  Future<void> _injectRememberEmailScript(
    InAppWebViewController controller,
  ) async {
    try {
      await controller.evaluateJavascript(source: """
        (function() {
          function setupRememberEmail() {
            var emailInputs = document.querySelectorAll('input[type="email"], input[name*="email" i], input[id*="email" i]');
            if (emailInputs.length === 0) return;

            window.flutter_inappwebview.callHandler('getRememberedEmail').then(function(savedEmail) {
              if (savedEmail && savedEmail.length > 0) {
                emailInputs.forEach(function(input) {
                  if (!input.dataset.emailPopulated && (!input.value || input.value.trim() === '')) {
                    input.value = savedEmail;
                    input.dataset.emailPopulated = 'true';
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                    input.dispatchEvent(new Event('change', { bubbles: true }));
                  }
                });
              }
            });

            emailInputs.forEach(function(input) {
              if (input.dataset.rememberEmailAttached) return;
              input.dataset.rememberEmailAttached = 'true';

              function handleEmailChange() {
                var val = input.value ? input.value.trim() : '';
                if (val.length > 0 && val.indexOf('@') !== -1) {
                  window.flutter_inappwebview.callHandler('saveRememberedEmail', val);
                } else if (val.length === 0) {
                  window.flutter_inappwebview.callHandler('clearRememberedEmail');
                }
              }

              input.addEventListener('blur', handleEmailChange);
              input.addEventListener('change', handleEmailChange);

              var form = input.closest('form');
              if (form && !form.dataset.rememberEmailAttached) {
                form.dataset.rememberEmailAttached = 'true';
                form.addEventListener('submit', function() {
                  handleEmailChange();
                });
              }
            });
          }

          setupRememberEmail();
        })();
      """);
    } catch (e) {
      AppLogger.e('Error injecting remember email script', e);
    }
  }


  @override
  Widget build(BuildContext context) {
    final webViewNotifier = ref.read(webViewProvider.notifier);

    // 1. Strictly show full OfflineScreen if network is disconnected
    if (!_isOnline) {
      return OfflineScreen(
        onRetry: _checkConnectionAndReload,
      );
    }

    // 2. Hide WebView and show custom Error Overlay on load failure or slow network timeout
    if (_hasLoadError || _isCrashing) {
      return WebviewErrorOverlay(
        title: _isCrashing
            ? AppStrings.webViewCrashTitle
            : AppStrings.webViewLoadErrorTitle,
        subtitle: _isCrashing
            ? AppStrings.webViewCrashSubtitle
            : AppStrings.webViewLoadErrorSubtitle,
        onRetry: _checkConnectionAndReload,
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
                    url: WebUri(AppStrings.baseUrl),
                  ),
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    UserScript(
                      source: """
                        (function() {
                          var style = document.createElement('style');
                          style.id = 'eglobal-hide-scrollbars';
                          style.innerHTML = `
                            html, body, div, p, span, iframe, section, article, nav, aside, main, header, footer, form, input, textarea, select {
                              scrollbar-width: none !important;
                              -ms-overflow-style: none !important;
                              -webkit-touch-callout: none !important;
                            }
                            ::-webkit-scrollbar {
                              display: none !important;
                              width: 0px !important;
                              height: 0px !important;
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
                    // Enforce HTTPS-only content security and disallow mixed HTTP content
                    mixedContentMode:
                        MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    scrollbarFadingEnabled: false,
                    scrollBarStyle: ScrollBarStyle.SCROLLBARS_INSIDE_OVERLAY,
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
                    final path = uri.path.toLowerCase();

                    // In offline mode, strictly block new server-changing or sensitive operations
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Active internet connection required for financial operations.'),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                    }

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

                    // Expose 'unregisterFcmToken' handler to the web app for secure native FCM unregistration on logout
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

                    // Expose 'getRememberedEmail' handler for secure email restoration
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

                    // Expose 'saveRememberedEmail' handler for secure email persistence
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

                    // Expose 'clearRememberedEmail' handler to clear saved email
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
                    _startLoadingTimer();
                    webViewNotifier.setLoading(true);
                    webViewNotifier.setError(false);
                  },
                  onLoadStop: (controller, url) async {
                    _stopLoadingTimer();
                    webViewNotifier.setLoading(false);

                    // Restore normal Android system UI and dismiss splash screen seamlessly once loaded
                    _restoreSystemUi();

                    // Inject form security, autofill prevention, and email restoration scripts
                    await _injectSecurityAndAutofillScripts(controller);
                    await _injectRememberEmailScript(controller);
                  },
                  onProgressChanged: (controller, progress) {
                    webViewNotifier.setProgress(progress / 100);
                  },
                  onReceivedError: (controller, request, error) async {
                    AppLogger.e(
                      'WebView error handled: ${error.description}',
                    );
                    if (request.isForMainFrame == true) {
                      _stopLoadingTimer();
                      final connectivity = ref.read(connectivityServiceProvider);
                      final isConnected = await connectivity.isConnected;
                      if (mounted) {
                        setState(() {
                          _isOnline = isConnected;
                          _hasLoadError = true;
                          _isCrashing = false;
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
                      _stopLoadingTimer();
                      final connectivity = ref.read(connectivityServiceProvider);
                      final isConnected = await connectivity.isConnected;
                      if (mounted) {
                        setState(() {
                          _isOnline = isConnected;
                          _hasLoadError = true;
                          _isCrashing = false;
                        });
                      }
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
