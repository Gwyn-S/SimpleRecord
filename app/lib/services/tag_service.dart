import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'record_service.dart';
import '../utils/id.dart';

final ValueNotifier<int> tagsVersion = ValueNotifier(0);

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

Future<List<Tag>> loadTags() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query('tags', orderBy: 'sort_order ASC, created_at ASC');
  return rows.map(Tag.fromDbMap).toList();
}

/// 新建标签；同名已存在时直接返回已有标签。
Future<Tag> insertTag(String name) async {
  final db = await DatabaseHelper.instance.database;
  final trimmed = name.trim();
  final existing = await db.query('tags', where: 'name = ?', whereArgs: [trimmed]);
  if (existing.isNotEmpty) return Tag.fromDbMap(existing.first);
  final tag = Tag(id: genId(), name: trimmed);
  await db.insert('tags', {
    'id': tag.id,
    'name': tag.name,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  tagsVersion.value++;
  return tag;
}

/// 按给定顺序持久化标签排序（sort_order 0..n）。
Future<void> reorderTags(List<Tag> ordered) async {
  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    for (var i = 0; i < ordered.length; i++) {
      await txn.update('tags', {'sort_order': i},
          where: 'id = ?', whereArgs: [ordered[i].id]);
    }
  });
  tagsVersion.value++;
}

/// 重命名标签，并同步更新 records 中引用该标签的记录。
Future<void> renameTag(String oldName, String newName) async {
  final db = await DatabaseHelper.instance.database;
  final trimmed = newName.trim();
  if (trimmed.isEmpty || trimmed == oldName) return;
  await db.transaction((txn) async {
    await txn.update('tags', {'name': trimmed},
        where: 'name = ?', whereArgs: [oldName]);
    await txn.update('records', {'tag': trimmed},
        where: 'tag = ?', whereArgs: [oldName]);
  });
  tagsVersion.value++;
  recordsVersion.value++;
}

/// 删除标签，并清空 records 中对该标签的引用。
Future<void> deleteTag(String name) async {
  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    await txn.delete('tags', where: 'name = ?', whereArgs: [name]);
    await txn.update('records', {'tag': null},
        where: 'tag = ?', whereArgs: [name]);
  });
  tagsVersion.value++;
  recordsVersion.value++;
}
