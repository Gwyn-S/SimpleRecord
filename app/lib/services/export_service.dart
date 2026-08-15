import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/record.dart';
import '../utils/formatters.dart';
import 'database.dart';

/// 导出文件统一放在备份目录。
Future<Directory> backupDirectory() async {
  Directory dir;
  if (Platform.isAndroid) {
    dir = Directory('/storage/emulated/0/Documents/SimpleRecord/backup');
  } else {
    final docs = await getApplicationDocumentsDirectory();
    dir = Directory(p.join(docs.path, 'backup'));
  }
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 导出记录为 CSV，返回导出文件路径。
/// 不传 [records] 时导出账本全部记录；传入时导出过滤后的结果。
Future<String> exportCsv({List<Record>? records}) async {
  final db = await DatabaseHelper.instance.database;
  final ledgers = await db.query('books');
  final nameById = {
    for (final l in ledgers) l['id'] as String?: l['name'] as String,
  };
  final rows =
      records ??
      (await db.query('records', orderBy: 'date DESC, created_at DESC'))
          .map(Record.fromDbMap)
          .toList();
  final now = DateTime.now();
  final stamp =
      '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}${now.millisecond.toString().padLeft(2, '0')}';
  final dir = await backupDirectory();
  final path = p.join(dir.path, 'export_$stamp.csv');
  await Isolate.run(() {
    final buffer = StringBuffer();
    buffer.writeln('账本,日期,收支,分类,金额,备注');
    for (final r in rows) {
      final fields = [
        _csvEscape(nameById[r.ledgerId] ?? ''),
        '${r.date.year}-${_two(r.date.month)}-${_two(r.date.day)}',
        r.isExpense ? '支出' : '收入',
        _csvEscape(r.categoryName),
        formatAmount(r.amountCents),
        _csvEscape(r.remark),
      ];
      buffer.writeln(fields.join(','));
    }
    File(path).writeAsStringSync('\uFEFF$buffer', encoding: utf8);
  });
  return path;
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
