class Record {
  final String id;
  final String? bookId;
  final bool isExpense;
  final String categoryName;
  final int amountCents;
  final String remark;
  final DateTime date;
  final DateTime createdAt;

  Record({
    required this.id,
    this.bookId,
    required this.isExpense,
    required this.categoryName,
    required this.amountCents,
    this.remark = '',
    required this.date,
    required this.createdAt,
  });

  static final DateTime _epoch = DateTime.utc(1970);

  int get _epochDay =>
      DateTime.utc(date.year, date.month, date.day).difference(_epoch).inDays;

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'book_id': bookId,
        'is_expense': isExpense ? 1 : 0,
        'category_name': categoryName,
        'amount_cents': amountCents,
        'remark': remark,
        'date': _epochDay,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Record.fromDbMap(Map<String, dynamic> map) => Record(
        id: map['id'] as String,
        bookId: map['book_id'] as String?,
        isExpense: map['is_expense'] == 1,
        categoryName: map['category_name'] as String,
        amountCents: map['amount_cents'] as int,
        remark: map['remark'] as String? ?? '',
        date: _epoch.add(Duration(days: map['date'] as int)),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}
