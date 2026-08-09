class Record {
  final String id;
  final String? ledgerId;
  final String? accountId;
  final bool isExpense;
  final String categoryName;
  final int amountCents;
  final String remark;
  final DateTime date;
  final DateTime createdAt;
  final String? accountName;

  Record({
    required this.id,
    this.ledgerId,
    this.accountId,
    required this.isExpense,
    required this.categoryName,
    required this.amountCents,
    this.remark = '',
    required this.date,
    required this.createdAt,
    this.accountName,
  });

  static final DateTime _epoch = DateTime.utc(1970);

  int get _epochDay =>
      DateTime.utc(date.year, date.month, date.day).difference(_epoch).inDays;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'book_id': ledgerId,
        'account_id': accountId,
        'is_expense': isExpense ? 1 : 0,
        'category_name': categoryName,
        'amount_cents': amountCents,
        'remark': remark,
        'date': _epochDay,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Record.fromDbMap(Map<String, dynamic> map) => Record(
        id: map['id'] as String,
        ledgerId: map['book_id'] as String?,
        accountId: map['account_id'] as String?,
        isExpense: map['is_expense'] == 1,
        categoryName: map['category_name'] as String,
        amountCents: map['amount_cents'] as int,
        remark: map['remark'] as String? ?? '',
        date: _epoch.add(Duration(days: map['date'] as int)),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        accountName: map['account_name'] as String?,
      );
}
