import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shou_cang_gui/core/app_access.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Auth implements GoTrueClient {
  _Auth(this.currentUser);
  @override
  final User? currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected auth call');
}

class _PreviewClient implements SupabaseClient {
  _PreviewClient(User? user) : auth = _Auth(user);
  @override
  final GoTrueClient auth;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Preview must not call private access RPCs');
}

void main() {
  test(
    'Explicit pre-migration preview still requires a signed-in user',
    () async {
      final signedOut = AppAccess(
        _PreviewClient(null),
        requirePrivateAccess: false,
        requireEmailAccess: false,
      );
      expect(await signedOut.allowed(), false);
      final preview = AppAccess(
        _PreviewClient(
          const User(
            id: 'owner',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-01-01',
          ),
        ),
        requirePrivateAccess: false,
        requireEmailAccess: false,
      );
      expect(await preview.allowed(), true);
      await preview.reserveCover('owner/item/cover.jpg');
      await preview.releaseCover('owner/item/cover.jpg');
    },
  );

  test(
    'Private mode never falls back when the migration RPC is missing',
    () async {
      final client = SupabaseClient(
        'https://test.supabase.co',
        'test-key',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({'code': 'PGRST202', 'message': 'Function not found'}),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      final access = AppAccess(client, requirePrivateAccess: true);
      await expectLater(access.allowed(), throwsA(isA<PostgrestException>()));
      await expectLater(
        access.reserveCover('owner/item/cover.jpg'),
        throwsA(isA<PostgrestException>()),
      );
      await client.dispose();
    },
  );

  test('Email-only mode preserves a server membership denial', () async {
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        expect(
          request.url.path,
          '/rest/v1/rpc/collection_email_access_allowed',
        );
        return http.Response(
          'false',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    expect(
      await AppAccess(client, requirePrivateAccess: false).allowed(),
      false,
    );
    await client.dispose();
  });

  test('Email-only mode fails closed when membership RPC is missing', () async {
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-key',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'code': 'PGRST202', 'message': 'Function not found'}),
          404,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    await expectLater(
      AppAccess(client, requirePrivateAccess: false).allowed(),
      throwsA(isA<PostgrestException>()),
    );
    await AppAccess(
      client,
      requirePrivateAccess: false,
    ).reserveCover('owner/image.jpg');
    await client.dispose();
  });

  test('Private mode propagates a quota denial before uploading', () async {
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/reserve_collection_cover');
        expect(jsonDecode(request.body), {
          'object_path': 'owner/item/cover.jpg',
        });
        return http.Response(
          jsonEncode({'code': '42501', 'message': 'Storage quota exceeded'}),
          403,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await expectLater(
      AppAccess(
        client,
        requirePrivateAccess: true,
      ).reserveCover('owner/item/cover.jpg'),
      throwsA(isA<PostgrestException>()),
    );
    await client.dispose();
  });
}
