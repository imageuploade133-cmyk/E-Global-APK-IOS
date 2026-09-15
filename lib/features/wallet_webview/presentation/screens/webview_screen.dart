import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/logger.dart';
import '../../offline/offline_screen.dart';
import 'widgets/webview_error_overlay.dart';
import 'widgets/webview_loader.dart';

/// The main screen that wraps the InAppWebView with:
/// - Full-screen immersive mode
/// - Connectivity monitoring (blocks access when offline)
/// - WebView crash / load failure protection (hides WebView, shows error overlay)
/// - Loading indicator while page loads
class WebviewScreen extends ConsumerStatefulWidget {
  final String initialUrl;

  constWebviewScreen({
    super.key,
    this.initialUrl = 'https://e-global-197077.vercel.app/',
  });

  @override
  ConsumerState<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends ConsumerState<WebviewScreen> {
  InAppWebView? _webView;
  bool _isWebViewReady = false;
  bool _hasLoadError = false;
  bool _isCrashing = false;
  String? _lastUrl;

  late final StreamSubscription<bool> _connectivitySub;

  @override
  void initState() {
    super.initState();
    AppLogger.info('WebviewScreen initializing', tag: 'Webview');
    _subscribeConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _webView?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Connectivity monitoring — set up once in initState
  // ------------------------------------------------------------------
  void _subscribeConnectivity() {
    _connectivitySub = ref.listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
      next.whenData((connected) {
        if (!connected) {
          AppLogger.warning('Internet lost — showing offline screen', tag: 'Webview');
          _showOffline();
        } else {
          AppLogger.info('Internet restored — hiding offline screen', tag: 'Webview');
          _dismissOfflineAndMaybeReload();
        }
      });
    }).stream.listen((_) {});
  }

