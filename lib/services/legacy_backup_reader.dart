import 'dart:convert';
import 'dart:typed_data';

import 'backup_archive_codec.dart';

// Import-only bridge for backups created before ZIP export was introduced.
class LegacyBackupReader {
  BackupPackage decode(Uint8List bytes) {
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (root['format'] != 'collect-backup' || root['version'] != 1) {
      throw const FormatException('不是受支持的 Collect 备份文件');
    }
    final files = <String, Uint8List>{};
    final items = <Map<String, dynamic>>[];
    for (final raw in (root['items'] as List<dynamic>? ?? [])) {
      final data = Map<String, dynamic>.from(raw as Map);
      final encoded = data.remove('cover_base64') as String?;
      final extension = _extension(data.remove('cover_extension'));
      final id = data['id'] as String;
      String? path;
      if (encoded != null) {
        path = 'images/item_$id.$extension';
        files[path] = _decodeImage(encoded);
      }
      data['cover_image'] = null;
      data['cover_file'] = path;
      items.add(data);
    }
    final prefs = Map<String, dynamic>.from(root['preferences'] as Map? ?? {});
    final encodedWallpaper = root['wallpaper_base64'] as String?;
    String? wallpaperFile;
    if (encodedWallpaper != null) {
      wallpaperFile =
          'wallpaper/wallpaper.${_extension(root['wallpaper_extension'])}';
      files[wallpaperFile] = _decodeImage(encodedWallpaper);
    }
    prefs['wallpaper_url'] = null;
    return BackupPackage({
      'format': 'collect-backup',
      'version': 2,
      'source_user_id': items.isEmpty ? null : items.first['user_id'],
      'items': items,
      'categories': root['categories'] ?? [],
      'preferences': prefs,
      'wallpaper_file': wallpaperFile,
    }, files);
  }

  Uint8List _decodeImage(String encoded) {
    final bytes = base64Decode(encoded);
    if (bytes.length > BackupArchiveCodec.maxImageBytes) {
      throw const FormatException('备份图片不能超过 10 MB');
    }
    return bytes;
  }

  String _extension(dynamic value) {
    const allowed = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};
    return value is String && allowed.contains(value.toLowerCase())
        ? value.toLowerCase()
        : 'jpg';
  }
}
