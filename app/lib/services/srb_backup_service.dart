import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/formatters.dart';
import 'asset_account_service.dart';
import 'database.dart';
import 'export_service.dart';
import 'image_storage_service.dart';
import 'record_service.dart';

const _xorKey = 'SimpleRecord_SRB_v1';
const _magic = 'SRB1';

/// XOR 加密/解密
void _xor(Uint8List data, List<int> key, int offset) {
  for (var i = 0; i < data.length; i++) {
    data[i] = data[i] ^ key[(offset + i) % key.length];
  }
}

/// 编码图片列表为二进制：count(4B) + [name_len(2B) + name + data_len(4B) + data]...
Future<Uint8List> _encodeImages() async {
  final images = await listImages();
  final builder = BytesBuilder();
  builder.add((ByteData(4)..setUint32(0, images.length, Endian.little)).buffer.asUint8List());
  for (final file in images) {
    final nameBytes = utf8.encode(p.basename(file.path));
    builder.add((ByteData(2)..setUint16(0, nameBytes.length, Endian.little)).buffer.asUint8List());
    builder.add(nameBytes);
    final data = file.readAsBytesSync();
    builder.add((ByteData(4)..setUint32(0, data.length, Endian.little)).buffer.asUint8List());
    builder.add(data);
  }
  return builder.toBytes();
}

/// 创建本地加密备份（.srb），返回文件路径。
Future<String> createSrbBackup({Directory? dir}) async {
  await DatabaseHelper.instance.vacuum();
  final dbFile = File(DatabaseHelper.instance.dbPath);
  final now = DateTime.now();
  final stamp = '${now.year}${pad2(now.month)}${pad2(now.day)}_${pad2(now.hour)}${pad2(now.minute)}${pad2(now.second)}';
  final targetDir = dir ?? await backupDirectory();
  final meta = utf8.encode(jsonEncode({
    'exportedAt': now.toIso8601String(),
    'currentBookId': currentLedgerId.value,
    'version': 1,
    'dbSize': dbFile.lengthSync(),
  }));
  final header = BytesBuilder()
    ..add(utf8.encode(_magic))
    ..add((ByteData(4)..setUint32(0, meta.length, Endian.little)).buffer.asUint8List())
    ..add(meta);
  final target = File(p.join(targetDir.path, 'backup_$stamp.srb'));
  await _encryptToSrb(DatabaseHelper.instance.dbPath, header.toBytes(), target.path, imagesBytes: await _encodeImages());
  return target.path;
}

/// 用 .srb 备份文件恢复全部数据。
Future<void> restoreSrbBackup(String filePath) async {
  final tmp = File(p.join((await getTemporaryDirectory()).path, 'sr_${DateTime.now().microsecondsSinceEpoch}.db'));
  Map<String, dynamic> meta;
  Uint8List? imagesBytes;
  try {
    final r = await _decryptSrb(filePath, tmp.path);
    if (r.error != null) throw FormatException(r.error!);
    meta = jsonDecode(r.metaJson!) as Map<String, dynamic>;
    imagesBytes = r.imagesBytes;
    final db = await openDatabase(tmp.path, readOnly: true);
    await db.close();
  } catch (e) {
    if (tmp.existsSync()) await tmp.delete();
    rethrow;
  }
  final helper = DatabaseHelper.instance;
  await helper.database;
  await helper.close();
  final dbPath = helper.dbPath;
  for (final s in const ['-wal', '-shm']) {
    final f = File('$dbPath$s');
    if (f.existsSync()) await f.delete();
  }
  await tmp.rename(dbPath);
  if (tmp.existsSync()) await tmp.delete();
  if (imagesBytes != null && imagesBytes.isNotEmpty) {
    await _restoreImages(imagesBytes);
  }
  await saveCurrentLedgerId(meta['currentBookId'] as String?);
  await helper.database;
  recordsVersion.value++;
  assetAccountsVersion.value++;
}

