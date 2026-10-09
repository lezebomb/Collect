import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shou_cang_gui/services/cover_encoding.dart';

void main() {
  test(
    'Large opaque PNG becomes a smaller JPEG, with preserved dimensions',
    () {
      final image = img.Image(width: 900, height: 660, numChannels: 4);
      for (final pixel in image) {
        pixel.setRgba(
          (pixel.x * 17 + pixel.y * 3) % 256,
          (pixel.y * 13 + pixel.x) % 256,
          (pixel.x * 5 + pixel.y * 19) % 256,
          255,
        );
      }
      final png = img.encodePng(image, level: 0);
      final compact = compactCover(png);
      expect(compact.length, lessThan(png.length));
      expect(compact.take(2), [255, 216]);
      final decoded = img.decodeImage(compact)!;
      expect(decoded.width, image.width);
      expect(decoded.height, image.height);
    },
  );
  test('Transparency, small files and unsupported formats retain bytes', () {
    final image = img.Image(width: 400, height: 400, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(100, 80, 60, 0));
    final png = img.encodePng(image, level: 0);
    expect(compactCover(png), png);
    final small = Uint8List.fromList([1, 2, 3]);
    expect(compactCover(small), same(small));
    final unknown = Uint8List(300 * 1024);
    expect(compactCover(unknown), same(unknown));
  });
}