  void _showOffline() {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => constOfflineScreen(
          onRetry: _checkConnectionAndReload,
        ),
      );
    }
  }

  void _dismissOfflineAndMaybeReload() {
    // Dismiss the offline dialog if it's showing, then reload the WebView
    try {
      Navigator.of(context).pop();
    } catch (_) {
      // No dialog to pop — fine
    }
    _reload();
  }

  // ------------------------------------------------------------------
  // WebView creation
  // ------------------------------------------------------------------
  void _createWebView() {
    if (_webView != null) return;

    const settings = InAppWebViewSettings(
      useShouldOverrideUrlLoading: true,
      useOnLoadResource: true,
      mixedContentAllowed: false,
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      allowFileAccess: true,
      allowContentAccess: true,
      cacheMode: CacheMode.LOAD_CACHE_ELSE_NETWORK,
      cacheEnabled: true,
      thirdPartyCookiesEnabled: true,
      userAgent:
          'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      // Disable debugging in release for security
      inspectionEnabled: false,
      allowBlindAuthRequests: false,
      allowUniversalAccessFromFileURLs: false,
      allowFileAccessFromFileURLs: false,
    );

    _webView = InAppWebView(
      key: constValueKey('main_webview'),
      initialSettings: settings,
      initialUrlRequest: URLRequest(
        url: WebUri(widget.initialUrl),
        headers: {'User-Agent': settings.userAgent},
      ),
      onWebViewCreated: _onWebViewCreated,
      onLoadStart: _onLoadStart,
      onLoadStop: _onLoadStop,
      onLoadError: _onLoadError,
      onReceivedError: _onReceivedError,
      onReceivedHttpError: _onReceivedHttpError,
      onReceivedServerTrustError: _onReceivedServerTrustError,
      onConsentPolicyButtonClicked: _onConsentPolicyButtonClicked,
      onConsoleMessage: _onConsoleMessage,
      onPermissionRequest: _onPermissionRequest,
      onGeolocationPermissionsShowPrompt: _onGeolocationPermissionsShowPrompt,
      onSaveFormDataRequest: (control, url, formData) async {
        // Don't save form data for security
        return SaveFormDataRequestAction.IGNORE;
      },
    );
  }

  void _onWebViewCreated(InAppWebView webView) {
    AppLogger.info('WebView created successfully', tag: 'Webview');
    _isWebViewReady = true;
  }

  void _onLoadStart(InAppWebView webView, WebUri? url) {
    _lastUrl = url?.toString();
    AppLogger.debug('WebView load start: $_lastUrl', tag: 'Webview');
    setState(() {
      _hasLoadError = false;
      _isCrashing = false;
    });
  }

  void _onLoadStop(InAppWebView webView, WebUri? url) async {
    AppLogger.info('WebView load complete: ${url?.toString()}', tag: 'Webview');

    // Verify the page actually loaded by checking the title
    final title = await webView.getTitle();
    final isLoaded = title != null && title.isNotEmpty;

    if (!isLoaded && mounted) {
      AppLogger.warning(
        'WebView load stop but no title — treating as crash',
        tag: 'Webview',
      );
      setState(() {
        _hasLoadError = true;
        _isCrashing = true;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _hasLoadError = false;
        _isCrashing = false;
      });
    }
  }

  void _onLoadError(
    InAppWebView webView,
    WebUri url,
    int errorCode,
    String errorDescription,
  ) {
    AppLogger.error(
      'WebView load error: $errorDescription (code: $errorCode)',
      tag: 'Webview',
    );
    if (mounted) {
      setState(() {
        _hasLoadError = true;
        _isCrashing = false;
      });
    }
  }

  void _onReceivedError(
    InAppWebView webView,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    AppLogger.warning(
      'Web resource error: ${error.description} (code: ${error.errorCode}) '
      'for ${request.url?.toString()}',
      tag: 'Webview',
    );
    // Only treat as critical if it's a connection-level error
    if (error.errorCode == -1 || error.errorCode == -2) {
      // -1 = ERR_INTERNET_DISCONNECTED, -2 = ERR_NAME_NOT_RESOLVED, etc.
      if (mounted) {
        setState(() {
          _hasLoadError = true;
          _isCrashing = false;
        });
      }
    }
  }

  void _onReceivedHttpError(
    InAppWebView webView,
    WebResourceRequest request,
    WebResourceResponse response,
  ) {
    AppLogger.warning(
      'HTTP error: ${response.statusCode} for ${request.url?.toString()}',
      tag: 'Webview',
    );
    final code = response.statusCode;
    if (code != null && (code >= 400 && code < 600)) {
      if (mounted) {
        setState(() {
          _hasLoadError = true;
          _isCrashing = false;
        });
      }
    }
  }

  void _onReceivedServerTrustError(
    InAppWebView webView,
    WebResourceRequest request,
    ServerTrustError serverTrustError,
  ) {
    AppLogger.error(
      'SSL/TLS error: ${serverTrustError.error} for ${request.url?.toString()}',
      tag: 'Webview',
    );
    // Never proceed with invalid certificates — security requirement
    if (mounted) {
      setState(() {
        _hasLoadError = true;
        _isCrashing = true;
      });
    }
  }

  void _onConsentPolicyButtonClicked(
    InAppWebView webView,
    ConsentPolicyButtonClickedCallback args,
  ) {
    // Auto-accept cookie/consent policies for seamless UX
    webView?.acceptConsentPolicy();
  }

  void _onConsoleMessage(
    InAppWebView webView,
    ConsoleMessage consoleMessage,
  ) {
    final level = consoleMessage.level.name;
    if (level == 'error' || level == 'warning') {
      AppLogger.warning(
        'WebView console [$level]: ${consoleMessage.message} '
        'at ${consoleMessage.sourceId}:${consoleMessage.lineNumber}',
        tag: 'Webview.Console',
      );
    }
  }

  void _onPermissionRequest(
    InAppWebView webView,
    PermissionRequest request,
  ) async {
    // Auto-grant camera, microphone, location for PWA functionality
    final permission = request.permissionIdentifier;
    if (permission == 'android.webkit.permission.CAMERA' ||
        permission == 'android.webkit.permission.RECORD_AUDIO' ||
        permission == 'android.webkit.permission.ACCESS_FINE_LOCATION') {
      try {
        // Request at OS level via permission_handler if needed
        // For now, auto-grant to WebView
        webView.grantPermission(request);
      } catch (e) {
        webView.denyPermission(request);
        AppLogger.warning('Auto-permission denied: $permission', tag: 'Webview');
      }
    } else {
      webView.denyPermission(request);
    }
  }

  void _onGeolocationPermissionsShowPrompt(
    InAppWebView webView,
    WebUri origin,
    GeolocationPermissionsShowPromptCallback callback,
  ) {
    // Auto-grant geolocation for PWA features
    callback(true, false);
  }

  // ------------------------------------------------------------------
  // Reload helpers
  // ------------------------------------------------------------------
  Future<void> _checkConnectionAndReload() async {
    // Close any offline dialog
    Navigator.of(context).pop();

    final connected = await ConnectivityService.hasConnection();
    if (!connected) {
      if (mounted) _showOffline();
      return;
    }
    await _reload();
  }

  Future<void> _reload() async {
    if (_webView == null) {
      _createWebView();
      setState(() {});
      return;
    }

    setState(() {
      _hasLoadError = false;
      _isCrashing = false;
    });

    try {
      await _webView!.reload();
    } catch (e) {
      AppLogger.error('Reload failed', tag: 'Webview', error: e);
      setState(() {
        _hasLoadError = true;
        _isCrashing = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we have a load/crash error, hide the WebView and show error overlay
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

    // If the WebView isn't created yet or isn't ready, show loader
    if (_webView == null || !_isWebViewReady) {
      return constWebviewLoader();
    }

    // Normal state: show the WebView, full-screen, immersive
    return Scaffold(
      body: _webView,
    );
  }


