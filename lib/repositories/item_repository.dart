import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection_item.dart';
import '../services/cover_image_service.dart';

class ItemRepository {
  ItemRepository(this.client, this.images);

  final SupabaseClient client;
  final CoverImageService images;

  String get _userId {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('请先登录');
    return user.id;
  }

  Future<List<CollectionItem>> list() async {
    final items = <CollectionItem>[];
    var offset = 0;
    while (true) {
      final rows = await client
          .from('items')
          .select()
          .eq('user_id', _userId)
          .order('created_at', ascending: false)
          .range(offset, offset + 499);
      items.addAll(rows.map((row) => CollectionItem.fromJson(row)));
      if (rows.length < 500) break;
      offset += 500;
    }
    return items;
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
      return CollectionItem.fromJson(row);
    } catch (_) {
      if (uploadedUrl != null) await _tryRemove(uploadedUrl);
      rethrow;
    }
  }

  Future<CollectionItem> update(
    CollectionItem item, {
    XFile? newCover,
    bool removeCover = false,
  }) async {
    final oldUrl = item.coverImage;
    String? uploadedUrl;
    try {
      if (newCover != null) {
        uploadedUrl = await images.upload(
          image: newCover,
          userId: _userId,
          itemId: item.id,
        );
      }
      final nextUrl = uploadedUrl ?? (removeCover ? null : oldUrl);
      final row = await client
          .from('items')
          .update({...item.toUpdateJson(), 'cover_image': nextUrl})
          .eq('id', item.id)
          .eq('user_id', _userId)
          .select()
          .single();
      if (oldUrl != null && oldUrl != nextUrl) await _tryRemove(oldUrl);
      return CollectionItem.fromJson(row);
    } catch (_) {
      if (uploadedUrl != null) await _tryRemove(uploadedUrl);
      rethrow;
    }
  }

  Future<void> delete(CollectionItem item) async {
    await client
        .from('items')
        .delete()
        .eq('id', item.id)
        .eq('user_id', _userId);
    if (item.coverImage != null) await _tryRemove(item.coverImage!);
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
