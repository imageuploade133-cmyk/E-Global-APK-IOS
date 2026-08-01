import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/core/constants/app_strings.dart';
import 'package:wallet/core/services/core_providers.dart';

class PermissionsOnboardingScreen extends ConsumerStatefulWidget {
  const PermissionsOnboardingScreen({super.key});

  @override
  ConsumerState<PermissionsOnboardingScreen> createState() => _PermissionsOnboardingScreenState();
}

class _PermissionsOnboardingScreenState extends ConsumerState<PermissionsOnboardingScreen> {
  bool _isRequesting = false;

  // Dynamic permission checklist based on OS platform for absolute compatibility
  final List<Permission> _permissions = Platform.isAndroid
      ? [
          Permission.camera,
          Permission.microphone,
          Permission.locationWhenInUse,
          Permission.storage,
          Permission.notification,
        ]
      : [
          Permission.camera,
          Permission.microphone,
          Permission.locationWhenInUse,
          Permission.photos,
          Permission.notification,
        ];

  Future<void> _requestAllPermissions() async {
    if (_isRequesting) return;
    setState(() {
      _isRequesting = true;
    });

    // Request permissions sequentially/on-screen
    for (final perm in _permissions) {
      await perm.request();
    }

    // Check final status
    bool allGranted = true;
    for (final perm in _permissions) {
      final status = await perm.status;
      final isGranted = status.isGranted || status.isLimited || status.isRestricted;
      if (!isGranted) {
        allGranted = false;
        break;
      }
    }

    setState(() {
      _isRequesting = false;
    });

    if (allGranted) {
      _proceedToApp();
    } else {
      _showPermissionDeniedDialog();
    }
  }

  Future<void> _proceedToApp() async {
    final connectivity = ref.read(connectivityServiceProvider);
    final secureStorage = ref.read(secureStorageProvider);
    final biometrics = ref.read(biometricServiceProvider);

    final isConnected = await connectivity.isConnected;
    if (!isConnected) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/offline');
      }
      return;
    }

    final biometricEnabledStr = await secureStorage.read(AppStrings.biometricKey);
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

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text(
              'Permissions Required',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textLight),
            ),
          ],
        ),
        content: const Text(
          'E-Global Wallet requires all permissions to ensure safe, secure, and compliant financial operations. The app will now close.',
          style: TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              exit(0); // Instantly and effectively close the app
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Exit App', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top: Logo and Title
                    Column(
                      children: [
                        const SizedBox(height: 20),
                        Image.asset(
                          'assets/images/logo.png',
                          width: 100,
                          height: 100,
                        ),
                        const SizedBox(height: 24),
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
                        const SizedBox(height: 12),
                        const Text(
                          'To enable a highly secure and functional banking experience, E-Global Wallet requires the following device permissions:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // List of permissions
                        _buildPermissionItem(
                          icon: Icons.camera_alt_rounded,
                          title: 'Camera Access',
                          description: 'Required for dynamic facial recognition verification and uploading document files.',
                        ),
                        const SizedBox(height: 20),
                        _buildPermissionItem(
                          icon: Icons.mic_rounded,
                          title: 'Microphone Access',
                          description: 'Used for support voice checks and verifying your dynamic banking identity.',
                        ),
                        const SizedBox(height: 20),
                        _buildPermissionItem(
                          icon: Icons.location_on_rounded,
                          title: 'Location Services',
                          description: 'Guarantees location compliance and anti-fraud detection during transactions.',
                        ),
                        const SizedBox(height: 20),
                        _buildPermissionItem(
                          icon: Platform.isAndroid ? Icons.folder_open_rounded : Icons.photo_library_rounded,
                          title: Platform.isAndroid ? 'Storage Access' : 'Photo Library',
                          description: Platform.isAndroid
                              ? 'Allows secure temporary file caching and saving downloaded receipts.'
                              : 'Allows seamless selection and uploading of saved payment or verification documents.',
                        ),
                        const SizedBox(height: 20),
                        _buildPermissionItem(
                          icon: Icons.notifications_active_rounded,
                          title: 'Real-time Alerts',
                          description: 'Keeps you updated instantly with transaction confirmations, bills, and notifications.',
                        ),
                      ],
                    ),

                    // Bottom: Action Button
                    Column(
                      children: [
                        const SizedBox(height: 40),
                        _isRequesting
                            ? const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                              )
                            : Container(
                                width: double.infinity,
                                height: 56,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(
                                    colors: [AppColors.primary, Color(0xFFFF9100)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.3),
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
      padding: const EdgeInsets.all(16),
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
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 24,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textLight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
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
