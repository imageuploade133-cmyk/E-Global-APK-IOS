import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/features/auth/data/models/user_model.dart';
import 'package:wallet/features/auth/data/repositories/auth_repository.dart';
import 'package:wallet/features/auth/presentation/screens/native_login_screen.dart';
import 'package:wallet/features/wallet/data/repositories/wallet_repository.dart';

class NativeProfileScreen extends StatefulWidget {
  const NativeProfileScreen({super.key});

  @override
  State<NativeProfileScreen> createState() => _NativeProfileScreenState();
}

class _NativeProfileScreenState extends State<NativeProfileScreen> {
  final AuthRepository _authRepository = AuthRepository();
  final WalletRepository _walletRepository = WalletRepository();
  UserModel? _user;
  bool _darkMode = false;
  bool _biometricEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final cached = await _walletRepository.getCachedUser();
    if (mounted && cached != null) {
      setState(() => _user = cached);
    }

    try {
      final remote = await _walletRepository.fetchUserProfileFromApi();
      if (mounted && remote != null) {
        setState(() => _user = remote);
      }
    } catch (_) {}
  }

  void _showChangePinDialog() {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Security PIN', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Enter new 4-digit PIN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Security PIN updated successfully')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('SAVE PIN', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of E-Global Pay?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('SIGN OUT', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm ?? false) {
      await _authRepository.signOut();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushReplacement(
          MaterialPageRoute(builder: (_) => const NativeLoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _user?.name ?? 'Valued Captain';
    final accountNo = _user?.accountNumber ?? '8012345678';
    final kycText = 'Tier ${_user?.kycLevel ?? 3} Verified';

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Account Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // User Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: Image.asset('assets/images/logo.png', width: 36, height: 36),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Account: $accountNo',
                              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: accountNo));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Account number copied!')),
                                );
                              },
                              child: const Icon(Icons.copy, size: 14, color: AppColors.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            kycText,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Security Options
            _SettingsGroup(
              title: 'SECURITY & BIOMETRICS',
              items: [
                _SettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Change Security PIN',
                  onTap: _showChangePinDialog,
                ),
                _SettingsTile(
                  icon: Icons.fingerprint,
                  title: 'Biometric Authentication',
                  trailing: Switch(
                    value: _biometricEnabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: (val) => setState(() => _biometricEnabled = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // App Preferences
            _SettingsGroup(
              title: 'PREFERENCES',
              items: [
                _SettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark Mode',
                  trailing: Switch(
                    value: _darkMode,
                    activeThumbColor: AppColors.primary,
                    onChanged: (val) => setState(() => _darkMode = val),
                  ),
                ),
                _SettingsTile(
                  icon: Icons.share_outlined,
                  title: 'Invite Friends & Earn',
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: 'https://e-global-197077.vercel.app/referral'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Referral link copied!')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Sign Out Button
            ElevatedButton.icon(
              onPressed: _handleSignOut,
              icon: const Icon(Icons.logout),
              label: const Text('SIGN OUT', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.1),
                foregroundColor: Colors.red,
                elevation: 0,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const _SettingsGroup({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: items),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.black.withValues(alpha: 0.8), size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
    );
  }
}
