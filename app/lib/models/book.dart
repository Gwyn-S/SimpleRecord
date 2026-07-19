class Book {
  final String id;
  String name;

  Book({required this.id, required this.name});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
  };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: json['name'] as String,
  );
}
