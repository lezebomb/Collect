import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shou_cang_gui/services/cover_image_service.dart';

void main() {
  test('Visible covers share one signature request; paths reuse fresh signatures', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        calls++;
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map;
        final paths = (body['paths'] as List).cast<String>();
        expect(paths.length, 2);
        return http.Response(
          jsonEncode([
            for (final path in paths)
              {
                'path': path,
                'signedURL': '/object/sign/item-covers/$path?token=example',
              },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final images = CoverImageService(
      client,
      baseUrl: 'https://test.supabase.co',
    );
    const prefix =
        'https://test.supabase.co/storage/v1/object/authenticated/item-covers/';
    final results = await Future.wait([
      images.signedUrl('${prefix}owner/a/1.jpg'),
      images.signedUrl('${prefix}owner/b/2.jpg'),
      images.signedUrl('${prefix}owner/a/1.jpg'),
    ]);
    expect(calls, 1);
    expect(results[0], results[2]);
    expect(await images.signedUrl('${prefix}owner/a/1.jpg'), results[0]);
    expect(calls, 1);
    await client.dispose();
  });
}
