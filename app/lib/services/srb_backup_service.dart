import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'asset_account_service.dart';
import 'database.dart';
import 'export_service.dart';
import 'record_service.dart';

const _xorKey = 'SimpleRecord_SRB_v1';
const _magic = 'SRB1';

/// 创建本地加密备份（.srb），返回文件路径。
/// [dir] 指定保存目录，默认保存到备份目录。
Future<String> createSrbBackup({Directory? dir}) async {
  await DatabaseHelper.instance.vacuum();
  final now = DateTime.now();
  final stamp =
      '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
  final targetDir = dir ?? await backupDirectory();
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
  final target = File(p.join(targetDir.path, 'backup_$stamp.srb'));
  await _encryptDbToSrb(
      DatabaseHelper.instance.dbPath, header.toBytes(), target.path);
  return target.path;
}

/// 用 .srb 备份文件恢复全部数据。
Future<void> restoreSrbBackup(String filePath) async {
  final tmp = File(p.join(
      (await getTemporaryDirectory()).path,
      'sr_restore_${DateTime.now().microsecondsSinceEpoch}.db'));
  Map<String, dynamic> meta;
  try {
    final r = await _decryptSrbToDb(filePath, tmp.path);
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

String _two(int n) => n.toString().padLeft(2, '0');
