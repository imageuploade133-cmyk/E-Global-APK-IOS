import 'package:flutter/material.dart';
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

  const WebviewScreen({
    super.key,
    this.initialUrl = 'https://e-global-197077.vercel.app/',
  });

  @override
  ConsumerState<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends ConsumerState<WebviewScreen> {
  InAppWebViewController? _controller;
  bool _isWebViewReady = false;
  bool _hasLoadError = false;
  bool _isCrashing = false;
  bool _isOfflineDialogShowing = false;

  @override
  void initState() {
    super.initState();
    AppLogger.info('WebviewScreen initializing', tag: 'Webview');
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
    if (!_isWebViewReady) {
      return const WebviewLoader();
    }

    // Normal state: show the WebView, full-screen, immersive
    return Scaffold(
      body: InAppWebView(
        key: const ValueKey('main_webview'),
        initialSettings: const InAppWebViewSettings(
          useShouldOverrideUrlLoading: true,
          useOnLoadResource: true,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
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
          inspectionEnabled: false,
          allowUniversalAccessFromFileURLs: false,
          allowFileAccessFromFileURLs: false,
          saveFormData: false,
        ),
        initialUrlRequest: URLRequest(
          url: WebUri(widget.initialUrl),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
          },
        ),
        onWebViewCreated: _onWebViewCreated,
        onLoadStart: _onLoadStart,
        onLoadStop: _onLoadStop,
        onLoadError: _onLoadError,
        onReceivedError: _onReceivedError,
        onReceivedHttpError: _onReceivedHttpError,
        onReceivedServerTrustAuthRequest: _onReceivedServerTrustAuthRequest,
        onConsoleMessage: _onConsoleMessage,
        onPermissionRequest: _onPermissionRequest,
        onGeolocationPermissionsShowPrompt: _onGeolocationPermissionsShowPrompt,
        onSaveFormDataRequest: (controller, url, formData) async {
          return SaveFormDataRequestAction.IGNORE;
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // WebView lifecycle callbacks
  // ------------------------------------------------------------------

  void _onWebViewCreated(InAppWebViewController controller) {
    AppLogger.info('WebView created successfully', tag: 'Webview');
    _controller = controller;
    setState(() {
      _isWebViewReady = true;
    });
  }

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    AppLogger.debug('WebView load start: ${url?.toString()}', tag: 'Webview');
    setState(() {
      _hasLoadError = false;
      _isCrashing = false;
    });
  }

  Future<void> _onLoadStop(InAppWebViewController controller, WebUri? url) async {
    AppLogger.info('WebView load complete: ${url?.toString()}', tag: 'Webview');

    // Verify the page actually loaded by checking the title
    final title = await controller.getTitle();
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
    InAppWebViewController controller,
    Uri? url,
    int code,
    String message,
  ) {
    AppLogger.error(
      'WebView load error: $message (code: $code)',
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
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    AppLogger.warning(
      'Web resource error: ${error.description} '
      'for ${request.url?.toString()}',
      tag: 'Webview',
    );
    // Treat any resource error as a load failure for the crash guard
    if (mounted) {
      setState(() {
        _hasLoadError = true;
        _isCrashing = false;
      });
    }
  }

  void _onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse errorResponse,
  ) {
    AppLogger.warning(
      'HTTP error: ${errorResponse.statusCode} for ${request.url?.toString()}',
      tag: 'Webview',
    );
    final code = errorResponse.statusCode;
    if (code != null && code >= 400) {
      if (mounted) {
        setState(() {
          _hasLoadError = true;
          _isCrashing = false;
        });
      }
    }
  }

  Future<ServerTrustAuthResponse> _onReceivedServerTrustAuthRequest(
    InAppWebViewController controller,
    URLAuthenticationChallenge challenge,
  ) async {
    AppLogger.error(
      'SSL/TLS error: ${challenge.error} for ${challenge.url}',
      tag: 'Webview',
    );
    // Never proceed with invalid certificates — security requirement
    if (mounted) {
      setState(() {
        _hasLoadError = true;
        _isCrashing = true;
      });
    }
    return ServerTrustAuthResponse.actionCancel();
  }

  void _onConsoleMessage(
    InAppWebViewController controller,
    ConsoleMessage consoleMessage,
  ) {
    if (mounted) {
      AppLogger.warning(
        'WebView console: ${consoleMessage.message}',
        tag: 'Webview.Console',
      );
    }
  }

  Future<PermissionResponse> _onPermissionRequest(
    InAppWebViewController controller,
    PermissionRequest permissionRequest,
  ) async {
    // Auto-grant camera, microphone, location for PWA functionality
    final resources = permissionRequest.resources;
    final needsCamera = resources.contains('camera');
    final needsAudio = resources.contains('microphone');
    final needsLocation = resources.contains('geolocation');

    if (needsCamera || needsAudio || needsLocation) {
      try {
        return await controller.grantPermission();
      } catch (e) {
        AppLogger.warning(
          'Auto-permission denied: ${resources.join(", ")}',
          tag: 'Webview',
        );
        return await controller.denyPermission();
      }
    }

    return await controller.denyPermission();
  }

  Future<GeolocationPermissionShowPromptResponse> _onGeolocationPermissionsShowPrompt(
    InAppWebViewController controller,
    String origin,
  ) async {
    // Auto-grant geolocation for PWA features
    return GeolocationPermissionShowPromptResponse.allowed(false);
  }

  // ------------------------------------------------------------------
  // Reload helpers
  // ------------------------------------------------------------------

  Future<void> _checkConnectionAndReload() async {
    // Close any offline dialog
    if (_isOfflineDialogShowing) {
      try {
        Navigator.of(context).pop();
      } catch (_) {}
      _isOfflineDialogShowing = false;
    }

    final connected = await ConnectivityService.hasConnection();
    if (!connected) {
      if (mounted) _showOffline();
      return;
    }
    await _reload();
  }

  Future<void> _reload() async {
    if (_controller == null) {
      setState(() {});
      return;
    }

    setState(() {
      _hasLoadError = false;
      _isCrashing = false;
    });

    try {
      await _controller!.reload();
    } catch (e) {
      AppLogger.error('Reload failed', tag: 'Webview', error: e);
      setState(() {
        _hasLoadError = true;
        _isCrashing = true;
      });
    }
  }

  void _showOffline() {
    if (mounted) {
      _isOfflineDialogShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => OfflineScreen(
          onRetry: _checkConnectionAndReload,
        ),
      );
    }
  }
