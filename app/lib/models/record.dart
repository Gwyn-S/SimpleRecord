import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'records';
const _currentBookKey = 'currentBookId';

final ValueNotifier<int> recordsVersion = ValueNotifier(0);
final ValueNotifier<String?> currentBookId = ValueNotifier(null);

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
  currentBookId.value = id;
  recordsVersion.value++;
}

class Record {
  final String id;
  final String? bookId;
  final bool isExpense;
  final String categoryName;
  final double amount;
  final String remark;
  final DateTime date;
  final DateTime createdAt;

  Record({
    required this.id,
    this.bookId,
    required this.isExpense,
    required this.categoryName,
    required this.amount,
    this.remark = '',
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'isExpense': isExpense,
        'categoryName': categoryName,
        'amount': amount,
        'remark': remark,
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Record.fromJson(Map<String, dynamic> json) => Record(
        id: json['id'] as String,
        bookId: json['bookId'] as String?,
        isExpense: json['isExpense'] as bool,
        categoryName: json['categoryName'] as String,
        amount: (json['amount'] as num).toDouble(),
        remark: json['remark'] as String? ?? '',
        date: DateTime.parse(json['date'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

Future<List<Record>> loadRecords() async {
  final prefs = await SharedPreferences.getInstance();
  final str = prefs.getString(_storageKey);
  if (str == null) return [];
  final list = jsonDecode(str) as List;
  return list.map((e) => Record.fromJson(e as Map<String, dynamic>)).toList();
}

Future<void> saveRecords(List<Record> records) async {
  final prefs = await SharedPreferences.getInstance();
  final str = jsonEncode(records.map((r) => r.toJson()).toList());
  await prefs.setString(_storageKey, str);
  recordsVersion.value++;
}
