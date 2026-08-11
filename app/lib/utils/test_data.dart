import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/category.dart';
import '../services/ledger_service.dart';
import '../services/database.dart';

const _seedDoneKey = 'seed_test_data_done';

/// 开发期一次性填充测试数据。用 SharedPreferences 标志保证只播一次，
/// 避免用户在删过账本/记录后反复被补建、补灌。
/// 目的：让用户能立刻感知「切换账本后展开状态残留」「账单分组」等交互。
Future<void> seedTestDataIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_seedDoneKey) ?? false) return;
  final existing = await _countExisting();
  if (existing >= 60) {
    // 已有足够数据视为已播种，只补设标志，不再补灌。
    await prefs.setBool(_seedDoneKey, true);
    return;
  }
  await _seedLedgers();
  await _seedRecords();
  await prefs.setBool(_seedDoneKey, true);
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
  final names = ledgers.map((l) => l.name).toSet();
  final db = await DatabaseHelper.instance.database;
  if (ledgers.isEmpty) {
    await db.insert('books', <String, Object?>{
      'id': _id(),
      'name': '日常',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  if (!names.contains('旅行')) {
    await db.insert('books', <String, Object?>{
      'id': _id(),
      'name': '旅行',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<void> _seedRecords() async {
  final ledgers = await loadLedgers();
  if (ledgers.isEmpty) return;
  final db = await DatabaseHelper.instance.database;
  final r = _Rand();
  final now = DateTime.now();
  final batch = db.batch();
  const perLedger = 2500;
  for (final ledger in ledgers) {
    for (int i = 0; i < perLedger; i++) {
      final day = now.subtract(Duration(days: r.nextInt(90)));
      final isExp = r.nextBool();
      final cats = isExp ? expenseCategories : incomeCategories;
      final cat = cats[r.nextInt(cats.length)];
      final cents = [5, 10, 15, 20, 30, 50, 100, 200, 500][r.nextInt(9)] * 100;
      batch.insert('records', <String, Object?>{
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
  await batch.commit(noResult: true);
}

String _id() => const Uuid().v4();

class _Rand {
  final math.Random _r = math.Random();
  bool nextBool() => _r.nextBool();
  int nextInt(int n) => _r.nextInt(n);
}
