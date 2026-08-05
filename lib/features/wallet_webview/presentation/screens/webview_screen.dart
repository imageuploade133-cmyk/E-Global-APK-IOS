import 'dart:io';
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

class _WebviewScreenState extends ConsumerState<WebviewScreen> {
  InAppWebViewController? _webViewController;

  double _downloadProgress = 0.0;
  String _downloadingFileName = '';
  bool _isDownloading = false;

  // Bleached Clean White constant color to eliminate black/white/colored layout flashes
  static const Color bleachWhite = Colors.white;

  // Base64 logo to render perfectly offline inside local HTML loaders
  String _logoBase64 = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadLogoAsset();
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

  Future<PermissionResponse?> _handlePermissionRequest(
    InAppWebViewController controller,
    PermissionRequest permissionRequest,
  ) async {
    final List<Permission> permissionsToRequest = [];

    for (final resource in permissionRequest.resources) {
      if (resource.toString().contains('AUDIO_CAPTURE') || resource.toString().contains('microphone')) {
        permissionsToRequest.add(Permission.microphone);
      } else if (resource.toString().contains('VIDEO_CAPTURE') || resource.toString().contains('camera')) {
        permissionsToRequest.add(Permission.camera);
      }
    }

    if (permissionsToRequest.isNotEmpty) {
      for (final perm in permissionsToRequest) {
        await perm.request();
      }
    }

    return PermissionResponse(
      resources: permissionRequest.resources,
      action: PermissionResponseAction.GRANT,
    );
  }

  Future<void> _handleDownload(String url, String? userAgent, String? contentDisposition, String? mimeType, int contentLength) async {
    try {
      final permissionService = ref.read(permissionServiceProvider);
      final hasStoragePermission = await permissionService.requestStoragePermission();
      if (!hasStoragePermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission is required to download files.')),
          );
        }
        return;
      }

      final uri = Uri.parse(url);
      final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'downloaded_file';

      setState(() {
        _isDownloading = true;
        _downloadingFileName = fileName;
        _downloadProgress = 0.1;
      });

      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();

      final bytes = <int>[];
      final total = response.contentLength;
      int received = 0;

      final dirPath = await _getDownloadDirectoryPath();
      final filePath = '$dirPath/$fileName';
      final file = File(filePath);

      // Create directories if they don't exist
      await file.parent.create(recursive: true);

      await response.listen((List<int> chunk) {
        bytes.addAll(chunk);
        received += chunk.length;
        setState(() {
          _downloadProgress = total > 0 ? (received / total) : 0.5;
        });
      }).asFuture();

