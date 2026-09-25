import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallet/core/constants/app_colors.dart';
import 'package:wallet/features/wallet/data/models/transaction_model.dart';
import 'package:wallet/features/wallet/data/repositories/wallet_repository.dart';

class NativeHistoryScreen extends StatefulWidget {
  const NativeHistoryScreen({super.key});

  @override
  State<NativeHistoryScreen> createState() => _NativeHistoryScreenState();
}

class _NativeHistoryScreenState extends State<NativeHistoryScreen> {
  final WalletRepository _walletRepository = WalletRepository();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String _selectedFilter = 'all'; // 'all' | 'credit' | 'debit' | 'vtu' | 'bills'
  List<TransactionModel> _allTransactions = [];
  List<TransactionModel> _filteredTransactions = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final cached = await _walletRepository.getCachedTransactions();
    if (mounted) {
      setState(() {
        _allTransactions = cached;
        _isLoading = false;
      });
      _applyFilters();
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredTransactions = _allTransactions.where((tx) {
        final matchesFilter = _selectedFilter == 'all' ||
            (_selectedFilter == 'credit' && tx.type == 'credit') ||
            (_selectedFilter == 'debit' && tx.type == 'debit') ||
            (_selectedFilter == 'vtu' && tx.category.toLowerCase().contains('vtu')) ||
            (_selectedFilter == 'bills' && tx.category.toLowerCase().contains('bill'));

        final matchesSearch = query.isEmpty ||
            tx.title.toLowerCase().contains(query) ||
            tx.reference.toLowerCase().contains(query) ||
            tx.category.toLowerCase().contains(query);

        return matchesFilter && matchesSearch;
      }).toList();
    });
  }

  void _showReceiptModal(TransactionModel tx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: tx.type == 'credit'
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                child: Icon(
                  tx.type == 'credit' ? Icons.arrow_downward : Icons.arrow_upward,
                  color: tx.type == 'credit' ? Colors.green : Colors.red,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${tx.type == 'credit' ? '+' : '-'}₦${tx.amount.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              tx.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            _ReceiptDetailRow(label: 'Status', value: tx.status.toUpperCase(), isSuccess: tx.status == 'completed'),
            _ReceiptDetailRow(label: 'Category', value: tx.category),
            _ReceiptDetailRow(label: 'Date & Time', value: tx.date),
            _ReceiptDetailRow(
              label: 'Reference',
              value: tx.reference,
              isCopyable: true,
              onCopy: () {
                Clipboard.setData(ClipboardData(text: tx.reference));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reference copied to clipboard')),
                );
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('DONE', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Activity History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // Filter Chips and Search Bar Box
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, category, or reference...',
                    hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _selectedFilter == 'all',
                        onSelected: () {
                          setState(() => _selectedFilter = 'all');
                          _applyFilters();
                        },
                      ),
                      _FilterChip(
                        label: 'Credits',
                        selected: _selectedFilter == 'credit',
                        onSelected: () {
                          setState(() => _selectedFilter = 'credit');
                          _applyFilters();
                        },
                      ),
                      _FilterChip(
                        label: 'Debits',
                        selected: _selectedFilter == 'debit',
                        onSelected: () {
                          setState(() => _selectedFilter = 'debit');
                          _applyFilters();
                        },
                      ),
                      _FilterChip(
                        label: 'Airtime & Data',
                        selected: _selectedFilter == 'vtu',
                        onSelected: () {
                          setState(() => _selectedFilter = 'vtu');
                          _applyFilters();
                        },
                      ),
                      _FilterChip(
                        label: 'Utility Bills',
                        selected: _selectedFilter == 'bills',
                        onSelected: () {
                          setState(() => _selectedFilter = 'bills');
                          _applyFilters();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Transaction List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _filteredTransactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.history, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'No transactions found',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadHistory,
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredTransactions.length,
                          itemBuilder: (context, index) {
                            final tx = _filteredTransactions[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
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
                                onTap: () => _showReceiptModal(tx),
                                leading: CircleAvatar(
                                  backgroundColor: tx.type == 'credit'
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : Colors.red.withValues(alpha: 0.1),
                                  child: Icon(
                                    tx.type == 'credit' ? Icons.arrow_downward : Icons.arrow_upward,
                                    color: tx.type == 'credit' ? Colors.green : Colors.red,
                                    size: 20,
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
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        checkmarkColor: AppColors.primary,
        labelStyle: TextStyle(
          color: selected ? AppColors.primary : Colors.black.withValues(alpha: 0.8),
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        backgroundColor: Colors.grey[100],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _ReceiptDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isSuccess;
  final bool isCopyable;
  final VoidCallback? onCopy;

  const _ReceiptDetailRow({
    required this.label,
    required this.value,
    this.isSuccess = false,
    this.isCopyable = false,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isSuccess ? Colors.green : Colors.black,
                ),
              ),
              if (isCopyable) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onCopy,
                  child: const Icon(Icons.copy, size: 16, color: AppColors.primary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
