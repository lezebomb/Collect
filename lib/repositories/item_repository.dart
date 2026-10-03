import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../core/session_cache.dart';
import '../core/collection_snapshot.dart';
import '../services/cover_image_service.dart';

class ItemRepository {
  ItemRepository(this.client, this.images);

  static const bulkChunkSize = 100;

  final SupabaseClient client;
  final CoverImageService images;
  final _lists = SessionCache<List<CollectionItem>>();

  String get _userId {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('请先登录');
    return user.id;
  }

  Future<List<CollectionItem>> list({bool refresh = false}) {
    final owner = _userId;
    if (refresh) _lists.invalidate(owner);
    return _lists.get(owner, () => _fetchList(owner));
  }

  void invalidate() => _lists.invalidate(_userId);

  void _merge(String owner, List<CollectionItem> changed, Set<String> deleted) {
    final current = _lists.peek(owner);
    if (current == null) {
      _lists.invalidate(owner);
      return;
    }
    final byId = {for (final item in changed) item.id: item};
    final next = [
      for (final item in current)
        if (!deleted.contains(item.id)) byId.remove(item.id) ?? item,
      ...byId.values,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _lists.put(owner, List.unmodifiable(next));
  }

  void categoryRenamed(String oldName, String newName) {
    final owner = _userId;
    final items = _lists.peek(owner);
    if (items == null) {
      _lists.invalidate(owner);
      return;
    }
    _lists.put(
      owner,
      List.unmodifiable([
        for (final item in items)
          if (item.category == oldName)
            CollectionSnapshot.withCategory(item, newName)
          else
            item,
      ]),
    );
  }

  Future<List<CollectionItem>> _fetchList(String owner) async {
    final items = <CollectionItem>[];
    var offset = 0;
    while (true) {
      final rows = await client
          .from('items')
          .select()
          .eq('user_id', owner)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + 499);
      items.addAll(rows.map((row) => CollectionItem.fromJson(row)));
      if (rows.length < 500) break;
      offset += 500;
    }
    return List.unmodifiable(items);
  }

  Future<CollectionItem> create(CollectionItem item, XFile? cover) async {
    final userId = _userId;
    String? uploadedUrl;
    try {
      if (cover != null) {
        uploadedUrl = await images.upload(
          image: cover,
          userId: userId,
          itemId: item.id,
        );
      }
      final row = await client
          .from('items')
          .insert({
            ...item.toCreateJson(),
            'user_id': userId,
            'cover_image': uploadedUrl,
          })
          .select()
          .single();
      final saved = CollectionItem.fromJson(row);
      _merge(userId, [saved], {});
      return saved;
    } catch (_) {
      if (uploadedUrl != null) await _tryRemove(uploadedUrl);
      rethrow;
    }
  }

  /// One INSERT is transactional: all selected list records succeed or none do.
  Future<List<CollectionItem>> importList(List<CollectionItem> items) async {
    final owner = _userId;
    if (items.isEmpty) return [];
    if (items.length > 500 ||
        items.any((item) => item.userId != owner || item.coverImage != null)) {
      throw ArgumentError('每次最多导入 500 件当前账号的无封面藏品');
    }
    List<Map<String, dynamic>> rows;
    try {
      rows = await client.from('items').insert([
        for (final item in items)
          {...item.toCreateJson(), 'user_id': owner, 'cover_image': null},
      ]).select();
    } catch (_) {
      // A disconnected response does not prove that the INSERT rolled back.
      final confirmed = await client
          .from('items')
          .select()
          .eq('user_id', owner)
          .inFilter('id', items.map((item) => item.id).toList());
      if (confirmed.length != items.length) rethrow;
      rows = confirmed;
    }
    final saved = rows.map(CollectionItem.fromJson).toList();
    _merge(owner, saved, {});
    return saved;
  }

  Future<CollectionItem> update(
    CollectionItem item, {
    XFile? newCover,
    bool removeCover = false,
  }) async {
    final owner = _userId;
    final oldUrl = item.coverImage;
    String? uploadedUrl;
    try {
      if (newCover != null) {
        uploadedUrl = await images.upload(
          image: newCover,
          userId: owner,
          itemId: item.id,
        );
      }
      final nextUrl = uploadedUrl ?? (removeCover ? null : oldUrl);
      final row = await client
          .from('items')
          .update({...item.toUpdateJson(), 'cover_image': nextUrl})
          .eq('id', item.id)
          .eq('user_id', owner)
          .select()
          .single();
      if (oldUrl != null && oldUrl != nextUrl) await _tryRemove(oldUrl);
      final saved = CollectionItem.fromJson(row);
      _merge(owner, [saved], {});
      return saved;
    } catch (_) {
      if (uploadedUrl != null) await _tryRemove(uploadedUrl);
      rethrow;
    }
  }

  Future<void> delete(CollectionItem item) async {
    final owner = _userId;
    await client.from('items').delete().eq('id', item.id).eq('user_id', owner);
    _merge(owner, [], {item.id});
    if (item.coverImage != null) await _tryRemove(item.coverImage!);
  }

  List<String> _bulkIds(List<String> ids) {
    final unique = ids.toSet().toList();
    if (unique.length > bulkChunkSize || unique.any((id) => id.isEmpty)) {
      throw ArgumentError('每次最多处理 $bulkChunkSize 件收藏');
    }
    return unique;
  }

  /// Update only the category, leaving the other collection fields intact.
  Future<List<CollectionItem>> changeCategory(
    List<String> ids,
    String category,
  ) async {
    final targets = _bulkIds(ids);
    if (targets.isEmpty) return [];
    final name = category.trim();
    if (name.isEmpty || name.length > 60) throw ArgumentError('分类名称无效');
    final owner = _userId;
    final rows = await client
        .from('items')
        .update({
          'category': name,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', owner)
        .inFilter('id', targets)
        .select();
    final saved = rows.map(CollectionItem.fromJson).toList();
    _merge(owner, saved, {});
    return saved;
  }

  /// Return only confirmed deletions; clean up their current cover objects.
  Future<Set<String>> deleteMany(List<String> ids) async {
    final targets = _bulkIds(ids);
    if (targets.isEmpty) return {};
    final owner = _userId;
    final rows = await client
        .from('items')
        .delete()
        .eq('user_id', owner)
        .inFilter('id', targets)
        .select('id,cover_image');
    final deleted = rows.map((row) => row['id'] as String).toSet();
    _merge(owner, [], deleted);
    final covers = rows
        .map((row) => row['cover_image'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    // Keep storage cleanup concurrency bounded for larger selections.
    for (var i = 0; i < covers.length; i += 8) {
      await Future.wait(covers.skip(i).take(8).map(_tryRemove));
    }
    return deleted;
  }

  Future<void> _tryRemove(String url) async {
    try {
      await images.remove(url);
    } catch (error) {
      // A failed cleanup must not turn a successful database write into a loss.
      debugPrint('Could not remove cover object: $error');
    }
  }
}
