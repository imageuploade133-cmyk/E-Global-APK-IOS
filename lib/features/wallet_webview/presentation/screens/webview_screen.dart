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

  // E-Global Brand Orange constant color to eliminate black/white spaces completely
  static const Color brandOrange = Color(0xFFF67C01);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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

  @override
  Widget build(BuildContext context) {
    final webViewNotifier = ref.read(webViewProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        await _handlePopInvocation(didPop);
      },
      child: Scaffold(
        // Use brandOrange background color for the screen to prevent any white/black flashes
        backgroundColor: brandOrange,
        body: Container(
          color: brandOrange,
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
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    // Robust 100% offline support cache configuration
                    cacheMode: CacheMode.LOAD_CACHE_ELSE_NETWORK,
                    // Remove all window/viewport margins, backgrounds, and styling issues
                    transparentBackground: true,
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
