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
      version: 11,
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
    final accountCols2 = await db.rawQuery('PRAGMA table_info(asset_accounts)');
    if (!accountCols2.any((c) => c['name'] == 'icon_path')) {
      await db.execute('ALTER TABLE asset_accounts ADD COLUMN icon_path TEXT NOT NULL DEFAULT \'\'');
    }
    final transferTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'transfers'");
    if (transferTables.isEmpty) {
      await db.execute('''
        CREATE TABLE transfers (
          id TEXT PRIMARY KEY,
          from_account_id TEXT NOT NULL,
          to_account_id TEXT NOT NULL,
          amount_cents INTEGER NOT NULL,
          fee_cents INTEGER NOT NULL DEFAULT 0,
          remark TEXT NOT NULL DEFAULT '',
          date INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    final transferCols = await db.rawQuery('PRAGMA table_info(transfers)');
    if (!transferCols.any((c) => c['name'] == 'fee_cents')) {
      await db.execute(
          'ALTER TABLE transfers ADD COLUMN fee_cents INTEGER NOT NULL DEFAULT 0');
    }
    final tagTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'tags'");
    if (tagTables.isEmpty) {
      await db.execute('''
        CREATE TABLE tags (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    final recordCols2 = await db.rawQuery('PRAGMA table_info(records)');
    if (!recordCols2.any((c) => c['name'] == 'tag')) {
      await db.execute('ALTER TABLE records ADD COLUMN tag TEXT');
    }
    final tagCols = await db.rawQuery('PRAGMA table_info(tags)');
    if (!tagCols.any((c) => c['name'] == 'sort_order')) {
      await db.execute(
          'ALTER TABLE tags ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
      // 老库按创建顺序补齐初始排序
      await db.execute(
          'UPDATE tags SET sort_order = rowid WHERE sort_order = 0');
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
        created_at INTEGER NOT NULL,
        tag TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE asset_accounts (
        id TEXT PRIMARY KEY,
        category_name TEXT NOT NULL,
        name TEXT NOT NULL,
        balance_cents INTEGER NOT NULL DEFAULT 0,
        remark TEXT NOT NULL DEFAULT '',
        card_last4 TEXT NOT NULL DEFAULT '',
        icon_path TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE transfers (
        id TEXT PRIMARY KEY,
        from_account_id TEXT NOT NULL,
        to_account_id TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        fee_cents INTEGER NOT NULL DEFAULT 0,
        remark TEXT NOT NULL DEFAULT '',
        date INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
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
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE asset_accounts ADD COLUMN icon_path TEXT NOT NULL DEFAULT \'\'');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE transfers (
          id TEXT PRIMARY KEY,
          from_account_id TEXT NOT NULL,
          to_account_id TEXT NOT NULL,
          amount_cents INTEGER NOT NULL,
          remark TEXT NOT NULL DEFAULT '',
          date INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 9) {
      await db.execute(
          'ALTER TABLE transfers ADD COLUMN fee_cents INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tags (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final cols = await db.rawQuery('PRAGMA table_info(records)');
      if (!cols.any((c) => c['name'] == 'tag')) {
        await db.execute('ALTER TABLE records ADD COLUMN tag TEXT');
      }
    }
    if (oldVersion < 11) {
      final cols = await db.rawQuery('PRAGMA table_info(tags)');
      if (!cols.any((c) => c['name'] == 'sort_order')) {
        await db.execute(
            'ALTER TABLE tags ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
        await db.execute(
            'UPDATE tags SET sort_order = rowid WHERE sort_order = 0');
      }
    }
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_records_book_date ON records(book_id, date)');
  }
}
