import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/category.dart';
import '../services/ledger_service.dart';
import '../services/database.dart';

/// 开发期一次性填充测试数据。调用一次后下次启动就失效。
/// 目的：让用户能立刻感知「切换账本后展开状态残留」「账单分组」等交互。
Future<void> seedTestDataIfNeeded() async {
  final existing = await _countExisting();
  if (existing >= 60) return;
  await _seedLedgers();
  await _seedRecords();
}

Future<int> _countExisting() async {
  final db = await DatabaseHelper.instance.database;
  final r = await db.rawQuery('SELECT COUNT(*) as c FROM records');
  final rows = r;
  if (rows.isEmpty) return 0;
  return (rows.first['c'] as int?) ?? 0;
}

Future<void> _seedLedgers() async {
  final ledgers = await loadLedgers();
  if (ledgers.length >= 2) return;
  final db = await DatabaseHelper.instance.database;
  if (ledgers.isEmpty) {
    await db.insert('books', <String, Object?>{
      'id': _id(),
      'name': '日常',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await db.insert('books', <String, Object?>{
    'id': _id(),
    'name': '旅行',
    'created_at': DateTime.now().millisecondsSinceEpoch,
  },
      conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _seedRecords() async {
  final ledgers = await loadLedgers();
  if (ledgers.isEmpty) return;
  final db = await DatabaseHelper.instance.database;
  final r = _Rand();
  final now = DateTime.now();
  for (final ledger in ledgers) {
    for (int dy = 0; dy < 90; dy++) {
      if (r.nextInt(3) == 0) continue;
      final day = now.subtract(Duration(days: dy));
      final isExp = r.nextBool();
      final cats = isExp ? expenseCategories : incomeCategories;
      final cat = cats[r.nextInt(cats.length)];
      final cents = [5, 10, 15, 20, 30, 50, 100, 200, 500][r.nextInt(9)] * 100;
      await db.insert('records', <String, Object?>{
        'id': _id(),
        'book_id': ledger.id,
        'is_expense': isExp ? 1 : 0,
        'category_name': cat.name,
        'amount_cents': cents,
        'remark': r.nextBool() ? '备注测试' : '',
        'date': DateTime.utc(day.year, day.month, day.day)
            .difference(DateTime.utc(1970))
            .inDays,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}

String _id() => const Uuid().v4();

class _Rand {
  final math.Random _r = math.Random();
  bool nextBool() => _r.nextBool();
  int nextInt(int n) => _r.nextInt(n);
}
