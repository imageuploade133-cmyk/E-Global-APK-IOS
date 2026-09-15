import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';

/// Displays when the WebView fails to load or crashes.
/// Hides the WebView entirely and shows a clean error state.
class WebviewErrorOverlay extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  constWebviewErrorOverlay({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: constEdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Broken link / exclamation icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.errorDark.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: constIcon(
                    Icons.error_outline_rounded,
                    size: 36,
                    color: AppColors.error,
                  ),
                ),
                constSizedBox(height: 24),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppColors.onBackground,
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                constSizedBox(height: 10),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textMuted,
                      ),
                  textAlign: TextAlign.center,
                ),
                constSizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: constIcon(Icons.refresh_rounded, size: 20),
                    label: Text(AppStrings.tryAgainLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: constEdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
