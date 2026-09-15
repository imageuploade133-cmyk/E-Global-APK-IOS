import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';

/// Full-screen loading overlay shown while the WebView is initializing.
class WebviewLoader extends StatelessWidget {
  constWebviewLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing loader ring
            _PulsingLoader(),
            constSizedBox(height: 24),
            Text(
              AppStrings.loading,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingLoader extends StatefulWidget {
  @override
  State<_PulsingLoader> createState() => _PulsingLoaderState();
}

class _PulsingLoaderState extends State<_PulsingLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: constDuration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CircularProgressIndicator(
            value: _controller.value,
            strokeWidth: 3.5,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          );
        },
      ),
    );
  }
}