      await file.writeAsBytes(bytes);

      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });

      if (mounted) {
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
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });
      AppLogger.e('Download error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  Future<String> _getDownloadDirectoryPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<void> _handleShare(String text) async {
    try {
      await Share.share(text, subject: 'E-Global Wallet Receipt');
    } catch (e) {
      AppLogger.e('Error sharing text', e);
    }
  }

  Future<void> _handleBase64Share(String base64Data, String fileName) async {
    try {
      final cleanBase64 = base64Data.contains(',') ? base64Data.split(',').last : base64Data;
      final bytes = base64.decode(cleanBase64);

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$fileName';
      final file = File(tempPath);
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(tempPath)], text: 'E-Global Wallet Receipt');
    } catch (e) {
      AppLogger.e('Error sharing base64 receipt', e);
    }
  }

  Future<void> _handleUrlShare(String url, String fileName) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      final bytes = <int>[];
      await response.listen((chunk) {
        bytes.addAll(chunk);
      }).asFuture();

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$fileName';
      final file = File(tempPath);
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(tempPath)], text: 'E-Global Wallet Receipt');
    } catch (e) {
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
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.power_settings_new_rounded, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Text(
              'Exit Application',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textLight),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      exit(0);
    }
  }

  // Inject CSS to override styles with premium iOS (San Francisco) and Android (Roboto) system fonts
  void _injectSystemFonts() {
    _webViewController?.evaluateJavascript(source: """
      (function() {
        const style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = `
          * {
            font-family: system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Roboto", "Helvetica Neue", Helvetica, Arial, sans-serif !important;
          }
        `;
        document.head.appendChild(style);
      })();
    """);
  }

  // Disable input auto-fill overlays to prevent browser/keyboard password autofill popups on login forms
  void _disableAutofillOverlays() {
    _webViewController?.evaluateJavascript(source: """
      (function() {
        const disableAutofill = () => {
          const inputs = document.querySelectorAll('input');
          inputs.forEach(input => {
            input.setAttribute('autocomplete', 'new-password');
            input.setAttribute('autocorrect', 'off');
            input.setAttribute('autocapitalize', 'off');
            input.setAttribute('spellcheck', 'false');
          });
          const forms = document.querySelectorAll('form');
          forms.forEach(form => {
            form.setAttribute('autocomplete', 'off');
          });
        };
        disableAutofill();
        // Also run on dynamic mutations to cover late rendering / single page app navigation
        const observer = new MutationObserver(disableAutofill);
        observer.observe(document.body, { childList: true, subtree: true });
      })();
    """);
  }

  // Fallback to beautiful branded screen if WebView fails to load, preventing Chromium Webpage not available from showing
  void _loadElegantFallback() {
    final logoSrc = _logoBase64.isNotEmpty ? "data:image/png;base64,$_logoBase64" : "";

    _webViewController?.loadData(data: """
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
        <script>
          // Automatic periodic retry loading the main page in background silently
          setInterval(function() {
            window.location.replace("${AppStrings.baseUrl}");
          }, 3500);
        </script>
      </body>
      </html>
    """);
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
                  initialUrlRequest: URLRequest(url: WebUri(AppStrings.baseUrl)),
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
                    // Allow mixed content so all icons/fonts/scripts load without HTTP restrictions
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    // Robust 100% offline support cache configuration
                    cacheMode: CacheMode.LOAD_CACHE_ELSE_NETWORK,
                    // Remove all window/viewport margins, backgrounds, and styling issues
                    transparentBackground: true,
                    // Enable high fidelity viewport dynamic scaling for smaller devices
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    supportZoom: false,
                  ),
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final uri = navigationAction.request.url;
                    if (uri != null) {
                      final urlString = uri.toString();
                      if (urlString.startsWith('share:') || urlString.startsWith('eglobal://share')) {
                        final queryParams = uri.queryParameters;
                        final text = queryParams['text'] ?? queryParams['data'] ?? urlString.replaceFirst('share:', '');
                        await _handleShare(Uri.decodeComponent(text));
                        return NavigationActionPolicy.CANCEL;
                      }
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onWebViewCreated: (controller) {
                    _webViewController = controller;

                    // Expose generic 'share' handler to the web app
                    controller.addJavaScriptHandler(
                      handlerName: 'share',
                      callback: (args) async {
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
                              await _handleBase64Share(base64Data, fileName ?? 'receipt.png');
                            } else if (url != null) {
                              await _handleUrlShare(url, fileName ?? 'receipt.png');
                            } else if (text != null) {
                              await _handleShare(text);
                            }
                          }
                        }
                      },
                    );

                    // Expose receipt-specific 'shareReceipt' handler to the web app
                    controller.addJavaScriptHandler(
                      handlerName: 'shareReceipt',
                      callback: (args) async {
                        if (args.isNotEmpty) {
                          final receiptData = args[0];
                          if (receiptData is String) {
                            await _handleShare(receiptData);
                          } else if (receiptData is Map) {
                            final text = receiptData['text'] as String?;
                            final base64 = receiptData['base64'] as String?;
                            final fileName = receiptData['fileName'] as String?;
                            if (base64 != null) {
                              await _handleBase64Share(base64, fileName ?? 'receipt.pdf');
                            } else if (text != null) {
                              await _handleShare(text);
                            }
                          }
                        }
                      },
                    );
                  },
                  onLoadStart: (controller, url) {
                    webViewNotifier.setLoading(true);
                    webViewNotifier.setError(false);
                  },
                  onLoadStop: (controller, url) async {
                    webViewNotifier.setLoading(false);

                    // Inject beautiful iOS/Android system font families right when the page fully loads
                    _injectSystemFonts();

                    // Disable autofill/autocomplete popups to stop showing browser/keyboard credential overlays
                    _disableAutofillOverlays();

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
                    AppLogger.e('WebView silent non-blocking error handled: ${error.description}');

                    if (request.isForMainFrame ?? true) {
                      _loadElegantFallback();
                    }
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
            ],
          ),
        ),
      ),
    );
  }
}
