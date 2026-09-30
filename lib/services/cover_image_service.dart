import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class CoverImageService {
  CoverImageService(this.client);

  static const bucket = 'item-covers';
  static const maxBytes = 10 * 1024 * 1024;
  static const _baseUrl = String.fromEnvironment('SUPABASE_URL');

  final SupabaseClient client;

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
    return client.storage.from(bucket).createSignedUrl(path, 3600);
  }

  Future<void> remove(String? imageUrl) async {
    final path = pathFromUrl(imageUrl);
    if (path != null) await client.storage.from(bucket).remove([path]);
  }

  Future<List<int>?> downloadBytes(String? imageUrl) async {
    final path = pathFromUrl(imageUrl);
    if (path == null) return null;
    return client.storage.from(bucket).download(path);
  }
}
