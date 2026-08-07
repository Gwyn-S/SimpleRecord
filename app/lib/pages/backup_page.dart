import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../services/asset_account_service.dart';
import '../services/database.dart';
import '../services/record_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  List<File> _files = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<Directory> _backupDir() async {
    final dir = await getApplicationSupportDirectory();
    final backupDir = Directory(p.join(dir.path, 'backup'));
    if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
    return backupDir;
  }

  Future<void> _refresh() async {
    final dir = await _backupDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (!mounted) return;
    setState(() => _files = files);
  }

  Future<void> _doBackup() async {
    setState(() => _busy = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final books = await db.query('books');
      final records = await db.query('records');
      final accounts = await db.query('asset_accounts');
      final data = JsonEncoder.withIndent('  ').convert({
        'app': 'simple_record',
        'exportedAt': DateTime.now().toIso8601String(),
        'currentBookId': currentBookId.value,
        'books': books,
        'records': records,
        'asset_accounts': accounts,
      });
      final now = DateTime.now();
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
      final dir = await _backupDir();
      await File(p.join(dir.path, 'backup_$stamp.json')).writeAsString(data);
      await _refresh();
      _toast('备份成功');
    } catch (e) {
      _toast('备份失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final books = await db.query('books');
      final nameById = {
        for (final b in books) b['id'] as String?: b['name'] as String,
      };
      final rows = await db.query('records', orderBy: 'date DESC, created_at DESC');
      final buffer = StringBuffer();
      buffer.writeln('账本,日期,收支,分类,金额,备注');
      for (final r in rows) {
        final date = DateTime.utc(1970).add(Duration(days: r['date'] as int));
        final fields = [
          _csvEscape(nameById[r['book_id']] ?? ''),
          '${date.year}-${_two(date.month)}-${_two(date.day)}',
          r['is_expense'] == 1 ? '支出' : '收入',
          _csvEscape(r['category_name'] as String),
          formatAmount(r['amount_cents'] as int),
          _csvEscape(r['remark'] as String),
        ];
        buffer.writeln(fields.join(','));
      }
      final now = DateTime.now();
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
      final dir = await _backupDir();
      final path = p.join(dir.path, 'export_$stamp.csv');
      await File(path).writeAsString('\uFEFF$buffer', encoding: utf8);
      _toast('导出成功：$path');
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _doRestore(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复备份'),
        content: const Text('将用备份覆盖当前全部数据，且不可撤销。确定恢复吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复', style: TextStyle(color: colorDelete)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        await txn.delete('records');
        await txn.delete('books');
        await txn.delete('asset_accounts');
        for (final row in map['books'] as List<dynamic>) {
          await txn.insert('books', (row as Map).cast<String, dynamic>(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final row in map['records'] as List<dynamic>) {
          await txn.insert('records', (row as Map).cast<String, dynamic>(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final row in map['asset_accounts'] as List<dynamic>) {
          await txn.insert('asset_accounts',
              (row as Map).cast<String, dynamic>(),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      await saveCurrentBookId(map['currentBookId'] as String?);
      recordsVersion.value++;
      assetAccountsVersion.value++;
      _toast('恢复成功');
    } catch (e) {
      _toast('恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doDelete(File file) async {
    try {
      await file.delete();
      await _refresh();
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('备份'),
        backgroundColor: colorBackgroundCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(spacingL, spacingL, spacingL, 0),
            child: ValueListenableBuilder<Color>(
              valueListenable: themeColorNotifier,
              builder: (context, color, _) => Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _doBackup,
                        icon: const Icon(Icons.backup_outlined),
                        label: const Text('立即备份'),
                        style: FilledButton.styleFrom(backgroundColor: color),
                      ),
                    ),
                  ),
                  const SizedBox(width: spacingM),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _exportCsv,
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('导出 CSV'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _files.isEmpty
                ? const Center(
                    child: Text('暂无备份，点击上方立即备份',
                        style: TextStyle(fontSize: 14, color: colorTextPlaceholder)),
                  )
                : ListView.separated(
                    itemCount: _files.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, thickness: 0.5, color: colorDivider),
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final name =
                          file.path.split(Platform.pathSeparator).last;
                      return ListTile(
                        title: Text(name,
                            style: const TextStyle(
                                fontSize: 14, color: colorTextPrimary)),
                        subtitle: Text(_fileSize(file.lengthSync()),
                            style: const TextStyle(
                                fontSize: 12, color: colorTextSecondary)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore, size: 20),
                              onPressed: _busy ? null : () => _doRestore(file),
                              tooltip: '恢复',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: colorTextSecondary),
                              onPressed: () => _doDelete(file),
                              tooltip: '删除',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
