import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shou_cang_gui/core/price_display.dart';
import 'package:shou_cang_gui/models/collection_item.dart';
import 'package:shou_cang_gui/services/local_workspace_store.dart';

void main() {
  test(
    'Draft and cover survive reopening, replacing and account changes',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'dearshelf-draft-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      LocalWorkspaceStore store() =>
          LocalWorkspaceStore(directory: () async => folder);
      final draft = {
        'name': 'My favorite',
        'price': '',
        'cover_bytes': base64Encode([1, 2, 3]),
        'cover_name': 'cat.png',
      };
      await store().saveDraft('alice', draft);
      await store().savePriceDisplay('alice', PriceDisplay.cny);
      expect(await store().loadDraft('alice'), draft);
      expect(await store().loadPriceDisplay('alice'), PriceDisplay.cny);
      expect(await store().loadDraft('bob'), isNull);
      expect(await store().loadPriceDisplay('bob'), PriceDisplay.original);
      await store().saveDraft('alice', {...draft, 'name': 'Updated'});
      expect((await store().loadDraft('alice'))!['name'], 'Updated');
      // A failed replacement cannot corrupt the last successful draft.
      await expectLater(
        store().saveDraft('alice', {'invalid': Object()}),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect((await store().loadDraft('alice'))!['name'], 'Updated');
      await store().clearDraft('alice');
      expect(await store().loadDraft('alice'), isNull);
      expect(await store().loadPriceDisplay('alice'), PriceDisplay.cny);
      expect(
        await folder
            .list(recursive: true)
            .where((e) => e.path.endsWith('.tmp'))
            .length,
        0,
      );
    },
  );

  test(
    'Price display uses saved conversion, never labels original amount CNY',
    () {
      final item = CollectionItem(
        id: '1',
        userId: 'alice',
        name: 'Game',
        category: '游戏',
        createdAt: DateTime(2026),
        price: 100,
        currency: 'HKD',
        priceCny: 92,
      );
      expect(displayedPrice(item, PriceDisplay.original), (
        amount: 100.0,
        currency: 'HKD',
      ));
      expect(displayedPrice(item, PriceDisplay.cny), (
        amount: 92.0,
        currency: 'CNY',
      ));
      final legacy = CollectionItem(
        id: '2',
        userId: 'alice',
        name: 'Game',
        category: '游戏',
        createdAt: DateTime(2026),
        price: 100,
        currency: 'USD',
      );
      expect(displayedPrice(legacy, PriceDisplay.cny).amount, isNull);
      final cny = CollectionItem(
        id: '3',
        userId: 'alice',
        name: 'Game',
        category: '游戏',
        createdAt: DateTime(2026),
        price: 100,
      );
      expect(displayedPrice(cny, PriceDisplay.cny).amount, 100);
    },
  );
}
