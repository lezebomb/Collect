import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

export 'package:cross_file/cross_file.dart' show XFile;

const harmonyChannel = MethodChannel('app.dearshelf/native');

enum ImageSource { camera, gallery }

enum FileType { custom, any }

class LostDataResponse {
  const LostDataResponse(this.files);
  final List<XFile>? files;
}

/// Same application-facing API as the original pickers; backed by system UI.
class ImagePicker {
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    final picked = await harmonyChannel.invokeMethod<String>('pickImage', {
      'source': source.name,
      'maxWidth': maxWidth ?? 2000,
      'maxHeight': maxHeight ?? 2000,
      'quality': imageQuality ?? 85,
    });
    if (picked != null) await harmonyChannel.invokeMethod<void>('consumeImage');
    return picked == null ? null : XFile(picked);
  }

  Future<LostDataResponse> retrieveLostData() async {
    final picked = await harmonyChannel.invokeMethod<String>('recoverImage');
    if (picked != null) await harmonyChannel.invokeMethod<void>('consumeImage');
    return LostDataResponse(picked == null ? null : [XFile(picked)]);
  }
}

class FilePicker {
  static Future<List<XFile>> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final paths = await harmonyChannel.invokeListMethod<String>('pickFiles', {
      'extensions': allowedExtensions ?? <String>[],
    });
    return (paths ?? <String>[]).map((path) => XFile(path)).toList();
  }

  static Future<XFile?> pickFile({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    final paths = await harmonyChannel.invokeListMethod<String>('pickFiles', {
      'extensions': allowedExtensions ?? <String>[],
      'single': true,
    });
    return paths == null || paths.isEmpty ? null : XFile(paths.first);
  }

  static Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    // Transfer large ZIPs through files, keeping them out of channel messages.
    final temporary = File(
      '${(await getTemporaryDirectory()).path}/${const Uuid().v4()}.export',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      final uri = await harmonyChannel.invokeMethod<String>('saveFile', {
        'fileName': fileName,
        'path': temporary.path,
        'mimeType': mimeType,
      });
      return uri == null ? null : Uri.parse(uri);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
