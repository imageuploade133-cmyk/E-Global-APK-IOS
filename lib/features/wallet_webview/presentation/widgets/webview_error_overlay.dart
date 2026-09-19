import 'package:flutter/material.dart';
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/core/constants/app_strings.dart';

/// Displays when the WebView fails to load or crashes.
/// Uses pure #FFFFFF background, clean typography, and E-Global orange gradient.
class WebviewErrorOverlay extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<void> Function() onRetry;

  const WebviewErrorOverlay({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  @override
  State<WebviewErrorOverlay> createState() => _WebviewErrorOverlayState();
}

class _WebviewErrorOverlayState extends State<WebviewErrorOverlay> {
  bool _isRetrying = false;

  Future<void> _handleRetry() async {
    if (_isRetrying) return;
    setState(() {
      _isRetrying = true;
    });

    try {
      await widget.onRetry();
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Clean error icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppColors.textLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.subtitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[600],
                        fontSize: 15,
                        height: 1.4,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        const Color(0xFFFF9100),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isRetrying ? null : _handleRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isRetrying) ...[
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Retrying...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ] else ...[
                          const Icon(
                            Icons.refresh_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            AppStrings.tryAgainLabel,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
