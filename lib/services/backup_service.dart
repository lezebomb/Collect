import 'package:file_picker/file_picker.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/user_preferences.dart';
import '../repositories/item_repository.dart';
import '../repositories/preferences_repository.dart';
import 'backup_archive_codec.dart';
import 'cover_image_service.dart';
import 'legacy_backup_reader.dart';

class BackupService {
  BackupService(this.client, this.items, this.preferences, this.images);

  final SupabaseClient client;
  final ItemRepository items;
  final PreferencesRepository preferences;
  final CoverImageService images;
  final BackupArchiveCodec _codec = BackupArchiveCodec();

  Future<Uri?> export() async {
    final records = await items.list(refresh: true);
    final categories = await preferences.categories();
    final prefs = await preferences.load();
    final files = <String, Uint8List>{};
    final payloadItems = <Map<String, dynamic>>[];
    for (final item in records) {
      String? coverFile;
      if (item.coverImage != null) {
        coverFile = 'images/item_${item.id}.${_extension(item.coverImage)}';
        files[coverFile] = await _downloadRequired(item.coverImage!);
      }
      payloadItems.add({
        ...item.toCreateJson(),
        'cover_image': null,
        'cover_file': coverFile,
      });
    }
    String? wallpaperFile;
    if (prefs.wallpaperUrl != null) {
      wallpaperFile = 'wallpaper/wallpaper.${_extension(prefs.wallpaperUrl)}';
      files[wallpaperFile] = await _downloadRequired(prefs.wallpaperUrl!);
    }
    final manifest = <String, dynamic>{
      'format': 'collect-backup',
      'version': 2,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'source_user_id': client.auth.currentUser!.id,
      'items': payloadItems,
      'categories': categories,
      'preferences': {...prefs.toJson(), 'wallpaper_url': null},
      'wallpaper_file': wallpaperFile,
    };
    final data = _codec.encode(BackupPackage(manifest, files));
    final today = DateTime.now();
    return FilePicker.saveFile(
      fileName:
          'Collect-${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}.zip',
      bytes: data,
      mimeType: 'application/zip',
    );
  }

  Future<int?> import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
    );
    if (file == null) return null;
    final bytes = Uint8List.fromList(await file.readAsBytes());
    final package = bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b
        ? _codec.decode(bytes)
        : LegacyBackupReader().decode(bytes);
    final root = package.manifest;
    final rawItems = root['items'];
    if (rawItems is! List) throw const FormatException('备份中的收藏数据无效');
    final rawPrefs = root['preferences'];
    if (rawPrefs is! Map) throw const FormatException('备份中的设置无效');
    final rawCategories = root['categories'];
    if (rawCategories is! List ||
        rawCategories.any((value) => value is! String)) {
      throw const FormatException('备份中的分类无效');
    }
    final payloadItems = rawItems
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
    for (final data in payloadItems) {
      _requiredFile(package, data['cover_file'], 'images/');
    }
    _requiredFile(package, root['wallpaper_file'], 'wallpaper/');

    final userId = client.auth.currentUser!.id;
    final sameAccount = root['source_user_id'] == userId;
    var count = 0;
    // Import writes rows directly, including partial imports that fail later.
    items.invalidate();
    for (final data in payloadItems) {
      final originalId = data['id'];
      if (originalId is! String) throw const FormatException('备份中的物品 ID 无效');
      final itemId = sameAccount ? originalId : const Uuid().v4();
      final old = sameAccount
          ? await client
                .from('items')
                .select('cover_image')
                .eq('id', itemId)
                .eq('user_id', userId)
                .maybeSingle()
          : null;
      final oldCover = old?['cover_image'] as String?;
      final filePath = data.remove('cover_file') as String?;
      data.remove('status');
      data.remove('rating');
      data['id'] = itemId;
      data['user_id'] = userId;
      data['cover_image'] = null;
      String? uploaded;
      try {
        if (filePath != null) {
          uploaded = await images.upload(
            image: _imageFile(package.files[filePath]!, filePath),
            userId: userId,
            itemId: itemId,
          );
          data['cover_image'] = uploaded;
        }
        await client.from('items').upsert(data);
      } catch (error) {
        if (uploaded != null && error is PostgrestException) {
          unawaited(_tryRemove(uploaded));
        }
        rethrow;
      }
      if (oldCover != null && oldCover != uploaded) {
        unawaited(_tryRemove(oldCover));
      }
      count++;
    }
    await preferences.addCategories(rawCategories.cast<String>());
    var prefs = UserPreferences.fromJson(Map<String, dynamic>.from(rawPrefs));
    final wallpaperFile = root['wallpaper_file'] as String?;
    String? uploadedWallpaper;
    if (wallpaperFile != null) {
      uploadedWallpaper = await images.upload(
        image: _imageFile(package.files[wallpaperFile]!, wallpaperFile),
        userId: userId,
        itemId: 'wallpaper',
      );
      prefs = prefs.copyWith(wallpaperUrl: uploadedWallpaper);
    } else {
      prefs = prefs.copyWith(clearWallpaper: true);
    }
    final oldPrefs = await preferences.load();
    try {
      await preferences.save(prefs);
    } catch (error) {
      if (uploadedWallpaper != null && error is PostgrestException) {
        unawaited(_tryRemove(uploadedWallpaper));
      }
      rethrow;
    }
    if (oldPrefs.wallpaperUrl != null &&
        oldPrefs.wallpaperUrl != prefs.wallpaperUrl) {
      unawaited(_tryRemove(oldPrefs.wallpaperUrl));
    }
    return count;
  }

  Future<Uint8List> _downloadRequired(String url) async {
    final bytes = await images.downloadBytes(url);
    if (bytes == null) throw const FormatException('有图片无法读取，备份已取消');
    return Uint8List.fromList(bytes);
  }

  Future<void> _tryRemove(String? url) async {
    try {
      await images.remove(url);
    } catch (error) {
      debugPrint('Could not remove an old backup image: $error');
    }
  }

  void _requiredFile(BackupPackage package, dynamic path, String prefix) {
    if (path == null) return;
    if (path is! String ||
        !path.startsWith(prefix) ||
        !package.files.containsKey(path)) {
      throw const FormatException('备份缺少图片文件');
    }
  }

  XFile _imageFile(Uint8List bytes, String path) {
    final extension = path.split('.').last.toLowerCase();
    return XFile.fromData(
      bytes,
      name: 'restore.$extension',
      mimeType: switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        _ => 'image/jpeg',
      },
    );
  }

  String _extension(String? url) {
    final path = images.pathFromUrl(url);
    final ext = path?.split('.').last.toLowerCase();
    return {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'}.contains(ext)
        ? ext!
        : 'jpg';
  }
}
