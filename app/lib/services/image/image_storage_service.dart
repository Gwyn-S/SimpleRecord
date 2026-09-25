import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../utils/app_paths.dart';

/// 图片统一存储目录（<应用基础目录>/images/）。
Future<Directory> imagesDirectory() async {
  final base = await appBaseDirectory();
  final dir = Directory(p.join(base.path, 'images'));
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

/// 列出统一存储目录中的所有图片文件。
Future<List<File>> listImages() async {
  final dir = await imagesDirectory();
  return dir
      .listSync()
      .whereType<File>()
      .where(
        (f) => _imageExtensions.contains(p.extension(f.path).toLowerCase()),
      )
      .toList();
}

const _imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'];

/// 将图片复制到统一存储目录，返回新路径。
/// 文件名用 UUID 重命名，避免冲突。
Future<String> saveImage(String sourcePath) async {
  final dir = await imagesDirectory();
  final ext = p.extension(sourcePath).toLowerCase();
  final newName = '${const Uuid().v4()}$ext';
  final dest = p.join(dir.path, newName);
  await File(sourcePath).copy(dest);
  return dest;
}

/// 删除统一存储目录中的图片文件。
Future<void> deleteImage(String path) async {
  final f = File(path);
  if (await f.exists()) await f.delete();
}
