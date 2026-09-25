import 'package:flutter/material.dart';
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/features/auth/data/models/user_model.dart';
import 'package:wallet/features/wallet/data/models/wallet_model.dart';
import 'package:wallet/features/wallet/data/models/transaction_model.dart';
import 'package:wallet/features/wallet/data/repositories/wallet_repository.dart';

class NativeHomeScreen extends StatefulWidget {
  const NativeHomeScreen({super.key});

  @override
  State<NativeHomeScreen> createState() => _NativeHomeScreenState();
}

class _NativeHomeScreenState extends State<NativeHomeScreen> {
  final WalletRepository _walletRepository = WalletRepository();
  bool _isLoading = true;
  bool _hideBalance = false;
  String _selectedCurrency = 'NGN';
  UserModel? _user;
  WalletModel _wallet = const WalletModel();
  List<TransactionModel> _recentTransactions = [];

  @override
  void initState() {
    super.initState();
    _loadCachedDataAndSync();
  }

  Future<void> _loadCachedDataAndSync() async {
    // 1. Render cached safe data instantly without waiting on network
    final cachedUser = await _walletRepository.getCachedUser();
    final cachedWallet = await _walletRepository.getCachedWallet();
    final cachedTxs = await _walletRepository.getCachedTransactions();

    if (mounted) {
      setState(() {
        if (cachedUser != null) _user = cachedUser;
        if (cachedWallet != null) _wallet = cachedWallet;
        _recentTransactions = cachedTxs;
        _isLoading = false;
      });
    }

    // 2. Perform silent background API synchronization
    try {
      final remoteUser = await _walletRepository.fetchUserProfileFromApi();
      final remoteWallet = await _walletRepository.fetchWalletFromApi();
      final remoteTxs = await _walletRepository.fetchTransactionsFromApi();

      if (mounted) {
        setState(() {
          if (remoteUser != null) _user = remoteUser;
          if (remoteWallet != null) _wallet = remoteWallet;
          if (remoteTxs.isNotEmpty) _recentTransactions = remoteTxs;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final double displayBalance = _selectedCurrency == 'NGN'
        ? _wallet.ngnBalance
        : (_selectedCurrency == 'USD' ? _wallet.usdBalance : _wallet.cfaBalance);

    final String currencySymbol = _selectedCurrency == 'NGN'
        ? '₦'
        : (_selectedCurrency == 'USD' ? '\$' : 'CFA ');

    final String displayName = _user?.name.toUpperCase() ?? 'VALUED CAPTAIN';

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        titleSpacing: 16,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Image.asset('assets/images/logo.png', width: 22, height: 22),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WELCOME BACK',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.support_agent, color: Colors.black),
            onPressed: () {},
            tooltip: 'Support Agent',
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.black),
            onPressed: () {},
            tooltip: 'Notifications',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCachedDataAndSync,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Balance Card Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C1324), Color(0xFF141D30)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'TOTAL BALANCE',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => setState(() => _hideBalance = !_hideBalance),
                              child: Icon(
                                _hideBalance ? Icons.visibility_off : Icons.visibility,
                                color: Colors.white70,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                        // Currency Selector Toggle
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButton<String>(
                            value: _selectedCurrency,
                            dropdownColor: const Color(0xFF141D30),
                            underline: const SizedBox(),
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'NGN', child: Text('NGN (₦)')),
                              DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                              DropdownMenuItem(value: 'XOF', child: Text('CFA (CFA)')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedCurrency = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _isLoading
                        ? Container(
                            height: 36,
                            width: 160,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          )
                        : Text(
                            _hideBalance
                                ? '••••••••'
                                : '$currencySymbol${displayBalance.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                    const SizedBox(height: 20),
                    // Action Buttons Row inside Balance Card
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text('Add Money', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.send_outlined, size: 18),
                            label: const Text('Transfer', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. Quick Services Grid
              const Text(
                'QUICK SERVICES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                children: const [
                  _QuickServiceItem(icon: Icons.phone_android, label: 'Airtime', color: Colors.blue),
                  _QuickServiceItem(icon: Icons.wifi, label: 'Data', color: Colors.green),
                  _QuickServiceItem(icon: Icons.lightbulb_outline, label: 'Electricity', color: Colors.orange),
                  _QuickServiceItem(icon: Icons.tv, label: 'Cable TV', color: Colors.purple),
                  _QuickServiceItem(icon: Icons.trending_up, label: 'Invest', color: Colors.teal),
                  _QuickServiceItem(icon: Icons.credit_card, label: 'Cards', color: Colors.indigo),
                  _QuickServiceItem(icon: Icons.home_work_outlined, label: 'Estate', color: Colors.brown),
                  _QuickServiceItem(icon: Icons.grid_view, label: 'More', color: Colors.blueGrey),
                ],
              ),

              const SizedBox(height: 28),

              // 3. Recent Activity Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'RECENT ACTIVITY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 0.8,
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('See All', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              _isLoading
                  ? Column(
                      children: List.generate(
                        3,
                        (index) => Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Container(
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    )
                  : _recentTransactions.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: const [
                              Icon(Icons.history_toggle_off, size: 40, color: Colors.grey),
                              SizedBox(height: 8),
                              Text(
                                'No recent transactions',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: _recentTransactions
                              .map(
                                (tx) => Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.02),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: tx.type == 'credit'
                                          ? Colors.green.withValues(alpha: 0.1)
                                          : Colors.red.withValues(alpha: 0.1),
                                      child: Icon(
                                        tx.type == 'credit' ? Icons.arrow_downward : Icons.arrow_upward,
                                        color: tx.type == 'credit' ? Colors.green : Colors.red,
                                      ),
                                    ),
                                    title: Text(
                                      tx.title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    subtitle: Text(
                                      tx.date,
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                    trailing: Text(
                                      '${tx.type == 'credit' ? '+' : '-'}₦${tx.amount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: tx.type == 'credit' ? Colors.green : Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickServiceItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickServiceItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
