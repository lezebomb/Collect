import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shou_cang_gui/models/catalog_candidate.dart';
import 'package:shou_cang_gui/services/image_search_service.dart';

void main() {
  test('preview and selection share one image download', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final subscription = server.listen((request) async {
      requests++;
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add([137, 80, 78, 71, 13, 10, 26, 10]);
      await request.response.close();
    });
    try {
      final images = ImageSearchService();
      final candidate = CatalogCandidate(
        title: 'test image',
        source: 'local test server',
        imageUrl: 'http://127.0.0.1:${server.port}/cover.png',
      );
      final results = await Future.wait([
        images.previewBytes(candidate),
        images.download(candidate).then((file) => file.readAsBytes()),
      ]);
      expect(results[0], results[1]);
      await images.download(candidate);
      expect(requests, 1);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
