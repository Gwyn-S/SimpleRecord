import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';

Future<List<Book>> loadBooks() async {
  final prefs = await SharedPreferences.getInstance();
  final jsonStr = prefs.getString('books');
  if (jsonStr == null || jsonStr.isEmpty) return [];
  final list = jsonDecode(jsonStr) as List;
  return list.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
}

Future<void> saveBooks(List<Book> books) async {
  final prefs = await SharedPreferences.getInstance();
  final json = jsonEncode(books.map((e) => e.toJson()).toList());
  await prefs.setString('books', json);
}
