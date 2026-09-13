import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/app_paths.dart';

/// 全局唯一的 SQLite 数据库访问入口（懒打开单例）。
class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  Future<Database>? _dbFuture;
  String? _dbPath;

  /// 已打开的数据库文件路径；尚未打开时抛 StateError。
  String get dbPath {
    final p = _dbPath;
    if (p == null) throw StateError('数据库尚未打开');
    return p;
  }

  /// 惰性打开并缓存数据库实例；首次访问时初始化。
  Future<Database> get database => _dbFuture ??= _open();

  /// 关闭数据库并释放连接；可安全重复调用。
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
        'DELETE FROM records WHERE book_id NOT IN (SELECT id FROM books)',
      );
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
    final dir = await appBaseDirectory();
    final dbPath = join(dir.path, 'simplerecord.db');
    _dbPath = dbPath;
    await _resetLegacyDb(dbPath);
    final db = await openDatabase(
      dbPath,
      // 未发布阶段：schema 恒为 V1，改动直接改 _onCreate 全量重建，
      // 不做版本迁移（旧库需删除后重建，见 _open 顶部的 _resetLegacyDb）。
      version: 1,
      onCreate: _onCreate,
    );
    return db;
  }

  /// 未发布阶段的历史遗留库（旧 schema <=v5 且无迁移路径）直接删除重建。
  /// schema 版本恒为 1；探测到旧版 user_version > 1 即整库重置，
  /// 保证以最新 _onCreate 全量重建，不依赖任何增量迁移。
  Future<void> _resetLegacyDb(String dbPath) async {
    final f = File(dbPath);
    if (!f.existsSync()) return;
    try {
      final probe = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 0),
      );
      final rows = await probe.rawQuery('PRAGMA user_version');
      final version = (rows.isNotEmpty ? rows.first['user_version'] : null) as int? ?? 0;
      await probe.close();
      if (version > 1) {
        f.deleteSync();
      }
    } catch (_) {
      // 库文件损坏或无法探测：交给正常打开流程按新 schema 重建/报错。
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0,
        sync_mode INTEGER NOT NULL DEFAULT 0,
        owner_author_id TEXT
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
        tag TEXT,
        image_path TEXT,
        author TEXT,
        author_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE asset_accounts (
        id TEXT PRIMARY KEY,
        category_name TEXT NOT NULL,
        name TEXT NOT NULL,
        balance_cents INTEGER NOT NULL DEFAULT 0,
        opening_balance_cents INTEGER NOT NULL DEFAULT 0,
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
    await db.execute(
      'CREATE INDEX idx_records_book_date ON records(book_id, date)',
    );
    await db.execute('''
      CREATE TABLE categories (
        ledger_id TEXT NOT NULL,
        name TEXT NOT NULL,
        is_expense INTEGER NOT NULL,
        icon_name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (ledger_id, name, is_expense)
      )
    ''');
    await db.execute('''
      CREATE TABLE balance_snapshots (
        account_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        balance INTEGER NOT NULL,
        PRIMARY KEY (account_id, date)
      )
    ''');
    await db.execute('''
      CREATE TABLE balance_adjustments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        delta INTEGER NOT NULL,
        before_cents INTEGER NOT NULL DEFAULT 0,
        after_cents INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // 小金库：owner + peer 两人共享的全局资产，跨账本。
    await db.execute('''
      CREATE TABLE piggies (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '小金库',
        owner_author_id TEXT,
        peer_author_id TEXT,
        invite_code TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // 小金库动作事件：本地镜像云端 piggy_ops，op_id 为幂等键。
    await db.execute('''
      CREATE TABLE piggy_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        op_id INTEGER NOT NULL,
        piggy_id TEXT NOT NULL,
        op TEXT NOT NULL,
        delta INTEGER NOT NULL,
        remark TEXT NOT NULL DEFAULT '',
        operator_email TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_piggy_events_op_id ON piggy_events(op_id)',
    );
    await _createSyncTables(db);
  }

  Future<void> _createSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        op TEXT NOT NULL,
        book_id TEXT NOT NULL DEFAULT '',
        payload TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0,
        state INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_sync_outbox_state ON sync_outbox(state)',
    );
    await db.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }
}
