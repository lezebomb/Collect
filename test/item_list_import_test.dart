import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shou_cang_gui/services/item_list_import.dart';

String list(List<Object?> items) =>
    jsonEncode({'format': 'dearshelf-item-list', 'version': 1, 'items': items});
void main() {
  test('Multiple UTF-8 JSON lists generate new owned items with PC digital defaults and no covers', () {
    final items = ItemListImport.parse({
      'games.json':
          '\uFEFF${list([
            {'name': 'My PC game', 'category': '游戏', 'game_platform': 'PC', 'game_edition': '实体版', 'price': 10, 'currency': 'USD', 'price_cny': 68, 'purchase_date': '2026-10-03'},
          ])}',
      'favorites.json': list([
        {
          'name': 'My keepsake',
          'category': '纪念品',
          'description': 'My own story',
        },
      ]),
    }, owner: 'alice');
    expect(items.length, 2);
    expect(items.first.gameEdition, '数字版');
    expect(items.first.priceCny, 68);
    expect(items.last.description, 'My own story');
    expect(
      items.every((item) => item.userId == 'alice' && item.coverImage == null),
      isTrue,
    );
    expect(items.map((item) => item.id).toSet().length, 2);
  });
  test('Validation reports filename and row, rejects normalized impossible dates, missing FX amounts and unexpected fields', () {
    for (final wrong in [
      {'name': '', 'category': '游戏'},
      {'name': 'Game', 'category': '游戏', 'purchase_date': '2026-02-30'},
      {'name': 'Game', 'category': '游戏', 'currency': 'USD', 'price': 10},
      {'name': 'Game', 'category': '游戏', 'cover_image': 'https://example.com'},
      {'name': 'Game', 'category': '游戏', 'price': -1},
    ]) {
      expect(
        () => ItemListImport.parse({
          'bad.json': list([wrong]),
        }, owner: 'alice'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'location',
            contains('bad.json：第 1 件'),
          ),
        ),
      );
    }
    expect(
      () => ItemListImport.parse({'backup.json': '{}'}, owner: 'alice'),
      throwsFormatException,
    );
    expect(
      () => ItemListImport.parse({
        'large.json': list(
          List.generate(501, (i) => {'name': '$i', 'category': '游戏'}),
        ),
      }, owner: 'alice'),
      throwsFormatException,
    );
    expect(
      ItemListImport.parse({
        'template.json': ItemListImport.template,
      }, owner: 'alice').length,
      2,
    );
  });
}
