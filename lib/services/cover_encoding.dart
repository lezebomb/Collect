import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Runs in a worker isolate. The crop editor already caps covers at 1200px.
/// Small files and unsupported formats (HEIC) retain their original bytes.
Uint8List compactCover(Uint8List bytes) {
  if (bytes.length < 256 * 1024) return bytes;
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info != null && info.width * info.height > 36000000) {
    throw const FormatException('图片分辨率过大，请先裁剪');
  }
  final decoded = decoder?.decodeFrame(0);
  if (decoded == null) return bytes;
  if (decoded.hasAlpha &&
      decoded.any((pixel) => pixel.a != pixel.maxChannelValue)) {
    return bytes;
  }
  final oriented = img.bakeOrientation(decoded);
  final resized = oriented.width > 1600 || oriented.height > 1600
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 1600 : null,
          height: oriented.height > oriented.width ? 1600 : null,
        )
      : oriented;
  final encoded = img.encodeJpg(resized, quality: 85);
  return encoded.length < bytes.length ? encoded : bytes;
}
