import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/app_access.dart';
import '../core/session_cache.dart';
import 'cover_encoding.dart';
import 'local_workspace_store.dart';

class CoverImageService {
  CoverImageService(
    this.client, {
    String? baseUrl,
    bool requirePrivateAccess = AppAccess.enabledByDefault,
  }) : _base = baseUrl ?? _baseUrl,
       _access = AppAccess(client, requirePrivateAccess: requirePrivateAccess);

  static const bucket = 'item-covers';
  static const maxBytes = 10 * 1024 * 1024;
  static const maxUploadBytes = 2 * 1024 * 1024;
  static const _baseUrl = String.fromEnvironment('SUPABASE_URL');

  final SupabaseClient client;
  final AppAccess _access;
  final String _base;
  final _signedUrls = SessionCache<String>();
  final _signatureQueue = <String, Completer<String>>{};
  bool _signing = false;
  static final _diskCaches = <String, CacheManager>{};
  String? _cacheOwner;
  final _local = LocalWorkspaceStore();
  Future<void> _cleanupWork = Future<void>.value();

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
    final originalBytes = await image.readAsBytes();
    if (originalBytes.length > maxBytes) {
      throw const FormatException('图片不能超过 10 MB');
    }
    final bytes = await compute(compactCover, originalBytes);
    if (bytes.length > maxUploadBytes) {
      throw const FormatException('处理后的图片超过 2 MB，请裁剪或选择较小的图片');
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
    final extension =
        !identical(bytes, originalBytes) &&
            bytes.length >= 2 &&
            bytes[0] == 0xff &&
            bytes[1] == 0xd8
        ? 'jpg'
        : mimeTypes.containsKey(nameExtension)
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
    await _access.reserveCover(path);
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    // Keep a stable object URL in Postgres. It cannot be opened publicly.
    final url = Uri.parse(_base)
        .resolve('/storage/v1/object/authenticated/$bucket/$path')
        .toString();
    // Reuse the upload for immediate display; cache failures cannot fail saving.
    unawaited(
      imageCache
          .putFile(url, bytes, key: _key(path), fileExtension: extension)
          .then((_) {})
          .catchError((Object _) {}),
    );
    return url;
  }

  String? pathFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    final base = Uri.tryParse(_base);
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
      () => _enqueueSignature(path),
      ttl: const Duration(minutes: 55),
    );
  }

  Future<String> _enqueueSignature(String path) {
    final pending = _signatureQueue.putIfAbsent(path, Completer<String>.new);
    if (!_signing) {
      _signing = true;
      Timer.run(_flushSignatures);
    }
    return pending.future;
  }

  Future<void> _flushSignatures() async {
    final owner = _account;
    try {
      while (_signatureQueue.isNotEmpty) {
        final batch = Map<String, Completer<String>>.fromEntries(
          _signatureQueue.entries.take(50),
        );
        for (final path in batch.keys) {
          _signatureQueue.remove(path);
        }
        try {
          final results = await client.storage
              .from(bucket)
              .createSignedUrlsResult(batch.keys.toList(), 3600);
          if (_account != owner) throw StateError('登录会话已改变');
          final byPath = {for (final result in results) result.path: result};
          for (final entry in batch.entries) {
            final result = byPath[entry.key];
            if (result is SignedUrlSuccess) {
              entry.value.complete(result.signedUrl);
            } else {
              entry.value.completeError(StateError('封面暂时无法读取'));
            }
          }
        } catch (error, stack) {
          for (final completer in batch.values) {
            if (!completer.isCompleted) completer.completeError(error, stack);
          }
        }
      }
    } finally {
      _signing = false;
    }
  }

  Future<void> _removeNow(String? imageUrl) async {
    final path = pathFromUrl(imageUrl);
    if (path != null) {
      await client.storage.from(bucket).remove([path]);
      await _access.releaseCover(path);
      _signedUrls.invalidate(_key(path));
      await imageCache.removeFile(_key(path));
    }
  }

  Future<void> remove(String? imageUrl) {
    final owner = _account;
    final next = _cleanupWork.catchError((Object _) {}).then((_) async {
      if (imageUrl == null || pathFromUrl(imageUrl) == null) return;
      final queue = {
        ...await _local.loadImageCleanup(owner),
        imageUrl,
      }.toList();
      await _local.saveImageCleanup(owner, queue);
      if (owner != _account) throw StateError('登录会话已改变');
      await _removeNow(imageUrl);
      await _local.saveImageCleanup(
        owner,
        queue.where((url) => url != imageUrl).toList(),
      );
    });
    _cleanupWork = next;
    return next;
  }

  Future<void> retryCleanup() {
    final owner = _account;
    final next = _cleanupWork.catchError((Object _) {}).then((_) async {
      if (owner == 'signed-out') return;
      final queue = await _local.loadImageCleanup(owner);
      for (final url in queue.take(8).toList()) {
        if (owner != _account) return;
        await _removeNow(url);
        queue.remove(url);
        await _local.saveImageCleanup(owner, queue);
      }
    });
    _cleanupWork = next;
    return next;
  }

  Future<List<int>?> downloadBytes(String? imageUrl) async {
    final path = pathFromUrl(imageUrl);
    if (path == null) return null;
    return client.storage.from(bucket).download(path);
  }
}
