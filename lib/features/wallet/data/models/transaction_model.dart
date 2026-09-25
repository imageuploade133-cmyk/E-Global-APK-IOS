class TransactionModel {
  final String id;
  final String title;
  final String type; // 'credit' | 'debit'
  final double amount;
  final String currency;
  final String category;
  final String status;
  final String date;
  final String reference;

  const TransactionModel({
    required this.id,
    required this.title,
    required this.type,
    required this.amount,
    this.currency = 'NGN',
    this.category = 'General',
    this.status = 'completed',
    required this.date,
    required this.reference,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String? ?? json['reference'] as String? ?? '',
      title: json['title'] as String? ?? json['description'] as String? ?? json['recipientName'] as String? ?? 'Transaction',
      type: (json['type'] as String? ?? 'debit').toLowerCase(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'NGN',
      category: json['category'] as String? ?? 'General',
      status: json['status'] as String? ?? 'completed',
      date: json['date'] as String? ?? json['createdAt'] as String? ?? '',
      reference: json['reference'] as String? ?? json['txRef'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'amount': amount,
      'currency': currency,
      'category': category,
      'status': status,
      'date': date,
      'reference': reference,
    };
  }
}
