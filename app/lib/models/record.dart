import 'dart:convert';

import '../utils/formatters.dart';

class Record {
  final String id;
  final String? ledgerId;
  final String? accountId;
  final bool isExpense;
  final String categoryName;
  final int amountCents;
  final String remark;
  final String? tag;
  final DateTime date;
  final DateTime createdAt;
  final String? accountName;
  final List<String>? imagePaths;
  final String? author;

  /// 从数据库原始字符串解析图片路径列表。
  static List<String> imagePathsFromDb(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return [raw];
  }

  Record({
    required this.id,
    this.ledgerId,
    this.accountId,
    required this.isExpense,
    required this.categoryName,
    required this.amountCents,
    this.remark = '',
    this.tag,
    required this.date,
    required this.createdAt,
    this.accountName,
    this.imagePaths,
    this.author,
  });

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'book_id': ledgerId,
        'account_id': accountId,
        'is_expense': isExpense ? 1 : 0,
        'category_name': categoryName,
        'amount_cents': amountCents,
        'remark': remark,
        'date': toEpochDay(date),
        'created_at': createdAt.millisecondsSinceEpoch,
        'tag': tag,
        'image_path': imagePaths != null ? jsonEncode(imagePaths) : null,
        'author': author,
      };

  factory Record.fromDbMap(Map<String, dynamic> map) {
    final raw = map['image_path'] as String?;
    List<String>? paths;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          paths = decoded.cast<String>();
        }
      } catch (_) {
        paths = [raw];
      }
    }
    return Record(
      id: map['id'] as String,
      ledgerId: map['book_id'] as String?,
      accountId: map['account_id'] as String?,
      isExpense: map['is_expense'] == 1,
      categoryName: map['category_name'] as String,
      amountCents: map['amount_cents'] as int,
      remark: map['remark'] as String? ?? '',
      tag: map['tag'] as String?,
      date: fromEpochDay(map['date'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      accountName: map['account_name'] as String?,
      imagePaths: paths,
      author: map['author'] as String?,
    );
  }

  /// 浅拷贝并覆盖指定字段。
  Record copyWith({
    String? author,
  }) {
    return Record(
      id: id,
      ledgerId: ledgerId,
      accountId: accountId,
      isExpense: isExpense,
      categoryName: categoryName,
      amountCents: amountCents,
      remark: remark,
      tag: tag,
      date: date,
      createdAt: createdAt,
      accountName: accountName,
      imagePaths: imagePaths,
      author: author ?? this.author,
    );
  }
}
