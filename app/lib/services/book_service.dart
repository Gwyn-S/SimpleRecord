import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../utils/id.dart';
import 'database.dart';
import 'record_service.dart';

Future<List<Book>> loadBooks() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query('books', orderBy: 'name');
  return rows.map(Book.fromDbMap).toList();
}

Future<void> insertBook(Book book) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('books', book.toDbMap(),
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
