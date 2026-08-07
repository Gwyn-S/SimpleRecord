import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/record.dart';
import 'database.dart';

const _currentBookKey = 'currentBookId';

final ValueNotifier<int> recordsVersion = ValueNotifier(0);
final ValueNotifier<String?> currentBookId = ValueNotifier(null);
final ValueNotifier<DateTime> currentMonth = ValueNotifier(DateTime(DateTime.now().year, DateTime.now().month));

int _epochDayOf(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1970)).inDays;

Future<void> loadCurrentBookId() async {
  final prefs = await SharedPreferences.getInstance();
  currentBookId.value = prefs.getString(_currentBookKey);
}

Future<void> saveCurrentBookId(String? id) async {
  final prefs = await SharedPreferences.getInstance();
  if (id == null) {
    await prefs.remove(_currentBookKey);
  } else {
    await prefs.setString(_currentBookKey, id);
  }
  // 只置 currentBookId：ValueNotifier 值变化本身就会触发一次 reload，
  // 不再额外 ++recordsVersion，避免切账本时双触发两次全量加载。
  currentBookId.value = id;
}

Future<List<Record>> loadRecords({String? bookId, DateTime? month}) async {
  final db = await DatabaseHelper.instance.database;
  final where = <String>[];
  final args = <Object>[];
  if (bookId != null) {
    where.add('book_id = ?');
    args.add(bookId);
  }
  if (month != null) {
    final start = _epochDayOf(month);
    final end = _epochDayOf(DateTime(month.year, month.month + 1));
    where.add('date >= ? AND date < ?');
    args.add(start);
    args.add(end);
  }
  final rows = await db.query(
    'records',
    where: where.isEmpty ? null : where.join(' AND '),
    whereArgs: args.isEmpty ? null : args,
    orderBy: 'date DESC, created_at DESC',
  );
  return rows.map(Record.fromDbMap).toList();
}

Future<void> insertRecord(Record record) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('records', record.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);
  recordsVersion.value++;
}

Future<void> updateRecord(Record record) async {
  final db = await DatabaseHelper.instance.database;
  await db.update('records', record.toDbMap(),
      where: 'id = ?', whereArgs: [record.id]);
  recordsVersion.value++;
}

Future<void> deleteRecord(String id) async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('records', where: 'id = ?', whereArgs: [id]);
  recordsVersion.value++;
}
