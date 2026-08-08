class Ledger {
  final String id;
  String name;
  final int createdAt;

  Ledger({required this.id, required this.name, this.createdAt = 0});

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt,
      };

  factory Ledger.fromDbMap(Map<String, dynamic> map) => Ledger(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: map['created_at'] as int? ?? 0,
      );
}
