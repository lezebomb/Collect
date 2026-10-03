import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shou_cang_gui/repositories/item_repository.dart';
import 'package:shou_cang_gui/repositories/preferences_repository.dart';
import 'package:shou_cang_gui/services/item_list_import.dart';
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
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    get = false,
  }) => delegate.rpc<T>(fn, params: params, get: get);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API');
}

class _Images extends CoverImageService {
  _Images(super.client);
  final removed = <String>[];
  @override
  Future<void> remove(String? url) async {
    if (url == null) return;
    removed.add(url);
    if (url == 'failed-cover') throw StateError('storage unavailable');
  }
}

void main() {
  test('Interrupted import response verifies scoped IDs and recognizes committed data without duplicate insert', () async {
    final items = ItemListImport.parse({
      'template': ItemListImport.template,
    }, owner: 'owner');
    final calls = <http.Request>[];
    final client = _Client(
      SupabaseClient(
        'https://test.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          calls.add(request);
          if (request.method == 'POST') {
            throw http.ClientException('connection interrupted');
          }
          expect(request.url.queryParameters['user_id'], 'eq.owner');
          expect(request.url.queryParameters['id'], contains(items.first.id));
          return http.Response(
            jsonEncode(items.map((item) => item.toCreateJson()).toList()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );
        }),
      ),
    );
    final repo = ItemRepository(client, _Images(client));
    final saved = await repo.importList(items);
    expect(saved.length, 2);
    expect(calls.map((request) => request.method).toList(), ['POST', 'GET']);
    await client.delegate.dispose();
  });
  test('Concurrent list calls share HTTP; importing merges cache, refresh requests fresh rows', () async {
    var gets = 0;
    var posts = 0;
    final gate = Completer<void>();
    final client = _Client(
      SupabaseClient(
        'https://test.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            gets++;
            await gate.future;
          } else {
            posts++;
          }
          expect(
            request.method == 'POST' ||
                request.url.queryParameters['user_id'] == 'eq.owner',
            isTrue,
          );
          return http.Response(
            request.method == 'GET' ? '[]' : request.body,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );
        }),
      ),
    );
    final repo = ItemRepository(client, _Images(client));
    final first = repo.list();
    final second = repo.list();
    await Future<void>.delayed(Duration.zero);
    expect(gets, 1);
    gate.complete();
    await Future.wait([first, second]);
    await repo.list();
    expect(gets, 1);
    final imported = ItemListImport.parse({
      'template.json': ItemListImport.template,
    }, owner: 'owner');
    await repo.importList(imported);
    expect((await repo.list()).length, 2);
    expect(posts, 1);
    expect(gets, 1);
    repo.categoryRenamed('游戏', 'Games');
    final game = (await repo.list()).singleWhere(
      (item) => item.category == 'Games',
    );
    expect(game.gamePlatform, 'PC');
    expect(game.gameEdition, '数字版');
    await repo.list(refresh: true);
    expect(gets, 2);
    await client.delegate.dispose();
  });
  test('Category rename sends one RPC; failed transaction keeps original cached definitions', () async {
    final calls = <http.Request>[];
    var fail = true;
    final client = _Client(
      SupabaseClient(
        'https://test.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          calls.add(request);
          return http.Response(
            request.url.path.endsWith('user_categories')
                ? '[{"name":"Old"},{"name":"Existing"}]'
                : (fail ? '{"code":"23505","message":"duplicate"}' : '2'),
            !request.url.path.endsWith('user_categories') && fail ? 409 : 200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );
        }),
      ),
    );
    final prefs = PreferencesRepository(client, _Images(client));
    expect(await prefs.categories(), ['Old', 'Existing']);
    await expectLater(
      prefs.renameCategory('Old', 'New'),
      throwsA(isA<PostgrestException>()),
    );
    expect(await prefs.categories(), ['Old', 'Existing']);
    fail = false;
    expect(await prefs.renameCategory('Old', ' New '), 2);
    expect(await prefs.categories(), ['New', 'Existing']);
    expect(calls.length, 3);
    expect(calls.last.url.path, endsWith('/rpc/rename_collection_category'));
    expect(jsonDecode(calls.last.body), {'old_name': 'Old', 'new_name': 'New'});
    await expectLater(
      prefs.renameCategory('New', 'Existing'),
      throwsFormatException,
    );
    expect(calls.length, 3);
    await client.delegate.dispose();
  });
  test(
    'Batch category scopes owner and ids; updates only category and timestamp',
    () async {
      final requests = <http.Request>[];
      final client = _Client(
        SupabaseClient(
          'https://test.supabase.co',
          'test-key',
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode([
                {
                  'id': 'a',
                  'user_id': 'owner',
                  'name': 'Original',
                  'category': '周边',
                  'created_at': '2026-01-01',
                  'price': 10,
                  'currency': 'USD',
                  'description': 'Original description',
                  'game_platform': 'PC',
                },
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request,
            );
          }),
        ),
      );
      final repository = ItemRepository(client, _Images(client));
      final updated = await repository.changeCategory(['a', 'b', 'a'], ' 周边 ');
      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.queryParameters['user_id'], 'eq.owner');
      expect(request.url.queryParameters['id'], 'in.("a","b")');
      final body = jsonDecode(request.body) as Map;
      expect(body.keys.toSet(), {'category', 'updated_at'});
      expect(body['category'], '周边');
      expect(updated.single.name, 'Original');
      expect(updated.single.gamePlatform, 'PC');
      expect(updated.single.currency, 'USD');
      expect(await repository.changeCategory([], '周边'), isEmpty);
      expect(await repository.deleteMany([]), isEmpty);
      await expectLater(
        repository.changeCategory(['a'], ''),
        throwsArgumentError,
      );
      await expectLater(
        repository.deleteMany(List.generate(101, (i) => '$i')),
        throwsArgumentError,
      );
      expect(requests.length, 1);
      await client.delegate.dispose();
    },
  );
  test('Delete cleans only confirmed covers; storage failure preserves database success', () async {
    http.Request? seen;
    var fail = false;
    final client = _Client(
      SupabaseClient(
        'https://test.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          seen = request;
          return http.Response(
            fail
                ? jsonEncode({'message': 'denied', 'code': '42501'})
                : jsonEncode([
                    {'id': 'a', 'cover_image': 'current-cover'},
                    {'id': 'b', 'cover_image': 'failed-cover'},
                  ]),
            fail ? 403 : 200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );
        }),
      ),
    );
    final images = _Images(client);
    final repository = ItemRepository(client, images);
    expect(await repository.deleteMany(['a', 'b', 'not-returned']), {'a', 'b'});
    expect(seen!.method, 'DELETE');
    expect(seen!.url.queryParameters['user_id'], 'eq.owner');
    expect(seen!.url.queryParameters['id'], 'in.("a","b","not-returned")');
    expect(seen!.url.queryParameters['select'], 'id,cover_image');
    expect(images.removed, ['current-cover', 'failed-cover']);
    fail = true;
    await expectLater(
      repository.deleteMany(['c']),
      throwsA(isA<PostgrestException>()),
    );
    expect(images.removed.length, 2);
    await client.delegate.dispose();
  });
}
