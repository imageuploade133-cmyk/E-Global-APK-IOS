import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
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

  // Essential critical permissions that are required for the application's secure operations to function
  final List<Permission> _permissions = [
    Permission.camera,
    Permission.microphone,
    Permission.locationWhenInUse,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionsAndProceed();
    });
  }

  Future<void> _checkPermissionsAndProceed() async {
    bool allGranted = true;
    for (final perm in _permissions) {
      final status = await perm.status;
      final isGranted = status.isGranted || status.isLimited || status.isRestricted;
      if (!isGranted) {
        allGranted = false;
        break;
      }
    }

    if (allGranted) {
      await _proceedToApp();
    } else {
      // If not all granted, show the onboarding UI and remove splash screen
      FlutterNativeSplash.remove();
    }
  }

  Future<void> _requestAllPermissions() async {
    if (_isRequesting) return;
    setState(() {
      _isRequesting = true;
    });

    // Request essential permissions sequentially/on-screen
    for (final perm in _permissions) {
      final status = await perm.request();
      if (status.isPermanentlyDenied) {
        setState(() {
          _isRequesting = false;
        });
        _showPermanentlyDeniedDialog(perm);
        return;
      } else if (!status.isGranted && !status.isLimited && !status.isRestricted) {
        setState(() {
          _isRequesting = false;
        });
        _showPermissionDeniedDialog(perm);
        return;
      }
    }

    // Attempt to request storage/photos and notifications on-demand silently (without crashing or blocking on failure)
    try {
      if (Platform.isAndroid) {
        await Permission.storage.request();
      } else if (Platform.isIOS) {
        await Permission.photos.request();
      }
      await Permission.notification.request();
    } catch (_) {
      // Non-blocking catch
    }

    setState(() {
      _isRequesting = false;
    });

    await _proceedToApp();
  }

  Future<void> _proceedToApp() async {
    final secureStorage = ref.read(secureStorageProvider);
    final biometrics = ref.read(biometricServiceProvider);

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

  String _getPermissionName(Permission permission) {
    if (permission == Permission.camera) return 'Camera Access';
    if (permission == Permission.microphone) return 'Microphone Access';
    if (permission == Permission.location || permission == Permission.locationWhenInUse) return 'Location Services';
    if (permission == Permission.storage) return 'Storage Access';
    if (permission == Permission.photos) return 'Photo Library';
    if (permission == Permission.notification) return 'Real-time Alerts';
    return permission.toString();
  }

  void _showPermissionDeniedDialog(Permission permission) {
    final name = _getPermissionName(permission);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 28),
            SizedBox(width: 12),
            Text(
              'Permission Recommended',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textLight),
            ),
          ],
        ),
        content: Text(
          'E-Global Wallet works best with $name enabled. You can grant this permission now or continue to the wallet and enable it later when using features that require it.',
          style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _proceedToApp();
            },
            child: const Text(
              'Continue Anyway',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _requestAllPermissions();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showPermanentlyDeniedDialog(Permission permission) {
    final name = _getPermissionName(permission);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.settings_suggest_rounded, color: AppColors.primary, size: 28),
            SizedBox(width: 12),
            Text(
              'Enable Permission',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textLight),
            ),
          ],
        ),
        content: Text(
          'The $name permission has been permanently disabled. You can open App Settings to enable it manually, or continue to the wallet.',
          style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _proceedToApp();
            },
            child: const Text(
              'Continue to Wallet',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
                                      color: AppColors.primary.withValues(alpha: 0.3),
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
              color: AppColors.primary.withValues(alpha: 0.08),
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
