import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../models/record.dart';
import '../utils/id.dart';
import 'database.dart';
import 'record_service.dart';

int bookRecordCount(List<Record> records, String bookId) =>
    records.where((r) => r.bookId == bookId).length;

int bookIncome(List<Record> records, String bookId) =>
    records.where((r) => r.bookId == bookId && !r.isExpense).fold(0, (s, r) => s + r.amountCents);

int bookExpense(List<Record> records, String bookId) =>
    records.where((r) => r.bookId == bookId && r.isExpense).fold(0, (s, r) => s + r.amountCents);

Future<List<Book>> loadBooks() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query('books', orderBy: 'created_at');
  return rows.map(Book.fromDbMap).toList();
}

Future<void> insertBook(Book book) async {
  final db = await DatabaseHelper.instance.database;
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('books', {
    ...book.toDbMap(),
    'created_at': book.createdAt != 0 ? book.createdAt : now,
  },
      conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> updateBook(Book book) async {
  final db = await DatabaseHelper.instance.database;
  await db.update('books', book.toDbMap(),
      where: 'id = ?', whereArgs: [book.id]);
}

Future<void> deleteBook(String id) async {
  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    await txn.delete('records', where: 'book_id = ?', whereArgs: [id]);
    await txn.delete('books', where: 'id = ?', whereArgs: [id]);
  });
  recordsVersion.value++;
}

/// 确保存在一个有效的当前账本：无账本时创建默认账本，
/// currentBookId 为空或已失效时选中第一个账本。
Future<String> ensureCurrentBookId() async {
  final books = await loadBooks();
  if (books.isEmpty) {
    final book = Book(id: genId(), name: '日常');
    await insertBook(book);
    await saveCurrentBookId(book.id);
    return book.id;
  }
  if (currentBookId.value == null || !books.any((b) => b.id == currentBookId.value)) {
    await saveCurrentBookId(books.first.id);
  }
  return currentBookId.value!;
}
