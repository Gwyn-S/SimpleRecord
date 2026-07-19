import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/record.dart';

const _storageKey = 'records';
const _currentBookKey = 'currentBookId';

final ValueNotifier<int> recordsVersion = ValueNotifier(0);
final ValueNotifier<String?> currentBookId = ValueNotifier(null);
final ValueNotifier<List<Record>> allRecords = ValueNotifier([]);

void _syncRecords() async {
  allRecords.value = await loadRecords();
}

void initRecordsListener() {
  recordsVersion.addListener(_syncRecords);
  currentBookId.addListener(_syncRecords);
  _syncRecords();
}

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
