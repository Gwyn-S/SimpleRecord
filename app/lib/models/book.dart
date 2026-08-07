class Book {
  final String id;
  String name;
  final int createdAt;

  Book({required this.id, required this.name, this.createdAt = 0});

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt,
      };

  factory Book.fromDbMap(Map<String, dynamic> map) => Book(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: map['created_at'] as int? ?? 0,
      );
}
