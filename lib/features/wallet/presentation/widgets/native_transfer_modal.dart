import 'package:flutter/material.dart';
import 'package:wallet/core/constants/app_colors.dart';

class NativeTransferModal extends StatefulWidget {
  final VoidCallback? onSuccess;

  const NativeTransferModal({super.key, this.onSuccess});

  static Future<void> show(BuildContext context, {VoidCallback? onSuccess}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NativeTransferModal(onSuccess: onSuccess),
    );
  }

  @override
  State<NativeTransferModal> createState() => _NativeTransferModalState();
}

class _NativeTransferModalState extends State<NativeTransferModal> {
  final _accountController = TextEditingController();
  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();

  final List<Map<String, String>> _popularBanks = [
    {'name': 'Access Bank', 'code': '044'},
    {'name': 'GTBank (Guaranty Trust)', 'code': '058'},
    {'name': 'First Bank of Nigeria', 'code': '011'},
    {'name': 'Zenith Bank', 'code': '057'},
    {'name': 'United Bank for Africa (UBA)', 'code': '033'},
    {'name': 'Kuda Bank', 'code': '50211'},
    {'name': 'OPay Digital Services', 'code': '999991'},
    {'name': 'Moniepoint Microfinance Bank', 'code': '50515'},
    {'name': 'Palmpay', 'code': '999992'},
    {'name': 'E-Global Pay Internal Transfer', 'code': '000000'},
  ];

  Map<String, String>? _selectedBank;
  bool _isVerifying = false;
  String? _accountName;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _accountController.dispose();
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _onAccountNumberChanged(String val) {
    if (val.length == 10 && _selectedBank != null) {
      _verifyAccount();
    } else {
      setState(() {
        _accountName = null;
      });
    }
  }

  Future<void> _verifyAccount() async {
    setState(() {
      _isVerifying = true;
    });

    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        _isVerifying = false;
        _accountName = 'VALUED CAPTAIN ACCOUNT (${_accountController.text.substring(0, 4)}***)';
      });
    }
  }

  void _showPinDialog() {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Enter Transaction PIN', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Confirm transfer of ₦${_amountController.text} to $_accountName',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if (pinController.text.length == 4) {
                Navigator.pop(context);
                _processTransfer();
              }
            },
            child: const Text('Confirm Transfer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _processTransfer() async {
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _isSubmitting = false);
      Navigator.pop(context);
      if (widget.onSuccess != null) widget.onSuccess!();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Transfer of funds initiated successfully!')),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bank Transfer',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black.withValues(alpha: 0.8)),
            ),
            const Text(
              'Send money instantly to any bank account',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // Select Bank
            DropdownButtonFormField<Map<String, String>>(
              initialValue: _selectedBank,
              decoration: InputDecoration(
                labelText: 'Select Bank',
                prefixIcon: const Icon(Icons.account_balance, color: AppColors.primary),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              items: _popularBanks.map((bank) {
                return DropdownMenuItem<Map<String, String>>(
                  value: bank,
                  child: Text(bank['name']!, style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedBank = val;
                  _accountName = null;
                });
                if (_accountController.text.length == 10) _verifyAccount();
              },
            ),
            const SizedBox(height: 14),

            // Account Number Input
            TextField(
              controller: _accountController,
              keyboardType: TextInputType.number,
              maxLength: 10,
              onChanged: _onAccountNumberChanged,
              decoration: InputDecoration(
                labelText: 'Account Number',
                counterText: '',
                prefixIcon: const Icon(Icons.numbers, color: AppColors.primary),
                suffixIcon: _isVerifying
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),

            if (_accountName != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _accountName!,
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Amount Input
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount (₦)',
                prefixIcon: const Icon(Icons.attach_money, color: AppColors.primary),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 14),

            // Narration Input
            TextField(
              controller: _remarkController,
              decoration: InputDecoration(
                labelText: 'Narration (Optional)',
                prefixIcon: const Icon(Icons.edit_note, color: AppColors.primary),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 20),

            // Fee Preview Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Transfer Fee:', style: TextStyle(fontSize: 12, color: Colors.orange)),
                  Text('₦10.00', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: (_selectedBank == null || _accountController.text.length != 10 || _amountController.text.isEmpty || _isSubmitting)
                    ? null
                    : _showPinDialog,
                child: _isSubmitting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text(
                        'Proceed with Transfer',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
