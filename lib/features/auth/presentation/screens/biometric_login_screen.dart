import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/services/core_providers.dart';

enum BiometricAuthState { idle, authenticating, success, error }

class BiometricLoginScreen extends ConsumerStatefulWidget {
  const BiometricLoginScreen({super.key});

  @override
  ConsumerState<BiometricLoginScreen> createState() =>
      _BiometricLoginScreenState();
}

class _BiometricLoginScreenState extends ConsumerState<BiometricLoginScreen> {
  BiometricAuthState _authState = BiometricAuthState.idle;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    FlutterNativeSplash.remove();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndAuthenticate();
    });
  }

  Future<void> _checkAndAuthenticate() async {
    final biometricService = ref.read(biometricServiceProvider);
    final secureStorage = ref.read(secureStorageProvider);

    final isValid =
        await biometricService.validateBiometricEnrollment(secureStorage);
    if (!isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Biometric enrollment changed or unavailable. Please login using standard credentials.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pushReplacementNamed('/webview');
      }
      return;
    }

    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authState == BiometricAuthState.authenticating) return;

    setState(() {
      _authState = BiometricAuthState.authenticating;
      _statusMessage = 'Touch sensor to verify fingerprint';
    });

    final biometricService = ref.read(biometricServiceProvider);

    final authenticated = await biometricService.authenticate().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        if (mounted) {
          setState(() {
            _authState = BiometricAuthState.error;
            _statusMessage = 'Biometric authentication timed out. Tap to retry.';
          });
        }
        return false;
      },
    );

    if (!mounted) return;

    if (authenticated) {
      HapticFeedback.mediumImpact();
      setState(() {
        _authState = BiometricAuthState.success;
        _statusMessage = 'Biometric verified! Unlocking...';
      });

      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/webview');
      }
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _authState = BiometricAuthState.error;
        _statusMessage = 'Biometric authentication failed. Tap below to retry.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric authentication failed. Please retry.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Color get _iconColor {
    switch (_authState) {
      case BiometricAuthState.success:
        return const Color(0xFF10B981); // Bright Green
      case BiometricAuthState.error:
        return const Color(0xFFEF4444); // Red
      case BiometricAuthState.authenticating:
        return AppColors.primary; // Brand Orange
      case BiometricAuthState.idle:
        return Colors.grey;
    }
  }

  Color get _containerBgColor {
    switch (_authState) {
      case BiometricAuthState.success:
        return const Color(0xFFD1FAE5); // Soft Green
      case BiometricAuthState.error:
        return const Color(0xFFFEE2E2); // Soft Red
      case BiometricAuthState.authenticating:
        return AppColors.primary.withAlpha(25);
      case BiometricAuthState.idle:
        return Colors.grey.withAlpha(25);
    }
  }

  IconData get _statusIcon {
    switch (_authState) {
      case BiometricAuthState.success:
        return Icons.check_circle_rounded;
      case BiometricAuthState.error:
        return Icons.error_rounded;
      case BiometricAuthState.authenticating:
      case BiometricAuthState.idle:
        return Icons.fingerprint_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/images/logo.png', width: 100, height: 100),
              const SizedBox(height: 24),
              const Text(
                AppStrings.appName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Biometric App Unlock',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              const SizedBox(height: 48),

              // Dynamic Visual Fingerprint Container
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: _containerBgColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _iconColor,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _iconColor.withAlpha(51),
                        blurRadius: 16,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      _statusIcon,
                      size: 64,
                      color: _iconColor,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              if (_statusMessage != null)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _statusMessage!,
                    key: ValueKey<String>(_statusMessage!),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _iconColor,
                    ),
                  ),
                ),

              const SizedBox(height: 40),

              if (_authState == BiometricAuthState.authenticating)
                const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                )
              else if (_authState == BiometricAuthState.error ||
                  _authState == BiometricAuthState.idle)
                ElevatedButton.icon(
                  onPressed: _authenticate,
                  icon: const Icon(Icons.fingerprint, size: 28),
                  label: const Text(
                    'Try Fingerprint Again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _authState == BiometricAuthState.error
                        ? const Color(0xFFEF4444)
                        : AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
