import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/session_cache.dart';
import '../models/user_preferences.dart';
import '../services/cover_image_service.dart';

class PreferencesRepository {
  PreferencesRepository(this.client, this.images);

  final SupabaseClient client;
  final CoverImageService images;
  final _preferences = SessionCache<UserPreferences>();
  final _categories = SessionCache<List<String>>();

  String get userId => client.auth.currentUser!.id;

  Future<UserPreferences> load({bool refresh = false}) {
    final owner = userId;
    if (refresh) _preferences.invalidate(owner);
    return _preferences.get(owner, () => _load(owner));
  }

  Future<UserPreferences> _load(String owner) async {
    final row = await client
        .from('user_preferences')
        .select()
        .eq('user_id', owner)
        .maybeSingle();
    return row == null
        ? const UserPreferences()
        : UserPreferences.fromJson(row);
  }

  Future<UserPreferences> save(UserPreferences prefs) async {
    final owner = userId;
    final row = await client
        .from('user_preferences')
        .upsert({
          'user_id': owner,
          ...prefs.toJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();
    final saved = UserPreferences.fromJson(row);
    _preferences.put(owner, saved);
    return saved;
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
    late final UserPreferences next;
    try {
      next = await save(
        current.copyWith(wallpaperUrl: uploaded, clearWallpaper: file == null),
      );
    } catch (_) {
      if (uploaded != null) {
        try {
          await images.remove(uploaded);
        } catch (error) {
          debugPrint('Could not remove unused wallpaper: $error');
        }
      }
      rethrow;
    }
    if (old != null && old != next.wallpaperUrl) {
      try {
        await images.remove(old);
      } catch (error) {
        debugPrint('Could not remove previous wallpaper: $error');
      }
    }
    return next;
  }

  Future<List<String>> categories({
    List<String> itemCategories = const [],
    bool refresh = false,
  }) async {
    final owner = userId;
    if (refresh) _categories.invalidate(owner);
    final definitions = await _categories.get(owner, () async {
      final rows = await client
          .from('user_categories')
          .select('name')
          .eq('user_id', owner)
          .order('created_at', ascending: true)
          .order('name', ascending: true);
      return List<String>.unmodifiable(
        rows.map((row) => row['name'] as String),
      );
    });
    // Retired categories only appear when editing an item that already uses one.
    return {...definitions, ...itemCategories}.toList();
  }

  Future<void> addCategory(String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > 60) {
      throw const FormatException('分类名称需为 1–60 个字');
    }
    final owner = userId;
    final loaded = await categories();
    final before = _categories.peek(owner) ?? loaded;
    if (before.contains(value)) return;
    _categories.put(owner, List.unmodifiable([...before, value]));
    try {
      await client.from('user_categories').insert({
        'user_id': owner,
        'name': value,
      });
    } catch (_) {
      final current = _categories.peek(owner) ?? before;
      _categories.put(
        owner,
        List.unmodifiable(current.where((v) => v != value)),
      );
      rethrow;
    }
  }

  Future<void> removeCategory(String name) async {
    final owner = userId;
    final loaded = await categories();
    final before = _categories.peek(owner) ?? loaded;
    _categories.put(owner, List.unmodifiable(before.where((v) => v != name)));
    try {
      await client
          .from('user_categories')
          .delete()
          .eq('user_id', owner)
          .eq('name', name);
    } catch (_) {
      final current = _categories.peek(owner) ?? [];
      _categories.put(
        owner,
        List.unmodifiable({...current, if (before.contains(name)) name}),
      );
      rethrow;
    }
  }
}
