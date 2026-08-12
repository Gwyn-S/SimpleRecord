import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  Future<Database>? _dbFuture;
  String? _dbPath;

  String get dbPath {
    final p = _dbPath;
    if (p == null) throw StateError('数据库尚未打开');
    return p;
  }

  Future<Database> get database => _dbFuture ??= _open();

  Future<void> close() async {
    final future = _dbFuture;
    _dbFuture = null;
    final db = future == null ? null : await future;
    if (db != null) await db.close();
  }

  /// 回收已删除数据的物理空间并清理孤儿记录：
  /// 删除账本/记录后调用，避免 DB 文件（含备份）只增不减。
  /// SQLite 默认 auto_vacuum=NONE，DELETE 只标记不回收页，
  /// 需 VACUUM 才真正抹掉并压缩文件。
  Future<void> vacuum() async {
    try {
      final db = await database;
      await db.execute(
          'DELETE FROM records WHERE book_id NOT IN (SELECT id FROM books)');
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('VACUUM');
      // WAL 模式下 VACUUM 的写入先进 WAL，需再次 checkpoint 才物理缩小主库文件
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // 压缩失败不阻塞删除流程，文件留待下次/备份时回收
    }
  }

  Future<Database> _open() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final dbPath = join(dir.path, 'simplerecord.db');
    _dbPath = dbPath;
    final db = await openDatabase(
      dbPath,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await _ensureSchema(db);
    return db;
  }

  /// 打开即自愈：历史遗留库的 books 表可能缺 created_at 列
  /// （v3 新建库由 onCreate 直接建表、不走 onUpgrade），幂等补列。
  Future<void> _ensureSchema(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(books)');
    if (!cols.any((c) => c['name'] == 'created_at')) {
      await db.execute('ALTER TABLE books ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0');
    }
    final recordCols = await db.rawQuery('PRAGMA table_info(records)');
    if (!recordCols.any((c) => c['name'] == 'account_id')) {
      await db.execute('ALTER TABLE records ADD COLUMN account_id TEXT');
    }
    final accountCols = await db.rawQuery('PRAGMA table_info(asset_accounts)');
    if (!accountCols.any((c) => c['name'] == 'remark')) {
      await db.execute('ALTER TABLE asset_accounts ADD COLUMN remark TEXT NOT NULL DEFAULT \'\'');
    }
    if (!accountCols.any((c) => c['name'] == 'card_last4')) {
      await db.execute('ALTER TABLE asset_accounts ADD COLUMN card_last4 TEXT NOT NULL DEFAULT \'\'');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE records (
        id TEXT PRIMARY KEY,
        book_id TEXT,
        account_id TEXT,
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
        balance_cents INTEGER NOT NULL DEFAULT 0,
        remark TEXT NOT NULL DEFAULT '',
        card_last4 TEXT NOT NULL DEFAULT ''
      )
    ''');
    await _upgradeToV2(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _upgradeToV2(db);
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE books ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE records ADD COLUMN account_id TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE asset_accounts ADD COLUMN remark TEXT NOT NULL DEFAULT \'\'');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE asset_accounts ADD COLUMN card_last4 TEXT NOT NULL DEFAULT \'\'');
    }
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_records_book_date ON records(book_id, date)');
  }
}
