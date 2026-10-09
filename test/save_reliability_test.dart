import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shou_cang_gui/models/collection_item.dart';
import 'package:shou_cang_gui/repositories/item_repository.dart';
import 'package:shou_cang_gui/services/cover_image_service.dart';

class _Auth implements GoTrueClient {
  @override
  User get currentUser => const User(
    id: 'owner',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected auth');
}

class _Client implements SupabaseClient {
  _Client(this.delegate);
  final SupabaseClient delegate;
  @override
  GoTrueClient get auth => _Auth();
  @override
  SupabaseQueryBuilder from(String table) => delegate.from(table);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API');
}

class _Images extends CoverImageService {
  _Images(super.client);
  final cleanup = Completer<void>();
  final removed = <String>[];
  @override
  Future<String> upload({
    required XFile image,
    required String userId,
    required String itemId,
  }) async => 'new-cover';
  @override
  Future<void> remove(String? url) async {
    if (url != null) removed.add(url);
    await cleanup.future;
  }
}

final item = CollectionItem(
  id: 'id',
  userId: 'owner',
  name: 'Game',
  category: '游戏',
  coverImage: 'old-cover',
  createdAt: DateTime(2026),
);

void main() {
  test(
    'Confirmed save returns without waiting for slow cover cleanup',
    () async {
      final client = _Client(
        SupabaseClient(
          'https://test.supabase.co',
          'test-key',
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode([
                {...item.toCreateJson(), 'cover_image': 'new-cover'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            ),
          ),
        ),
      );
      final images = _Images(client);
      final saved = await ItemRepository(client, images)
          .update(
            item,
            newCover: XFile.fromData(Uint8List.fromList([1]), name: 'x.jpg'),
          )
          .timeout(const Duration(seconds: 1));
      expect(saved.coverImage, 'new-cover');
      expect(images.removed, ['old-cover']);
      images.cleanup.complete();
      await client.delegate.dispose();
    },
  );
  test(
    'Response lost after commit reconciles the record and retains new cover',
    () async {
      final client = _Client(
        SupabaseClient(
          'https://test.supabase.co',
          'test-key',
          httpClient: MockClient((request) async {
            if (request.method == 'PATCH') {
              throw http.ClientException('Response lost');
            }
            return http.Response(
              jsonEncode([
                {...item.toCreateJson(), 'cover_image': 'new-cover'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        ),
      );
      final images = _Images(client);
      final saved = await ItemRepository(client, images).update(
        item,
        newCover: XFile.fromData(Uint8List.fromList([1]), name: 'x.jpg'),
      );
      expect(saved.coverImage, 'new-cover');
      expect(images.removed, ['old-cover']);
      images.cleanup.complete();
      await client.delegate.dispose();
    },
  );
  test(
    'Uncertain writes never delete a potentially committed uploaded cover',
    () async {
      final client = _Client(
        SupabaseClient(
          'https://test.supabase.co',
          'test-key',
          httpClient: MockClient((request) async {
            throw http.ClientException('Network unavailable');
          }),
        ),
      );
      final images = _Images(client);
      await expectLater(
        ItemRepository(client, images).update(
          item,
          newCover: XFile.fromData(Uint8List.fromList([1]), name: 'x.jpg'),
        ),
        throwsA(isA<http.ClientException>()),
      );
      expect(images.removed, isEmpty);
      images.cleanup.complete();
      await client.delegate.dispose();
    },
  );
}
