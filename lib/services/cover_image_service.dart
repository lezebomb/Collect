import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/session_cache.dart';

class CoverImageService {
  CoverImageService(this.client);

  static const bucket = 'item-covers';
  static const maxBytes = 10 * 1024 * 1024;
  static const _baseUrl = String.fromEnvironment('SUPABASE_URL');

  final SupabaseClient client;
  final _signedUrls = SessionCache<String>();
  static final _diskCaches = <String, CacheManager>{};
  String? _cacheOwner;

  String get _account => client.auth.currentUser?.id ?? 'signed-out';
  String _key(String path) => '$_account:$path';

  CacheManager get imageCache {
    final owner = _cacheOwner = _account;
    return _diskCaches.putIfAbsent(
      owner,
      () => CacheManager(
        Config(
          'collect-covers-$owner',
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 250,
        ),
      ),
    );
  }

  String? cachedSignedUrl(String? url) {
    final path = pathFromUrl(url);
    return path == null ? null : _signedUrls.peek(_key(path));
  }

  bool hasFreshSignedUrl(String? url) {
    final path = pathFromUrl(url);
    return path == null || _signedUrls.contains(_key(path));
  }

  String cacheKey(String url) => _key(pathFromUrl(url) ?? url);

  Future<File?> cachedCover(String? url) async {
    if (pathFromUrl(url) == null || client.auth.currentUser == null) {
      return null;
    }
    final entry = await imageCache.getFileFromCache(cacheKey(url!));
    // Object paths contain a new UUID for every replacement, so an existing
    // account-scoped file is safe to display without renewing its signed URL.
    return entry != null && await entry.file.exists() ? entry.file : null;
  }

  Future<void> clearSession() async {
    _signedUrls.clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final cache = _diskCaches.remove(_cacheOwner);
    if (cache != null) {
      await cache.emptyCache();
      await cache.dispose();
    }
  }

  Future<String> upload({
    required XFile image,
    required String userId,
    required String itemId,
  }) async {
    final bytes = await image.readAsBytes();
    if (bytes.length > maxBytes) {
      throw const FormatException('图片不能超过 10 MB');
    }
    final nameExtension = image.name.split('.').last.toLowerCase();
    const mimeTypes = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'heic': 'image/heic',
      'heif': 'image/heif',
    };
    final extension = mimeTypes.containsKey(nameExtension)
        ? nameExtension
        : switch (image.mimeType?.toLowerCase()) {
            'image/jpeg' => 'jpg',
            'image/png' => 'png',
            'image/webp' => 'webp',
            'image/heic' => 'heic',
            'image/heif' => 'heif',
            _ => '',
          };
    final contentType = mimeTypes[extension];
    if (contentType == null) {
      throw const FormatException('请选择 JPG、PNG、WebP 或 HEIC 图片');
    }
    final path = '$userId/$itemId/${const Uuid().v4()}.$extension';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    // Keep a stable object URL in Postgres. It cannot be opened publicly.
    return Uri.parse(_baseUrl)
        .resolve('/storage/v1/object/authenticated/$bucket/$path')
        .toString();
  }

  String? pathFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    final base = Uri.tryParse(_baseUrl);
    if (uri == null || base == null || uri.origin != base.origin) return null;
    const prefix = ['storage', 'v1', 'object', 'authenticated', bucket];
    final segments = uri.pathSegments;
    if (segments.length <= prefix.length) return null;
    for (var index = 0; index < prefix.length; index++) {
      if (segments[index] != prefix[index]) return null;
    }
    return segments.skip(prefix.length).join('/');
  }

  Future<String?> signedUrl(String? imageUrl) async {
    final path = pathFromUrl(imageUrl);
    if (path == null) return null;
    return _signedUrls.get(
      _key(path),
      () => client.storage.from(bucket).createSignedUrl(path, 3600),
      ttl: const Duration(minutes: 55),
    );
  }

  Future<void> remove(String? imageUrl) async {
    final path = pathFromUrl(imageUrl);
    if (path != null) {
      await client.storage.from(bucket).remove([path]);
      _signedUrls.invalidate(_key(path));
      await imageCache.removeFile(_key(path));
    }
  }

  Future<List<int>?> downloadBytes(String? imageUrl) async {
    final path = pathFromUrl(imageUrl);
    if (path == null) return null;
    return client.storage.from(bucket).download(path);
  }
}
