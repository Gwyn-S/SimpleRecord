import '../../utils/formatters.dart';

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
  final String operatorEmail;
  final String operatorNickname;
  final String? operatorAvatarUrl;

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
    this.operatorEmail = '',
    this.operatorNickname = '',
    this.operatorAvatarUrl,
  });

  Transfer copyWith({
    String? operatorNickname,
    String? operatorAvatarUrl,
  }) => Transfer(
    id: id,
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    amountCents: amountCents,
    feeCents: feeCents,
    remark: remark,
    date: date,
    createdAt: createdAt,
    fromAccountName: fromAccountName,
    toAccountName: toAccountName,
    operatorEmail: operatorEmail,
    operatorNickname: operatorNickname ?? this.operatorNickname,
    operatorAvatarUrl: operatorAvatarUrl ?? this.operatorAvatarUrl,
  );

  Map<String, dynamic> toDbMap() => {
    'id': id,
    'from_account_id': fromAccountId,
    'to_account_id': toAccountId,
    'amount_cents': amountCents,
    'fee_cents': feeCents,
    'remark': remark,
    'date': toEpochDay(date),
    'created_at': createdAt.millisecondsSinceEpoch,
    'operator_email': operatorEmail,
    'operator_nickname': operatorNickname,
    'operator_avatar_url': operatorAvatarUrl ?? '',
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
    operatorEmail: (map['operator_email'] as String?) ?? '',
    operatorNickname: (map['operator_nickname'] as String?) ?? '',
    operatorAvatarUrl: map['operator_avatar_url'] as String?,
  );
}
