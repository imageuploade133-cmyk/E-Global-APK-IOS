import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/services/core_providers.dart';

class PermissionsOnboardingScreen extends ConsumerStatefulWidget {
  const PermissionsOnboardingScreen({super.key});

  @override
  ConsumerState<PermissionsOnboardingScreen> createState() =>
      _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState
    extends ConsumerState<PermissionsOnboardingScreen> with WidgetsBindingObserver {
  bool _isRequesting = false;
  static const String _onboardingCompletedKey = 'eglobal_permissions_onboarding_completed_v1';
  bool _checkingInitialState = true;

  // List of all device permissions requested by E-Global Pay
  final List<Permission> _permissions = [
    Permission.camera,
    Permission.microphone,
    Permission.locationWhenInUse,
    Permission.notification,
    Permission.contacts,
    Permission.photos,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionsAndProceed();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isRequesting) {
      _checkPermissionsAndProceed();
    }
  }

  Future<bool> _areRequiredPermissionsGranted() async {
    for (final perm in _permissions) {
      final status = await perm.status;
      if (!(status.isGranted || status.isLimited || status.isRestricted)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _checkPermissionsAndProceed() async {
    final secureStorage = ref.read(secureStorageProvider);
    final completed = await secureStorage.read(_onboardingCompletedKey) == 'true';
    final allGranted = await _areRequiredPermissionsGranted();

    // Once onboarding has been completed, never show this screen again.
    if (completed) {
      if (mounted) setState(() => _checkingInitialState = false);
      await _proceedToApp();
      return;
    }

    if (allGranted) {
      await secureStorage.write(_onboardingCompletedKey, 'true');
      if (mounted) setState(() => _checkingInitialState = false);
      await _proceedToApp();
    } else {
      if (mounted) setState(() => _checkingInitialState = false);
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      try {
        FlutterNativeSplash.remove();
      } catch (_) {}
    }
  }

  Future<void> _requestAllPermissions() async {
    if (_isRequesting) return;
    setState(() {
      _isRequesting = true;
    });

    for (final perm in _permissions) {
      try {
        await perm.request();
      } catch (_) {
        // Non-blocking catch to ensure process continues
      }
    }

    // Persist completion state into secure local storage
    final secureStorage = ref.read(secureStorageProvider);
    await secureStorage.write(_onboardingCompletedKey, 'true');

    if (mounted) {
      setState(() {
        _isRequesting = false;
      });
    }

    await _proceedToApp();
  }

  Future<void> _proceedToApp() async {
    final secureStorage = ref.read(secureStorageProvider);
    final biometrics = ref.read(biometricServiceProvider);

    final biometricEnabledStr = await secureStorage.read(
      AppStrings.biometricKey,
    );
    final biometricEnabled = biometricEnabledStr == 'true';
    final hasBiometrics = await biometrics.isBiometricsAvailable();

    if (mounted) {
      if (biometricEnabled && hasBiometrics) {
        Navigator.of(context).pushReplacementNamed('/biometric_login');
      } else {
        Navigator.of(context).pushReplacementNamed('/webview');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingInitialState) {
      return const Scaffold(backgroundColor: Colors.white, body: SizedBox.shrink());
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 24.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top: Logo and Title
                    Column(
                      children: [
                        const SizedBox(height: 12),
                        Image.asset(
                          'assets/images/logo.png',
                          width: 88,
                          height: 88,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'App Permissions',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textLight,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'To enable a secure and seamless banking experience, E-Global Pay requires access to the following permissions:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // List of permissions
                        _buildPermissionItem(
                          icon: Icons.camera_alt_rounded,
                          title: 'Camera Access',
                          description:
                              'Required for identity verification, facial recognition, and document scanning.',
                        ),
                        const SizedBox(height: 14),
                        _buildPermissionItem(
                          icon: Icons.mic_rounded,
                          title: 'Microphone Access',
                          description:
                              'Used for voice verification and customer support communication.',
                        ),
                        const SizedBox(height: 14),
                        _buildPermissionItem(
                          icon: Icons.location_on_rounded,
                          title: 'Location Services',
                          description:
                              'Ensures location compliance and fraud detection during transactions.',
                        ),
                        const SizedBox(height: 14),
                        _buildPermissionItem(
                          icon: Icons.notifications_active_rounded,
                          title: 'Real-time Alerts',
                          description:
                              'Receive immediate transaction updates, security alerts, and account notices.',
                        ),
                        const SizedBox(height: 14),
                        _buildPermissionItem(
                          icon: Icons.contacts_rounded,
                          title: 'Contacts Access',
                          description:
                              'Quickly select beneficiaries and send funds to your saved contacts.',
                        ),
                        const SizedBox(height: 14),
                        _buildPermissionItem(
                          icon: Icons.photo_library_rounded,
                          title: 'Photo Library & Storage',
                          description:
                              'Save transaction receipts and upload verification documents safely.',
                        ),
                      ],
                    ),

                    // Bottom: Action Button
                    Column(
                      children: [
                        const SizedBox(height: 32),
                        _isRequesting
                            ? const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              )
                            : Container(
                                width: double.infinity,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      Color(0xFFFF9100),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: _requestAllPermissions,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Grant All Permissions',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textLight,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
