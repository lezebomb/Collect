import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_preferences.dart';
import '../repositories/item_repository.dart';
import '../repositories/preferences_repository.dart';
import 'cover_image_service.dart';

class BackupService {
  BackupService(this.client, this.items, this.preferences, this.images);

  final SupabaseClient client;
  final ItemRepository items;
  final PreferencesRepository preferences;
  final CoverImageService images;

  Future<Uri?> export() async {
    final records = await items.list();
    final categories = await preferences.categories();
    final prefs = await preferences.load();
    final payloadItems = <Map<String, dynamic>>[];
    for (final item in records) {
      final bytes = await images.downloadBytes(item.coverImage);
      payloadItems.add({
        ...item.toCreateJson(),
        'cover_base64': bytes == null ? null : base64Encode(bytes),
        'cover_extension': _extension(item.coverImage),
      });
    }
    final wallpaper = await images.downloadBytes(prefs.wallpaperUrl);
    final payload = {
      'format': 'collect-backup',
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'items': payloadItems,
      'categories': categories,
      'preferences': prefs.toJson(),
      'wallpaper_base64': wallpaper == null ? null : base64Encode(wallpaper),
      'wallpaper_extension': _extension(prefs.wallpaperUrl),
    };
    final data = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final today = DateTime.now();
    return FilePicker.saveFile(
      fileName:
          'Collect-${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}.json',
      bytes: data,
      mimeType: 'application/json',
    );
  }

  Future<int?> import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (root['format'] != 'collect-backup' || root['version'] != 1) {
      throw const FormatException('不是受支持的 Collect 备份文件');
    }
    final rawItems = root['items'] as List<dynamic>;
    final userId = client.auth.currentUser!.id;
    var count = 0;
    for (final raw in rawItems) {
      final data = Map<String, dynamic>.from(raw as Map);
      final encoded = data.remove('cover_base64') as String?;
      final extension = (data.remove('cover_extension') as String?) ?? 'jpg';
      data['user_id'] = userId;
      if (encoded != null) {
        final image = XFile.fromData(
          base64Decode(encoded),
          name: 'restore.$extension',
          mimeType: _mimeForExtension(extension),
        );
        data['cover_image'] = await images.upload(
          image: image,
          userId: userId,
          itemId: data['id'] as String,
        );
      } else {
        data['cover_image'] = null;
      }
      await client.from('items').upsert(data);
      count++;
    }
    for (final raw in (root['categories'] as List<dynamic>? ?? [])) {
      await preferences.addCategory(raw as String);
    }
    final rawPrefs = root['preferences'] as Map<String, dynamic>?;
    if (rawPrefs != null) {
      var prefs = UserPreferences.fromJson(rawPrefs);
      final encoded = root['wallpaper_base64'] as String?;
      if (encoded != null) {
        final extension = (root['wallpaper_extension'] as String?) ?? 'jpg';
        final image = XFile.fromData(
          base64Decode(encoded),
          name: 'wallpaper.$extension',
          mimeType: _mimeForExtension(extension),
        );
        final url = await images.upload(
          image: image,
          userId: userId,
          itemId: 'wallpaper',
        );
        prefs = prefs.copyWith(wallpaperUrl: url);
      } else {
        prefs = prefs.copyWith(clearWallpaper: true);
      }
      await preferences.save(prefs);
    }
    return count;
  }

  String _extension(String? url) {
    final path = images.pathFromUrl(url);
    final ext = path?.split('.').last.toLowerCase();
    return {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'}.contains(ext)
        ? ext!
        : 'jpg';
  }

  String _mimeForExtension(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    _ => 'image/jpeg',
  };
}
