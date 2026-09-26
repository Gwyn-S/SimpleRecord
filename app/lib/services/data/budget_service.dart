import 'package:sqflite/sqflite.dart';

import '../core/database.dart';

/// 预算存储：按账本存"全局规则"（不区分月份）。
/// 每行一条预算：category_id 为空串表示总预算，否则为分类名。
/// 金额设 0 即删除该行（等同不设预算），保证稀疏存储、无历史膨胀。
class BudgetService {
  BudgetService._();

  static final BudgetService instance = BudgetService._();

  static const _table = 'budgets';

  static const emptyCategory = '';

  Future<Database> get _db async => DatabaseHelper.instance.database;

  /// 读取账本总预算；未设置返回 0。
  Future<int> getTotalBudget(String ledgerId) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      columns: ['amount_cents'],
      where: 'ledger_id = ? AND category_id = ?',
      whereArgs: [ledgerId, emptyCategory],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['amount_cents'] as int?) ?? 0;
  }

  /// 读取账本全部分类预算（Map：分类名 -> 金额，仅包含已设置的）。
  Future<Map<String, int>> getCategoryBudgets(String ledgerId) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      columns: ['category_id', 'amount_cents'],
      where: 'ledger_id = ? AND category_id != ?',
      whereArgs: [ledgerId, emptyCategory],
    );
    return {
      for (final r in rows)
        if ((r['category_id'] as String).isNotEmpty)
          r['category_id'] as String: (r['amount_cents'] as int?) ?? 0,
    };
  }

  /// 读取单个分类预算；未设置返回 0。
  Future<int> getCategoryBudget(String ledgerId, String categoryId) async {
    final db = await _db;
    final rows = await db.query(
      _table,
      columns: ['amount_cents'],
      where: 'ledger_id = ? AND category_id = ?',
      whereArgs: [ledgerId, categoryId],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['amount_cents'] as int?) ?? 0;
  }

  /// 保存预算：金额为 0 时删除该行，否则覆盖写入。
  /// 分类预算的 [categoryId] 传分类名；总预算传 [emptyCategory]。
  Future<void> setBudget({
    required String ledgerId,
    required String categoryId,
    required int amountCents,
  }) async {
    final db = await _db;
    if (amountCents <= 0) {
      await db.delete(
        _table,
        where: 'ledger_id = ? AND category_id = ?',
        whereArgs: [ledgerId, categoryId],
      );
      return;
    }
    await db.insert(
      _table,
      {
        'ledger_id': ledgerId,
        'category_id': categoryId,
        'amount_cents': amountCents,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除账本全部预算（删除账本时调用）。
  Future<void> clearLedgerBudgets(String ledgerId) async {
    final db = await _db;
    await db.delete(_table, where: 'ledger_id = ?', whereArgs: [ledgerId]);
  }
}