import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class BackupPackage {
  const BackupPackage(this.manifest, this.files);
  final Map<String, dynamic> manifest;
  final Map<String, Uint8List> files;
}

class BackupArchiveCodec {
  static const maxArchiveBytes = 250 * 1024 * 1024;
  static const maxManifestBytes = 5 * 1024 * 1024;
  static const maxImageBytes = 10 * 1024 * 1024;

  Uint8List encode(BackupPackage package) {
    final archive = Archive();
    final manifestBytes = utf8.encode(jsonEncode(package.manifest));
    if (manifestBytes.length > maxManifestBytes) {
      throw const FormatException('备份清单过大');
    }
    archive.addFile(ArchiveFile.bytes('backup.json', manifestBytes));
    var total = 0;
    for (final entry in package.files.entries) {
      _validatePath(entry.key);
      if (entry.value.length > maxImageBytes) {
        throw const FormatException('备份图片不能超过 10 MB');
      }
      total += entry.value.length;
      if (total > maxArchiveBytes) {
        throw const FormatException('备份内容过大');
      }
      archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
    }
    final encoded = Uint8List.fromList(ZipEncoder().encode(archive));
    if (encoded.length > maxArchiveBytes) {
      throw const FormatException('备份文件过大');
    }
    return encoded;
  }

  BackupPackage decode(Uint8List bytes) {
    if (bytes.length > maxArchiveBytes) throw const FormatException('备份文件过大');
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Uint8List>{};
    Map<String, dynamic>? manifest;
    var total = 0;
    for (final entry in archive) {
      if (!entry.isFile || entry.isSymbolicLink) {
        throw const FormatException('备份包含不支持的文件');
      }
      if (entry.name == 'backup.json') {
        if (manifest != null || entry.size > maxManifestBytes) {
          throw const FormatException('备份清单无效');
        }
        final data = entry.readBytes();
        if (data == null || data.length > maxManifestBytes) {
          throw const FormatException('备份清单无效');
        }
        manifest = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      } else {
        _validatePath(entry.name);
        if (files.containsKey(entry.name) || entry.size > maxImageBytes) {
          throw const FormatException('备份图片无效');
        }
        total += entry.size;
        if (total > maxArchiveBytes) throw const FormatException('备份内容过大');
        final data = entry.readBytes();
        if (data == null || data.length > maxImageBytes) {
          throw const FormatException('备份图片无效');
        }
        files[entry.name] = data;
      }
    }
    if (manifest?['format'] != 'collect-backup' || manifest?['version'] != 2) {
      throw const FormatException('不是受支持的 Collect ZIP 备份');
    }
    return BackupPackage(manifest!, files);
  }

  void _validatePath(String path) {
    if (!RegExp(
      r'^(images|wallpaper)/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp|heic|heif)$',
    ).hasMatch(path)) {
      throw const FormatException('备份中的图片路径无效');
    }
  }
}
