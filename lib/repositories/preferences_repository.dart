import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/collection_options.dart';
import '../models/user_preferences.dart';
import '../services/cover_image_service.dart';

class PreferencesRepository {
  PreferencesRepository(this.client, this.images);

  final SupabaseClient client;
  final CoverImageService images;

  String get userId => client.auth.currentUser!.id;

  Future<UserPreferences> load() async {
    final row = await client
        .from('user_preferences')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null
        ? const UserPreferences()
        : UserPreferences.fromJson(row);
  }

  Future<UserPreferences> save(UserPreferences prefs) async {
    final row = await client
        .from('user_preferences')
        .upsert({
          'user_id': userId,
          ...prefs.toJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();
    return UserPreferences.fromJson(row);
  }

  Future<UserPreferences> setWallpaper(
    UserPreferences current,
    XFile? file,
  ) async {
    final old = current.wallpaperUrl;
    String? uploaded;
    if (file != null) {
      uploaded = await images.upload(
        image: file,
        userId: userId,
        itemId: 'wallpaper',
      );
    }
    try {
      final next = await save(
        current.copyWith(wallpaperUrl: uploaded, clearWallpaper: file == null),
      );
      if (old != null && old != next.wallpaperUrl) await images.remove(old);
      return next;
    } catch (_) {
      if (uploaded != null) await images.remove(uploaded);
      rethrow;
    }
  }

  Future<List<String>> categories({
    List<String> itemCategories = const [],
  }) async {
    final rows = await client
        .from('user_categories')
        .select('name')
        .eq('user_id', userId);
    return {
      ...collectionCategories,
      ...itemCategories,
      ...rows.map((row) => row['name'] as String),
    }.toList();
  }

  Future<void> addCategory(String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > 60) {
      throw const FormatException('分类名称需为 1–60 个字');
    }
    if (collectionCategories.contains(value)) return;
    if ((await categories()).contains(value)) return;
    await client.from('user_categories').insert({
      'user_id': userId,
      'name': value,
    });
  }

  Future<void> removeCategory(String name) async {
    if (collectionCategories.contains(name)) return;
    await client
        .from('user_categories')
        .delete()
        .eq('user_id', userId)
        .eq('name', name);
  }
}
