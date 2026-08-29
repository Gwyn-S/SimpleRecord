class Ledger {
  final String id;
  String name;
  final int createdAt;
  int syncMode;

  Ledger({
    required this.id,
    required this.name,
    this.createdAt = 0,
    this.syncMode = 0,
  });

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt,
        'sync_mode': syncMode,
      };

  factory Ledger.fromDbMap(Map<String, dynamic> map) => Ledger(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: map['created_at'] as int? ?? 0,
        syncMode: map['sync_mode'] as int? ?? 0,
      );
}
