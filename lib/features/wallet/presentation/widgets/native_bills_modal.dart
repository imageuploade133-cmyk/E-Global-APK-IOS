import 'package:flutter/material.dart';
import 'package:wallet/core/constants/app_colors.dart';

class NativeBillsModal extends StatefulWidget {
  final String billCategory; // 'electricity' or 'cable'
  final VoidCallback? onSuccess;

  const NativeBillsModal({super.key, this.billCategory = 'electricity', this.onSuccess});

  static Future<void> show(BuildContext context, {String billCategory = 'electricity', VoidCallback? onSuccess}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NativeBillsModal(billCategory: billCategory, onSuccess: onSuccess),
    );
  }

  @override
  State<NativeBillsModal> createState() => _NativeBillsModalState();
}

class _NativeBillsModalState extends State<NativeBillsModal> {
  final _accountController = TextEditingController(); // Meter or Smartcard
  final _amountController = TextEditingController();

  String? _selectedProvider;
  String _meterType = 'PREPAID';
  String? _verifiedCustomerName;
  bool _isVerifying = false;
  bool _isSubmitting = false;

  final List<String> _electricityDiscos = [
    'Ikeja Electric (IKEDC)',
    'Eko Electricity (EKEDC)',
    'Abuja Electricity (AEDC)',
    'Kano Electricity (KEDCO)',
    'Enugu Electricity (EEDC)',
    'Port Harcourt Electric (PHED)',
  ];

  final List<String> _cableTvProviders = [
    'DSTV',
    'GOTV',
    'Startimes',
    'Showmax',
  ];

  @override
  void dispose() {
    _accountController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _onNumberChanged(String val) {
    if (val.length >= 10 && _selectedProvider != null) {
      _verifyBillAccount();
    } else {
      setState(() => _verifiedCustomerName = null);
    }
  }

  Future<void> _verifyBillAccount() async {
    setState(() => _isVerifying = true);
    await Future.delayed(const Duration(milliseconds: 700));

    if (mounted) {
      setState(() {
        _isVerifying = false;
        _verifiedCustomerName = 'CUSTOMER: JOHN DOE (${_accountController.text.substring(0, 4)}***)';
      });
    }
  }

  void _showPinDialog() {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Pay ${widget.billCategory.toUpperCase()}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Confirm payment for $_selectedProvider (${_accountController.text})',
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
                _processBillPayment();
              }
            },
            child: const Text('Confirm Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _processBillPayment() async {
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _isSubmitting = false);
      Navigator.pop(context);
      if (widget.onSuccess != null) widget.onSuccess!();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.billCategory.toUpperCase()} bill paid successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isElectricity = widget.billCategory == 'electricity';

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
              isElectricity ? 'Electricity Bill' : 'Cable TV Subscription',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black.withValues(alpha: 0.8)),
            ),
            Text(
              isElectricity ? 'Pay your DISCO power bill instantly' : 'Renew your DSTV, GOTV or Startimes TV',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // Provider Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedProvider,
              decoration: InputDecoration(
                labelText: isElectricity ? 'Select Electricity Provider' : 'Select TV Provider',
                prefixIcon: Icon(isElectricity ? Icons.lightbulb_outline : Icons.tv, color: AppColors.primary),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              items: (isElectricity ? _electricityDiscos : _cableTvProviders).map((prov) {
                return DropdownMenuItem<String>(
                  value: prov,
                  child: Text(prov, style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedProvider = val;
                  _verifiedCustomerName = null;
                });
                if (_accountController.text.length >= 10) _verifyBillAccount();
              },
            ),

            if (isElectricity) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _meterType = 'PREPAID'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _meterType == 'PREPAID' ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _meterType == 'PREPAID' ? AppColors.primary : Colors.transparent),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Prepaid',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _meterType == 'PREPAID' ? AppColors.primary : Colors.black.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _meterType = 'POSTPAID'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _meterType == 'POSTPAID' ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _meterType == 'POSTPAID' ? AppColors.primary : Colors.transparent),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Postpaid',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _meterType == 'POSTPAID' ? AppColors.primary : Colors.black.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),

            // Meter or Smartcard Number
            TextField(
              controller: _accountController,
              keyboardType: TextInputType.number,
              onChanged: _onNumberChanged,
              decoration: InputDecoration(
                labelText: isElectricity ? 'Meter Number' : 'Smartcard / IUC Number',
                prefixIcon: const Icon(Icons.pin, color: AppColors.primary),
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

            if (_verifiedCustomerName != null) ...[
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
                        _verifiedCustomerName!,
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

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

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: (_selectedProvider == null || _accountController.text.length < 8 || _amountController.text.isEmpty || _isSubmitting)
                    ? null
                    : _showPinDialog,
                child: _isSubmitting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text(
                        'Pay Bill',
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
