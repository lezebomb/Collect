import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shou_cang_gui/services/backup_archive_codec.dart';
import 'package:shou_cang_gui/services/legacy_backup_reader.dart';

void main() {
  test('ZIP backup keeps data and image bytes together', () {
    final codec = BackupArchiveCodec();
    final image = Uint8List.fromList([0, 1, 2, 127, 255]);
    final manifest = <String, dynamic>{
      'format': 'collect-backup',
      'version': 2,
      'items': [
        {'id': 'item-1', 'name': '咚奇刚蕉力全开', 'cover_file': 'images/item_1.webp'},
      ],
      'categories': ['游戏'],
      'preferences': {'show_price': true},
      'wallpaper_file': 'wallpaper/wallpaper.jpg',
    };
    final encoded = codec.encode(
      BackupPackage(manifest, {
        'images/item_1.webp': image,
        'wallpaper/wallpaper.jpg': Uint8List.fromList([3, 4, 5]),
      }),
    );
    expect(encoded.take(2), [0x50, 0x4b]);
    final restored = codec.decode(encoded);
    expect(restored.manifest, manifest);
    expect(restored.files['images/item_1.webp'], image);
    expect(restored.files['wallpaper/wallpaper.jpg'], [3, 4, 5]);
  });

  test(
    'old JSON backup can still restore its image into the ZIP data model',
    () {
      final old = {
        'format': 'collect-backup',
        'version': 1,
        'items': [
          {
            'id': 'item-1',
            'user_id': 'user-1',
            'name': '旧收藏',
            'cover_base64': base64Encode([1, 2, 3]),
            'cover_extension': 'png',
          },
        ],
        'categories': ['游戏'],
        'preferences': {'show_price': true},
      };
      final restored = LegacyBackupReader().decode(
        Uint8List.fromList(utf8.encode(jsonEncode(old))),
      );
      expect(restored.manifest['version'], 2);
      expect(restored.manifest['source_user_id'], 'user-1');
      expect(restored.files['images/item_item-1.png'], [1, 2, 3]);
    },
  );
}