Future<void> _restoreImages(Uint8List bytes) async {
  final dir = await imagesDirectory();
  final buf = ByteData.sublistView(bytes);
  var offset = 0;
  final count = buf.getUint32(offset, Endian.little);
  offset += 4;
  for (var i = 0; i < count; i++) {
    final nameLen = buf.getUint16(offset, Endian.little);
    offset += 2;
    final name = utf8.decode(bytes.sublist(offset, offset + nameLen));
    offset += nameLen;
    final dataLen = buf.getUint32(offset, Endian.little);
    offset += 4;
    final data = bytes.sublist(offset, offset + dataLen);
    offset += dataLen;
    File(p.join(dir.path, name)).writeAsBytesSync(data, flush: true);
  }
}

Future<void> _encryptToSrb(String dbPath, Uint8List header, String targetPath, {Uint8List? imagesBytes}) {
  return Isolate.run(() {
    final key = utf8.encode(_xorKey);
    final out = File(targetPath).openSync(mode: FileMode.write);
    try {
      // header
      final enc = Uint8List.fromList(header);
      _xor(enc, key, 0);
      out.writeFromSync(enc);
      var off = header.length;
      // db
      const chunk = 1 << 16;
      final buf = Uint8List(chunk);
      _xorChunks(File(dbPath), out, key, buf, off);
      off += File(dbPath).lengthSync();
      // images
      if (imagesBytes != null && imagesBytes.isNotEmpty) {
        var w = 0;
        while (w < imagesBytes.length) {
          final n = (w + chunk < imagesBytes.length) ? chunk : imagesBytes.length - w;
          for (var i = 0; i < n; i++) {
            buf[i] = imagesBytes[w + i] ^ key[(off + i) % key.length];
          }
          off += n;
          w += n;
          out.writeFromSync(buf, 0, n);
        }
      }
    } finally {
      out.closeSync();
    }
  });
}

void _xorChunks(File inF, RandomAccessFile outF, List<int> key, Uint8List buf, int off) {
  final inp = inF.openSync();
  try {
    int n;
    while ((n = inp.readIntoSync(buf, 0, buf.length)) > 0) {
      for (var i = 0; i < n; i++) {
        buf[i] = buf[i] ^ key[(off + i) % key.length];
      }
      off += n;
      outF.writeFromSync(buf, 0, n);
    }
  } finally {
    inp.closeSync();
  }
}

Future<({String? metaJson, Uint8List? imagesBytes, String? error})> _decryptSrb(String srbPath, String tmpPath) {
  return Isolate.run(() {
    try {
      final key = utf8.encode(_xorKey);
      final input = File(srbPath).openSync();
      try {
        // header: magic(4) + meta_len(4)
        final head = input.readSync(8);
        if (head.length < 8) throw const FormatException('不是有效的备份文件');
        _xor(head, key, 0);
        final magic = String.fromCharCodes(head.sublist(0, 4));
        if (magic != _magic) throw const FormatException('不是有效的备份文件');
        final metaLen = ByteData.sublistView(head, 4, 8).getUint32(0, Endian.little);
        if (metaLen < 1 || metaLen > 1 << 20) throw const FormatException('备份文件已损坏');
        // meta
        final metaRaw = input.readSync(metaLen);
        if (metaRaw.length < metaLen) throw const FormatException('备份文件已损坏');
        _xor(metaRaw, key, 8);
        final metaJson = utf8.decode(metaRaw);
        final meta = jsonDecode(metaJson) as Map<String, dynamic>;
        final dbSize = meta['dbSize'] as int?;
        // data
        final headMetaTotal = 8 + metaLen;
        final remaining = File(srbPath).lengthSync() - headMetaTotal;
        if (remaining <= 0) throw const FormatException('备份文件已损坏');
        final allData = input.readSync(remaining);
        if (allData.length < remaining) throw const FormatException('备份文件已损坏');
        _xor(allData, key, headMetaTotal);
        // split
        final hasImages = dbSize != null && allData.length > dbSize;
        File(tmpPath).writeAsBytesSync(hasImages ? allData.sublist(0, dbSize) : allData, flush: true);
        return (metaJson: metaJson, imagesBytes: hasImages ? allData.sublist(dbSize) : null, error: null);
      } finally {
        input.closeSync();
      }
    } catch (e) {
      return (metaJson: null, imagesBytes: null, error: e.toString());
    }
  });
}
