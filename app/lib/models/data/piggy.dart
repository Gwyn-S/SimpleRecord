/// 小金库实体：owner + peer（两人）共享的全局资产，跨账本，双方可存取。
/// 云端 piggy 表字段：id / name / owner_email / peer_email / invite_code / created_at。
class Piggy {
  final String id;
  String name;
  final String? ownerAuthorId;
  final String? peerAuthorId;
  final String inviteCode;
  final int createdAt;

  Piggy({
    required this.id,
    this.name = '小金库',
    this.ownerAuthorId,
    this.peerAuthorId,
    this.inviteCode = '',
    this.createdAt = 0,
  });

  /// 对方参与人（非本机的那位），用于列表/详情展示；本机 email 之外返回 null。
  String? peerAuthorIdFor(String myEmail) {
    if (myEmail.isEmpty) return null;
    if (ownerAuthorId == myEmail) return peerAuthorId;
    return ownerAuthorId;
  }

  Map<String, dynamic> toDbMap() => {
    'id': id,
    'name': name,
    'owner_author_id': ownerAuthorId,
    'peer_author_id': peerAuthorId,
    'invite_code': inviteCode,
    'created_at': createdAt,
  };

  factory Piggy.fromDbMap(Map<String, dynamic> map) => Piggy(
    id: map['id'] as String,
    name: map['name'] as String? ?? '小金库',
    ownerAuthorId: map['owner_author_id'] as String?,
    peerAuthorId: map['peer_author_id'] as String?,
    inviteCode: map['invite_code'] as String? ?? '',
    createdAt: map['created_at'] as int? ?? 0,
  );
}

/// 小金库流水事件：对应云端 piggy_ops 的一行，op_id 为幂等键。
/// delta 正 = 存入、负 = 取出。
class PiggyEvent {
  final int id;
  final int opId;
  final String piggyId;
  final String op;
  final int delta;
  final String remark;
  final String operatorEmail;
  final int createdAt;

  PiggyEvent({
    required this.id,
    required this.opId,
    required this.piggyId,
    required this.op,
    required this.delta,
    this.remark = '',
    this.operatorEmail = '',
    this.createdAt = 0,
  });

  bool get isDeposit => op == 'deposit' || delta > 0;

  factory PiggyEvent.fromDbMap(Map<String, dynamic> map) => PiggyEvent(
    id: map['id'] as int,
    opId: map['op_id'] as int,
    piggyId: map['piggy_id'] as String,
    op: map['op'] as String,
    delta: map['delta'] as int,
    remark: map['remark'] as String? ?? '',
    operatorEmail: map['operator_email'] as String? ?? '',
    createdAt: map['created_at'] as int? ?? 0,
  );
}