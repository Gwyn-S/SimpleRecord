import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final dbPath = join(dir.path, 'simplerecord.db');
    return openDatabase(
      dbPath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE records (
        id TEXT PRIMARY KEY,
        book_id TEXT,
        is_expense INTEGER NOT NULL,
        category_name TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        remark TEXT NOT NULL DEFAULT '',
        date INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE asset_accounts (
        id TEXT PRIMARY KEY,
        category_name TEXT NOT NULL,
        name TEXT NOT NULL,
        balance_cents INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _upgradeToV2(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _upgradeToV2(db);
    }
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_records_book_date ON records(book_id, date)');
  }
}
