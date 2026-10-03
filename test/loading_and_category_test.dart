import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shou_cang_gui/core/app_theme.dart';
import 'package:shou_cang_gui/core/collection_snapshot.dart';
import 'package:shou_cang_gui/core/price_display.dart';
import 'package:shou_cang_gui/models/collection_item.dart';
import 'package:shou_cang_gui/models/user_preferences.dart';
import 'package:shou_cang_gui/repositories/item_repository.dart';
import 'package:shou_cang_gui/repositories/preferences_repository.dart';
import 'package:shou_cang_gui/screens/collection_screen.dart';
import 'package:shou_cang_gui/services/cover_image_service.dart';
import 'package:shou_cang_gui/services/local_workspace_store.dart';
import 'package:shou_cang_gui/widgets/category_chip.dart';
import 'package:shou_cang_gui/widgets/collection_card.dart';

class _Auth implements GoTrueClient {
  @override
  User get currentUser => const User(
    id: 'owner',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected auth');
}

class _Client implements SupabaseClient {
  @override
  GoTrueClient get auth => _Auth();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected network');
}

class _Images extends CoverImageService {
  _Images(super.client);
  @override
  Future<void> clearSession() async {}
}

class _Items extends ItemRepository {
  _Items(super.client, super.images);
  final response = Completer<List<CollectionItem>>();
  int calls = 0;
  @override
  Future<List<CollectionItem>> list({bool refresh = false}) {
    calls++;
    return response.future;
  }
}

class _Prefs extends PreferencesRepository {
  _Prefs(super.client, super.images);
  final prefs = Completer<UserPreferences>();
  final categoriesReply = Completer<List<String>>();
  Completer<int>? rename;
  @override
  Future<UserPreferences> load({bool refresh = false}) => prefs.future;
  @override
  Future<List<String>> categories({
    List<String> itemCategories = const [],
    bool refresh = false,
  }) => categoriesReply.future;
  @override
  Future<int> renameCategory(String oldName, String newName) =>
      (rename = Completer<int>()).future;
}

class _Local extends LocalWorkspaceStore {
  CollectionSnapshot? snapshot;
  @override
  Future<CollectionSnapshot?> loadCollectionSnapshot(String owner) async =>
      snapshot;
  @override
  Future<void> saveCollectionSnapshot(
    String owner,
    CollectionSnapshot view,
  ) async {
    snapshot = view;
  }

  @override
  Future<PriceDisplay> loadPriceDisplay(String owner) async =>
      PriceDisplay.original;
}

CollectionItem _item(String name) => CollectionItem(
  id: name,
  userId: 'owner',
  name: name,
  category: '旧分类',
  createdAt: DateTime(2026),
  price: 20,
  priceCny: 20,
  gamePlatform: 'PC',
);

class _Harness {
  final client = _Client();
  late final images = _Images(client);
  late final items = _Items(client, images);
  late final prefs = _Prefs(client, images);
  final local = _Local();
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CollectionScreen(
          client: client,
          images: images,
          itemsRepository: items,
          preferencesRepository: prefs,
          local: local,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  void complete() {
    items.response.complete([_item('Fresh')]);
    prefs.prefs.complete(const UserPreferences());
    prefs.categoriesReply.complete(['旧分类', '已有分类']);
  }
}

void main() {
  testWidgets(
    'Disk snapshot shows wall and statistics while all cloud work is pending; tabs do not refetch',
    (tester) async {
      final h = _Harness();
      h.local.snapshot = CollectionSnapshot(
        items: [_item('Cached')],
        preferences: const UserPreferences(),
        categories: ['旧分类'],
      );
      await h.open(tester);
      expect(find.text('Cached'), findsOneWidget);
      expect(find.byType(CollectionCard), findsOneWidget);
      await tester.tap(find.text('统计'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('收藏统计'), findsOneWidget);
      expect(find.text('藏品价值'), findsOneWidget);
      expect(h.items.calls, 1);
      h.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('展柜'));
      await tester.pumpAndSettle();
      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('Cached'), findsNothing);
      expect(h.items.calls, 1);
    },
  );
  testWidgets(
    'Cold cloud items render without waiting for settings; failed sync keeps a cached wall',
    (tester) async {
      final h = _Harness();
      await h.open(tester);
      h.items.response.complete([_item('Arrived first')]);
      await tester.pump();
      expect(find.text('Arrived first'), findsOneWidget);
      h.prefs.prefs.completeError(StateError('offline'));
      h.prefs.categoriesReply.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Arrived first'), findsOneWidget);
      expect(find.text('部分数据同步失败，点击重试'), findsOneWidget);
    },
  );
  testWidgets(
    'Category long-press validates duplicates then updates settings, wall, stats and disk only after confirmation',
    (tester) async {
      final h = _Harness();
      h.complete();
      await h.open(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      final chip = find.widgetWithText(CategoryChip, '旧分类');
      await tester.ensureVisible(chip);
      await tester.longPress(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑分类名称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '已有分类');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('已存在同名分类'), findsOneWidget);
      expect(h.prefs.rename, isNull);
      await tester.enterText(find.byType(TextFormField), '新分类');
      await tester.tap(find.text('保存'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(CategoryChip, '旧分类'), findsOneWidget);
      expect(h.local.snapshot!.items.single.category, '旧分类');
      h.prefs.rename!.complete(1);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CategoryChip, '新分类'), findsOneWidget);
      expect(h.local.snapshot!.items.single.category, '新分类');
      expect(h.local.snapshot!.items.single.gamePlatform, 'PC');
      expect(h.items.calls, 1);
      await tester.tap(find.text('展柜'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CategoryChip, '旧分类'), findsNothing);
      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      expect(find.text('新分类'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
