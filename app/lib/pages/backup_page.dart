import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/asset_account_service.dart';
import '../services/database.dart';
import '../services/record_service.dart';
import '../services/theme_service.dart';
import '../utils/formatters.dart';
import '../utils/toast.dart';

const _xorKey = 'SimpleRecord_SRB_v1';
const _magic = 'SRB1';

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
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/SimpleRecord/backup');
    } else {
      final support = await getApplicationSupportDirectory();
      dir = Directory(p.join(support.path, 'backup'));
    }
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> _refresh() async {
    final dir = await _backupDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.srb'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (!mounted) return;
    setState(() => _files = files);
  }

  Future<void> _doBackup() async {
    setState(() => _busy = true);
    showToast(context, '备份中…');
    try {
      final db = await DatabaseHelper.instance.database;
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final now = DateTime.now();
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
      final dir = await _backupDir();
      final metaBytes = utf8.encode(jsonEncode({
        'exportedAt': now.toIso8601String(),
        'currentBookId': currentLedgerId.value,
      }));
      final header = BytesBuilder()
        ..add(utf8.encode(_magic))
        ..add((ByteData(4)..setUint32(0, metaBytes.length, Endian.little))
            .buffer
            .asUint8List())
        ..add(metaBytes);
      final target = File(p.join(dir.path, 'backup_$stamp.srb'));
      await _encryptDbToSrb(
          DatabaseHelper.instance.dbPath, header.toBytes(), target.path);
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
      final ledgers = await db.query('books');
      final nameById = {
        for (final l in ledgers) l['id'] as String?: l['name'] as String,
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
    if (!mounted) return;
    setState(() => _busy = true);
    showToast(context, '恢复中…');
    try {
      final tmp = File(p.join(
          (await getTemporaryDirectory()).path,
          'sr_restore_${DateTime.now().microsecondsSinceEpoch}.db'));
      Map<String, dynamic> meta;
      try {
        final r = await _decryptSrbToDb(file.path, tmp.path);
        if (r.error != null) {
          throw FormatException(r.error!);
        }
        meta = jsonDecode(r.metaJson!) as Map<String, dynamic>;
        final check = await openDatabase(tmp.path, readOnly: true);
        await check.close();
      } catch (e) {
        if (tmp.existsSync()) await tmp.delete();
        rethrow;
      }
      final helper = DatabaseHelper.instance;
      await helper.database;
      await helper.close();
      final dbPath = helper.dbPath;
      for (final suffix in const ['-wal', '-shm']) {
        final f = File('$dbPath$suffix');
        if (f.existsSync()) await f.delete();
      }
      await tmp.copy(dbPath);
      if (tmp.existsSync()) await tmp.delete();
      await saveCurrentLedgerId(meta['currentBookId'] as String?);
      await helper.database;
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
    showToast(context, text);
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
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _doBackup,
                      icon: const Icon(Icons.backup_outlined),
                      label: const Text('立即备份'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).extension<AppThemeColors>()!.primary,
                      ),
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
          Expanded(
            child: _files.isEmpty
                ? const Center(
                    child: Text('暂无备份，点击上方立即备份',
                        style: textPlaceholder),
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
                            style: textBody),
                        subtitle: Text(_fileSize(file.lengthSync()),
                            style: textItemSub),
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

Future<void> _encryptDbToSrb(
    String dbPath, Uint8List header, String targetPath) {
  return Isolate.run(() {
    final key = utf8.encode(_xorKey);
    final output = File(targetPath).openSync(mode: FileMode.write);
    try {
      final encHeader = Uint8List(header.length);
      for (var i = 0; i < header.length; i++) {
        encHeader[i] = header[i] ^ key[i % key.length];
      }
      output.writeFromSync(encHeader);
      final input = File(dbPath).openSync();
      try {
        const chunk = 1 << 16;
        final buf = Uint8List(chunk);
        var keyOffset = header.length;
        int n;
        while ((n = input.readIntoSync(buf, 0, chunk)) > 0) {
          for (var i = 0; i < n; i++) {
            buf[i] = buf[i] ^ key[(keyOffset + i) % key.length];
          }
          keyOffset += n;
          output.writeFromSync(buf, 0, n);
        }
      } finally {
        input.closeSync();
      }
    } finally {
      output.closeSync();
    }
  });
}

Future<({String? metaJson, String? error})> _decryptSrbToDb(
    String srbPath, String tmpPath) {
  return Isolate.run(() {
    try {
      final key = utf8.encode(_xorKey);
      final input = File(srbPath).openSync();
      try {
        final head = input.readSync(8);
        if (head.length < 8) {
          throw const FormatException('不是有效的备份文件');
        }
        for (var i = 0; i < head.length; i++) {
          head[i] = head[i] ^ key[i % key.length];
        }
        if (String.fromCharCodes(head.sublist(0, 4)) != _magic) {
          throw const FormatException('不是有效的备份文件');
        }
        final metaLen =
            ByteData.sublistView(head, 4, 8).getUint32(0, Endian.little);
        if (metaLen < 1 || metaLen > 1 << 20) {
          throw const FormatException('备份文件已损坏');
        }
        final metaRaw = input.readSync(metaLen);
        if (metaRaw.length < metaLen) {
          throw const FormatException('备份文件已损坏');
        }
        for (var i = 0; i < metaLen; i++) {
          metaRaw[i] = metaRaw[i] ^ key[(8 + i) % key.length];
        }
        final metaJson = utf8.decode(metaRaw);
        final output = File(tmpPath).openSync(mode: FileMode.write);
        try {
          const chunk = 1 << 16;
          final buf = Uint8List(chunk);
          var keyOffset = 8 + metaLen;
          int n;
          while ((n = input.readIntoSync(buf, 0, chunk)) > 0) {
            for (var i = 0; i < n; i++) {
              buf[i] = buf[i] ^ key[(keyOffset + i) % key.length];
            }
            keyOffset += n;
            output.writeFromSync(buf, 0, n);
          }
        } finally {
          output.closeSync();
        }
        return (metaJson: metaJson, error: null);
      } finally {
        input.closeSync();
      }
    } catch (e) {
      return (metaJson: null, error: e.toString());
    }
  });
}
