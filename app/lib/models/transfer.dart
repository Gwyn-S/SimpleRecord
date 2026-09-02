import '../utils/formatters.dart';

class Transfer {
  final String id;
  final String fromAccountId;
  final String toAccountId;
  final int amountCents;
  final int feeCents;
  final String remark;
  final DateTime date;
  final DateTime createdAt;
  final String? fromAccountName;
  final String? toAccountName;

  Transfer({
    required this.id,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountCents,
    this.feeCents = 0,
    this.remark = '',
    required this.date,
    required this.createdAt,
    this.fromAccountName,
    this.toAccountName,
  });

  Map<String, dynamic> toDbMap() => {
    'id': id,
    'from_account_id': fromAccountId,
    'to_account_id': toAccountId,
    'amount_cents': amountCents,
    'fee_cents': feeCents,
    'remark': remark,
    'date': toEpochDay(date),
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory Transfer.fromDbMap(Map<String, dynamic> map) => Transfer(
    id: map['id'] as String,
    fromAccountId: map['from_account_id'] as String,
    toAccountId: map['to_account_id'] as String,
    amountCents: map['amount_cents'] as int,
    feeCents: map['fee_cents'] as int? ?? 0,
    remark: map['remark'] as String? ?? '',
    date: fromEpochDay(map['date'] as int),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    fromAccountName: map['from_account_name'] as String?,
    toAccountName: map['to_account_name'] as String?,
  );
}
