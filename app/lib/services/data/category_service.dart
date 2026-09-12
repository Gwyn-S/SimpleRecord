import 'package:flutter/foundation.dart' hide Category;
import 'package:sqflite/sqflite.dart';

import '../../models/data/category.dart';
import '../core/database.dart';
import '../cloud/sync_service.dart';
import 'record_service.dart';

final ValueNotifier<int> categoriesVersion = ValueNotifier(0);

/// 注册远端分类变更回调：远端应用的共享分类变更落到本地后，
/// 重新加载当前账本分类缓存（触发各页面重建）。
void initCategorySync() {
  SyncService.instance.onCategoryRemoteChanged = () async {
    await loadCategoryCache();
  };
}

/// 为某个账本写入默认分类种子。
Future<void> seedCategoriesForLedger(String ledgerId) async {
  final db = await DatabaseHelper.instance.database;
  final batch = db.batch();
  for (final c in [
    ...defaultExpenseCategorySeeds,
    ...defaultIncomeCategorySeeds,
  ]) {
    batch.insert(
      'categories',
      {...c.toDbMap(), 'ledger_id': ledgerId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
  await batch.commit(noResult: true);
}

/// 加载【当前账本】的分类到内存缓存（expenseCategories / incomeCategories）。
Future<void> loadCategoryCache() async {
  final cat = await loadCategoriesForLedger(currentLedgerId.value);
  expenseCategories = cat.where((c) => c.isExpense).toList();
  incomeCategories = cat.where((c) => !c.isExpense).toList();
  categoriesVersion.value++;
}

/// 加载指定账本的分类列表（按 sort_order 升序）。
Future<List<Category>> loadCategoriesForLedger(String? ledgerId) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'categories',
    where: 'ledger_id = ?',
    whereArgs: [ledgerId],
    orderBy: 'sort_order ASC',
  );
  return rows.map(Category.fromDbMap).toList();
}

/// 新增分类（当前账本）；同名已存在时返回 false 不插入。
Future<bool> insertCategory({
  required String name,
  required bool isExpense,
  String iconName = 'settings_outlined',
}) async {
  final ledgerId = currentLedgerId.value;
  final trimmed = name.trim();
  if (ledgerId == null || trimmed.isEmpty) return false;
  final db = await DatabaseHelper.instance.database;
  final existing = await db.query(
    'categories',
    where: 'ledger_id = ? AND name = ? AND is_expense = ?',
    whereArgs: [ledgerId, trimmed, isExpense ? 1 : 0],
  );
  if (existing.isNotEmpty) return false;
  final maxRow = await db.rawQuery(
    'SELECT COALESCE(MAX(sort_order), -1) AS mx FROM categories '
    'WHERE ledger_id = ? AND is_expense = ?',
    [ledgerId, isExpense ? 1 : 0],
  );
  final next = (maxRow.first['mx'] as int?) ?? -1;
  await db.insert('categories', {
    'ledger_id': ledgerId,
    'name': trimmed,
    'is_expense': isExpense ? 1 : 0,
    'icon_name': iconName,
    'sort_order': next + 1,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await SyncService.instance.enqueueCategory({
    'ledger_id': ledgerId,
    'name': trimmed,
    'is_expense': isExpense ? 1 : 0,
    'icon_name': iconName,
    'sort_order': next + 1,
  }, op: 'insert');
  await loadCategoryCache();
  return true;
}

/// 重命名分类（当前账本），并同步更新当前账本 records 中引用该分类的记录。
Future<bool> renameCategory(
  String oldName,
  String newName,
  bool isExpense,
) async {
  final ledgerId = currentLedgerId.value;
  final trimmed = newName.trim();
  if (ledgerId == null || trimmed.isEmpty || trimmed == oldName) return false;
  final db = await DatabaseHelper.instance.database;
  final existing = await db.query(
    'categories',
    where:
        'ledger_id = ? AND name = ? AND is_expense = ? AND name != ?',
    whereArgs: [ledgerId, trimmed, isExpense ? 1 : 0, oldName],
  );
  if (existing.isNotEmpty) return false;
  await db.transaction((txn) async {
    await txn.update(
      'categories',
      {'name': trimmed},
      where: 'ledger_id = ? AND name = ? AND is_expense = ?',
      whereArgs: [ledgerId, oldName, isExpense ? 1 : 0],
    );
    await txn.update(
      'records',
      {'category_name': trimmed},
      where:
          'book_id = ? AND category_name = ? AND is_expense = ?',
      whereArgs: [ledgerId, oldName, isExpense ? 1 : 0],
    );
  });
  recordsVersion.value++;
  await SyncService.instance.enqueueCategory({
    'ledger_id': ledgerId,
    'name': trimmed,
    'is_expense': isExpense ? 1 : 0,
  }, op: 'update');
  await loadCategoryCache();
  return true;
}

/// 按给定顺序持久化【当前账本】分类排序（sort_order 0..n）。
Future<void> reorderCategories(List<Category> ordered) async {
  final ledgerId = currentLedgerId.value;
  if (ledgerId == null) return;
  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    for (var i = 0; i < ordered.length; i++) {
      await txn.update(
        'categories',
        {'sort_order': i},
        where: 'ledger_id = ? AND name = ? AND is_expense = ?',
        whereArgs: [ledgerId, ordered[i].name, ordered[i].isExpense ? 1 : 0],
      );
    }
  });
  for (final c in ordered) {
    await SyncService.instance.enqueueCategory({
      'ledger_id': ledgerId,
      'name': c.name,
      'is_expense': c.isExpense ? 1 : 0,
      'icon_name': c.iconName,
      'sort_order': c.sortOrder,
    }, op: 'update');
  }
  await loadCategoryCache();
}

/// 删除分类（当前账本），并连带删除【当前账本】中该分类下的全部记录
/// （复用 deleteRecord 的余额/图片/同步逻辑）。返回删除的记录数。
Future<int> deleteCategory({
  required String name,
  required bool isExpense,
}) async {
  final db = await DatabaseHelper.instance.database;
  final ledgerId = currentLedgerId.value;
  if (ledgerId == null) return 0;
  final rows = await db.query(
    'records',
    columns: ['id'],
    where: 'book_id = ? AND category_name = ? AND is_expense = ?',
    whereArgs: [ledgerId, name, isExpense ? 1 : 0],
  );
  final ids = rows.map((r) => r['id'] as String).toList();
  for (final id in ids) {
    await deleteRecord(id);
  }
  await db.delete(
    'categories',
    where: 'ledger_id = ? AND name = ? AND is_expense = ?',
    whereArgs: [ledgerId, name, isExpense ? 1 : 0],
  );
  await SyncService.instance.enqueueCategory({
    'ledger_id': ledgerId,
    'name': name,
    'is_expense': isExpense ? 1 : 0,
  }, op: 'delete');
  await loadCategoryCache();
  return ids.length;
}