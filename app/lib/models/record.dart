class Record {
  final String id;
  final String? bookId;
  final bool isExpense;
  final String categoryName;
  final double amount;
  final String remark;
  final DateTime date;
  final DateTime createdAt;

  Record({
    required this.id,
    this.bookId,
    required this.isExpense,
    required this.categoryName,
    required this.amount,
    this.remark = '',
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'isExpense': isExpense,
        'categoryName': categoryName,
        'amount': amount,
        'remark': remark,
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Record.fromJson(Map<String, dynamic> json) => Record(
        id: json['id'] as String,
        bookId: json['bookId'] as String?,
        isExpense: json['isExpense'] as bool,
        categoryName: json['categoryName'] as String,
        amount: (json['amount'] as num).toDouble(),
        remark: json['remark'] as String? ?? '',
        date: DateTime.parse(json['date'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
