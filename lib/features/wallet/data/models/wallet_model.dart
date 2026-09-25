class WalletModel {
  final double ngnBalance;
  final double usdBalance;
  final double cfaBalance;
  final double ngnBonus;
  final String activeCurrency;

  const WalletModel({
    this.ngnBalance = 0.0,
    this.usdBalance = 0.0,
    this.cfaBalance = 0.0,
    this.ngnBonus = 0.0,
    this.activeCurrency = 'NGN',
  });

  factory WalletModel.fromJson(Map<String, dynamic> json) {
    final wallets = json['wallets'] as Map<String, dynamic>? ?? {};
    final ngnMap = wallets['NGN'] as Map<String, dynamic>? ?? {};
    final usdMap = wallets['USD'] as Map<String, dynamic>? ?? {};
    final cfaMap = wallets['XOF'] as Map<String, dynamic>? ?? {};

    return WalletModel(
      ngnBalance: (ngnMap['balance'] as num?)?.toDouble() ?? (json['balance'] as num?)?.toDouble() ?? 0.0,
      usdBalance: (usdMap['balance'] as num?)?.toDouble() ?? 0.0,
      cfaBalance: (cfaMap['balance'] as num?)?.toDouble() ?? 0.0,
      ngnBonus: (ngnMap['bonusBalance'] as num?)?.toDouble() ?? 0.0,
      activeCurrency: json['activeCurrency'] as String? ?? 'NGN',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'wallets': {
        'NGN': {'balance': ngnBalance, 'bonusBalance': ngnBonus},
        'USD': {'balance': usdBalance},
        'XOF': {'balance': cfaBalance},
      },
      'balance': ngnBalance,
      'activeCurrency': activeCurrency,
    };
  }
}
