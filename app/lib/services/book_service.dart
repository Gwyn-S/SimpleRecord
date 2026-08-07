import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import 'database.dart';

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
  await db.delete('books', where: 'id = ?', whereArgs: [id]);
}
