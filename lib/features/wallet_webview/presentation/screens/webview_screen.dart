import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/services/core_providers.dart';
import 'package:wallet/core/utils/logger.dart';
import '../widgets/webview_error_overlay.dart';
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
  
  // Connection and loading state management
  bool _hasConnectionIssue = false;
  Timer? _loadingTimer;
  String _currentUrl = '';
  
  // List of allowed domains to keep inside the app
  // IMPORTANT: Replace with your actual domain(s)
  // Based on your baseUrl, you should update this to match your webapp domain
  final List<String> _allowedDomains = [
    'e-global-197077.vercel.app',
    'www.e-global-197077.vercel.app',
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _startLoadingTimer();
  }
  
  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }
  
  void _startLoadingTimer() {
    _loadingTimer?.cancel();
    _loadingTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && ref.read(webViewProvider.notifier).state.isLoading) {
        setState(() {
          _hasConnectionIssue = true;
        });
      }
    });
  }
  
  void _stopLoadingTimer() {
    _loadingTimer?.cancel();
    _loadingTimer = null;
  }
  
  bool _isAllowedDomain(String url) {
    try {
      final uri = Uri.parse(url);
      // Allow relative links, about:blank, or data URLs
      if (uri.scheme.isEmpty || uri.scheme == 'about' || uri.scheme == 'data') {
        return true;
      }
      
      final domain = uri.host.toLowerCase().replaceFirst('www.', '');
      
      for (var allowed in _allowedDomains) {
        final cleanAllowed = allowed.toLowerCase().replaceFirst('www.', '');
        if (domain == cleanAllowed || domain.endsWith('.$cleanAllowed')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  
  void _launchExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication, // Forces external tab/browser
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
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
      final uri = Uri.parse(url);
      final fileName = _extractFileName(uri, contentDisposition);
      
      setState(() {
        _isDownloading = true;
        _downloadingFileName = fileName;
        _downloadProgress = 0.1;
      });

      final dirPath = await _getDownloadDirectoryPath();
      final filePath = '$dirPath/$fileName';
      final file = File(filePath);

      // Create directories if they don't exist
      await file.parent.create(recursive: true);

      final client = HttpClient();
      final request = await client.getUrl(uri);
      
      // Set headers to mimic browser request
      if (userAgent != null && userAgent.isNotEmpty) {
        request.headers.set('user-agent', userAgent);
      }
      request.headers.set('Accept', '*/*');
      
      final response = await request.close();

      final total = response.contentLength > 0 ? response.contentLength : contentLength;
      int received = 0;

      // Stream directly to file with throttled progress updates to prevent UI jank
      final sink = file.openWrite();
      int lastProgressUpdate = 0;
      try {
        await response.listen((List<int> chunk) {
          received += chunk.length;
          if (total > 0) {
            final progress = (received / total * 100).toInt();
            // Only update UI every 5% to prevent excessive setState calls
            if (progress - lastProgressUpdate >= 5) {
              lastProgressUpdate = progress;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _downloadProgress = received / total;
                  });
                }
              });
            }
          }
        }).forEach(sink.add);
        
        await sink.flush();
      } finally {
        await sink.close();
      }

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

  String _extractFileName(Uri uri, String? contentDisposition) {
    // Try to extract filename from Content-Disposition header first
    if (contentDisposition != null && contentDisposition.isNotEmpty) {
      final fileNameRegex = RegExp(r"filename[^;=\n]*=[\"']?([^\"';\n]*)[\"']?");
      final matches = fileNameRegex.allMatches(contentDisposition);
      if (matches.isNotEmpty) {
        final match = matches.first.group(1);
        if (match != null) {
          return match.trim();
        }
      }
    }
    
    // Fallback to extracting from URL
    final pathSegments = uri.pathSegments;
    if (pathSegments.isNotEmpty) {
      final fileName = pathSegments.last;
      if (fileName.isNotEmpty && fileName.contains('.')) {
        return Uri.decodeComponent(fileName);
      }
    }
    
    // Default fallback
    return 'downloaded_file_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _getDownloadDirectoryPath() async {
    // Standard secure application documents directory works perfectly on Android 10+
    // (Scoped Storage compliant), iOS, and macOS with zero filesystem write restrictions or crashes.
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<void> _handleShare(String text) async {
    try {
      await Share.share(text, subject: 'E-Global Pay Receipt');
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

      await Share.shareXFiles([XFile(tempPath)], text: 'E-Global Pay Receipt');
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

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$fileName';
      final file = File(tempPath);
      await file.parent.create(recursive: true);

      // Stream directly to file - DO NOT accumulate in memory
      final sink = file.openWrite();
      try {
        await response.listen((List<int> chunk) => sink.add(chunk)).asFuture();
        await sink.flush();
      } finally {
        await sink.close();
      }

      await Share.shareXFiles([XFile(tempPath)], text: 'E-Global Pay Receipt');
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
      exit(0); // Effectively close the app instantly and cleanly!
    }
  }

  @override
  Widget build(BuildContext context) {
    final webViewState = ref.watch(webViewProvider);
    final webViewNotifier = ref.read(webViewProvider.notifier);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        await _handlePopInvocation(didPop);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
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
                        cacheMode: CacheMode.LOAD_DEFAULT,
                        hardwareAcceleration: true,
                      ),
                      shouldOverrideUrlLoading: (controller, navigationAction) async {
                        final uri = navigationAction.request.url;
                        if (uri != null) {
                          final urlString = uri.toString();
                          
                          // Handle custom share schemes
                          if (urlString.startsWith('share:') || urlString.startsWith('eglobal://share')) {
                            final queryParams = uri.queryParameters;
                            final text = queryParams['text'] ?? queryParams['data'] ?? urlString.replaceFirst('share:', '');
                            await _handleShare(Uri.decodeComponent(text));
                            return NavigationActionPolicy.CANCEL;
                          }
                          
                          // Check if it's an external domain - open in external browser
                          if (!_isAllowedDomain(urlString)) {
                            _launchExternalUrl(urlString);
                            return NavigationActionPolicy.CANCEL;
                          }
                        }
                        return NavigationActionPolicy.ALLOW;
                      },
                      onWebViewCreated: (controller) async {
                        _webViewController = controller;

                        // Inject CSS to hide scrollbars globally in the web content
                        await controller.evaluateJavascript(
                          source: """
                            (function() {
                              var style = document.createElement('style');
                              style.textContent = '''
                                * {
                                  scrollbar-width: none !important;
                                  -ms-overflow-style: none !important;
                                }
                                ::-webkit-scrollbar {
                                  width: 0 !important;
                                  height: 0 !important;
                                }
                                ::-webkit-scrollbar-thumb {
                                  display: none !important;
                                }
                                ::-webkit-scrollbar-track {
                                  display: none !important;
                                }
                                html, body {
                                  overflow: auto !important;
                                  -webkit-overflow-scrolling: touch !important;
                                }
                              ''';
                              document.head.appendChild(style);
                            })();
                          """,
                        );

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
                        _currentUrl = url.toString();
                        webViewNotifier.setLoading(true);
                        webViewNotifier.setError(false);
                        // Reset connection issue flag when new page starts loading
                        if (_hasConnectionIssue) {
                          setState(() {
                            _hasConnectionIssue = false;
                          });
                        }
                        // Restart the loading timer for each new page
                        _startLoadingTimer();
                      },
                      onLoadStop: (controller, url) async {
                        _stopLoadingTimer();
                        webViewNotifier.setLoading(false);
                        // Reset connection issue flag when page loads successfully
                        if (_hasConnectionIssue) {
                          setState(() {
                            _hasConnectionIssue = false;
                          });
                        }
                        // Re-inject CSS to hide scrollbars after each page load
                        await controller.evaluateJavascript(
                          source: """
                            (function() {
                              var existingStyle = document.getElementById('hide-scrollbar-style');
                              if (existingStyle) return;
                              var style = document.createElement('style');
                              style.id = 'hide-scrollbar-style';
                              style.textContent = '''
                                * {
                                  scrollbar-width: none !important;
                                  -ms-overflow-style: none !important;
                                }
                                ::-webkit-scrollbar {
                                  width: 0 !important;
                                  height: 0 !important;
                                }
                                ::-webkit-scrollbar-thumb {
                                  display: none !important;
                                }
                                ::-webkit-scrollbar-track {
                                  display: none !important;
                                }
                                html, body {
                                  overflow: auto !important;
                                  -webkit-overflow-scrolling: touch !important;
                                }
                              ''';
                              document.head.appendChild(style);
                            })();
                          """,
                        );
                      },
                      onProgressChanged: (controller, progress) {
                        webViewNotifier.setProgress(progress / 100);
                      },
                      onReceivedError: (controller, request, error) {
                        // Only show the full-page error overlay if it is the main frame that failed to load.
                        // This prevents minor sub-resource load failures (e.g., ad scripts, analytics, missing icons, font issues)
                        // from interrupting the user experience with a blocking error screen.
                        if (request.isForMainFrame ?? true) {
                          _stopLoadingTimer();
                          setState(() {
                            _hasConnectionIssue = true;
                          });
                          webViewNotifier.setError(true, error.description);
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
                ],
              ),
              if (webViewState.hasError)
                WebviewErrorOverlay(
                  title: 'App',
                  description: webViewState.errorMessage.isNotEmpty
                      ? webViewState.errorMessage
                      : 'An error occurred while loading the wallet application.',
                  onRetry: () {
                    webViewNotifier.setError(false);
                    _webViewController?.reload();
                  },
                ),
              if (_isDownloading)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DownloadProgressBar(
                    progress: _downloadProgress,
                    fileName: _downloadingFileName,
                  ),
                ),
              // Show connection issue overlay when page takes too long to load or network fails
              if (_hasConnectionIssue)
                Container(
                  color: Colors.white,
                  child: WebviewErrorOverlay(
                    title: 'Connection Issue',
                    description: 'Something went wrong. Please check your internet connection and try again.',
                    onRetry: () {
                      setState(() {
                        _hasConnectionIssue = false;
                      });
                      _startLoadingTimer();
                      _webViewController?.reload();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
