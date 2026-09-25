import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:wallet/core/constants/app_colors.dart';

class NativeVtuModal extends StatefulWidget {
  final String initialType; // 'airtime' or 'data'
  final VoidCallback? onSuccess;

  const NativeVtuModal({super.key, this.initialType = 'airtime', this.onSuccess});

  static Future<void> show(BuildContext context, {String initialType = 'airtime', VoidCallback? onSuccess}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NativeVtuModal(initialType: initialType, onSuccess: onSuccess),
    );
  }

  @override
  State<NativeVtuModal> createState() => _NativeVtuModalState();
}

class _NativeVtuModalState extends State<NativeVtuModal> {
  late String _serviceType;
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();

  String _selectedNetwork = 'MTN';
  String? _selectedDataPlan;
  bool _isSubmitting = false;

  final List<Map<String, String>> _networks = [
    {'name': 'MTN', 'code': 'mtn'},
    {'name': 'Airtel', 'code': 'airtel'},
    {'name': 'Glo', 'code': 'glo'},
    {'name': '9mobile', 'code': '9mobile'},
  ];

  final List<String> _dataPlansMTN = [
    '1.0 GB - 1 Day (₦300)',
    '2.5 GB - 2 Days (₦600)',
    '10.0 GB - 30 Days (₦3,000)',
    '20.0 GB - 30 Days (₦5,500)',
    '50.0 GB - 30 Days (₦11,000)',
  ];

  @override
  void initState() {
    super.initState();
    _serviceType = widget.initialType;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    try {
      if (await FlutterContacts.requestPermission()) {
        final contact = await FlutterContacts.openExternalPick();
        if (contact != null && contact.phones.isNotEmpty) {
          String rawPhone = contact.phones.first.number.replaceAll(RegExp(r'[^0-9+]'), '');
          if (rawPhone.startsWith('+234')) {
            rawPhone = '0${rawPhone.substring(4)}';
          }
          setState(() {
            _phoneController.text = rawPhone;
          });
        }
      }
    } catch (_) {
      // Fallback if permission or external picker fails
    }
  }

  void _showPinDialog() {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Confirm ${_serviceType.toUpperCase()}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Confirm $_selectedNetwork ${_serviceType.toUpperCase()} purchase for ${_phoneController.text}',
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
                _processPurchase();
              }
            },
            child: const Text('Confirm Purchase', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _processPurchase() async {
    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _isSubmitting = false);
      Navigator.pop(context);
      if (widget.onSuccess != null) widget.onSuccess!();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_serviceType.toUpperCase()} purchase processed successfully!'),
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

            // Tab Selector: Airtime vs Data
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _serviceType = 'airtime'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _serviceType == 'airtime' ? AppColors.primary : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Buy Airtime',
                        style: TextStyle(
                          color: _serviceType == 'airtime' ? Colors.white : Colors.black.withValues(alpha: 0.8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _serviceType = 'data'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _serviceType == 'data' ? AppColors.primary : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Buy Data',
                        style: TextStyle(
                          color: _serviceType == 'data' ? Colors.white : Colors.black.withValues(alpha: 0.8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Network Selector
            const Text('Select Network Provider', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _networks.map((net) {
                final isSelected = _selectedNetwork == net['name'];
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: InkWell(
                      onTap: () => setState(() => _selectedNetwork = net['name']!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey.shade50,
                          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.shade300, width: isSelected ? 2 : 1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          net['name']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? AppColors.primary : Colors.black.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Phone Input with Contact Picker
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: const Icon(Icons.phone_android, color: AppColors.primary),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.contacts, color: AppColors.primary),
                  onPressed: _pickContact,
                  tooltip: 'Pick from Contacts',
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 14),

            if (_serviceType == 'airtime')
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
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedDataPlan,
                decoration: InputDecoration(
                  labelText: 'Select Data Bundle Plan',
                  prefixIcon: const Icon(Icons.wifi, color: AppColors.primary),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                items: _dataPlansMTN.map((plan) {
                  return DropdownMenuItem<String>(
                    value: plan,
                    child: Text(plan, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedDataPlan = val),
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
                onPressed: (_phoneController.text.isEmpty ||
                        (_serviceType == 'airtime' && _amountController.text.isEmpty) ||
                        (_serviceType == 'data' && _selectedDataPlan == null) ||
                        _isSubmitting)
                    ? null
                    : _showPinDialog,
                child: _isSubmitting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        'Purchase ${_serviceType.toUpperCase()}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
