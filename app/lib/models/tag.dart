/// 标签模型。
class Tag {
  final String id;
  final String name;
  final int sortOrder;

  const Tag({required this.id, required this.name, this.sortOrder = 0});

  factory Tag.fromDbMap(Map<String, dynamic> map) => Tag(
    id: map['id'] as String,
    name: map['name'] as String,
    sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
  );
}
