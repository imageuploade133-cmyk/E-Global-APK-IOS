import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/services/core_providers.dart';
import 'package:wallet/core/utils/logger.dart';
import '../widgets/webview_loader.dart';
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
  PullToRefreshController? _pullToRefreshController;

  double _downloadProgress = 0.0;
  String _downloadingFileName = '';
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _initPullToRefresh();
  }

  void _initPullToRefresh() {
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: AppColors.primary,
      ),
      onRefresh: () async {
        if (Platform.isAndroid) {
          _webViewController?.reload();
        } else if (Platform.isIOS || Platform.isMacOS) {
          _webViewController?.loadUrl(
            urlRequest: URLRequest(url: await _webViewController?.getUrl()),
          );
        }
      },
    );
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

      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);

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

  Future<bool> _onWillPop() async {
    if (_webViewController != null && await _webViewController!.canGoBack()) {
      await _webViewController!.goBack();
      return false;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Application'),
        content: const Text('Are you sure you want to exit E-Global Wallet?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Exit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final webViewState = ref.watch(webViewProvider);
    final webViewNotifier = ref.read(webViewProvider.notifier);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (webViewState.progress < 1.0 && webViewState.isLoading)
                    LinearProgressIndicator(
                      value: webViewState.progress,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
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
                      ),
                      pullToRefreshController: _pullToRefreshController,
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                      },
                      onLoadStart: (controller, url) {
                        webViewNotifier.setLoading(true);
                        webViewNotifier.setError(false);
                      },
                      onLoadStop: (controller, url) async {
                        _pullToRefreshController?.endRefreshing();
                        webViewNotifier.setLoading(false);
                      },
                      onProgressChanged: (controller, progress) {
                        webViewNotifier.setProgress(progress / 100);
                      },
                      onReceivedError: (controller, request, error) {
                        _pullToRefreshController?.endRefreshing();
                        // Only show the full-page error overlay if it is the main frame that failed to load.
                        // This prevents minor sub-resource load failures (e.g., ad scripts, analytics, missing icons, font issues)
                        // from interrupting the user experience with a blocking error screen.
                        if (request.isForMainFrame ?? true) {
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
              if (webViewState.isLoading && webViewState.progress < 0.3)
                const WebviewLoader(),
              if (webViewState.hasError)
                WebviewErrorOverlay(
                  title: 'Page Load Failed',
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
            ],
          ),
        ),
      ),
    );
  }
}
