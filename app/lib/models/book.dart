class Book {
  final String id;
  String name;

  Book({required this.id, required this.name});

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'name': name,
      };

  factory Book.fromDbMap(Map<String, dynamic> map) => Book(
        id: map['id'] as String,
        name: map['name'] as String,
      );
}
