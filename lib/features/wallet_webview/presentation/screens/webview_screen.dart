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
                  onReceivedError: (controller, request, error) {
                    AppLogger.e(
                      'WebView error handled: ${error.description}',
                    );
                    if (request.isForMainFrame ?? true) {
                      _stopLoadingTimer();
                      if (mounted) {
                        setState(() {
                          _hasLoadError = true;
                          _isCrashing = false;
                        });
                      }
                    }
                  },
                  onReceivedHttpError: (controller, request, errorResponse) {
                    AppLogger.e(
                      'WebView HTTP error handled: ${errorResponse.statusCode}',
                    );
                    if ((request.isForMainFrame ?? true) &&
                        (errorResponse.statusCode ?? 200) >= 400) {
                      _stopLoadingTimer();
                      if (mounted) {
                        setState(() {
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
