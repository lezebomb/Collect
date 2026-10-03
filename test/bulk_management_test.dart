import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shou_cang_gui/core/app_theme.dart';
import 'package:shou_cang_gui/core/price_display.dart';
import 'package:shou_cang_gui/core/collection_snapshot.dart';
import 'package:shou_cang_gui/models/collection_item.dart';
import 'package:shou_cang_gui/models/user_preferences.dart';
import 'package:shou_cang_gui/repositories/item_repository.dart';
import 'package:shou_cang_gui/repositories/preferences_repository.dart';
import 'package:shou_cang_gui/screens/collection_screen.dart';
import 'package:shou_cang_gui/services/cover_image_service.dart';
import 'package:shou_cang_gui/services/local_workspace_store.dart';
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
      throw StateError('Unexpected API');
}

class _Images extends CoverImageService {
  _Images(super.client);
  @override
  Future<void> clearSession() async {}
}

class _Preferences extends PreferencesRepository {
  _Preferences(super.client, super.images);
  @override
  Future<UserPreferences> load({bool refresh = false}) async =>
      const UserPreferences();
  @override
  Future<List<String>> categories({
    List<String> itemCategories = const [],
    bool refresh = false,
  }) async => ['游戏', '周边', '1'];
}

class _Local extends LocalWorkspaceStore {
  @override
  Future<CollectionSnapshot?> loadCollectionSnapshot(String owner) async =>
      null;
  @override
  Future<void> saveCollectionSnapshot(
    String owner,
    CollectionSnapshot view,
  ) async {}
  @override
  Future<PriceDisplay> loadPriceDisplay(String owner) async =>
      PriceDisplay.original;
}

CollectionItem item(int i) => CollectionItem(
  id: '$i',
  userId: 'owner',
  name: '藏品 $i',
  category: i == 2 ? '周边' : '游戏',
  createdAt: DateTime(2026, 1, i + 1),
  price: 10.0 + i,
  description: '简介 $i',
  gamePlatform: i == 2 ? null : 'PC',
);

class _Items extends ItemRepository {
  _Items(super.client, super.images, int count)
    : stored = List.generate(count, item);
  List<CollectionItem> stored;
  int loads = 0;
  final deleted = <List<String>>[];
  final changed = <List<String>>[];
  Completer<Set<String>>? deletion;
  Completer<List<CollectionItem>>? categoryReply;
  bool failSecondDelete = false;
  @override
  Future<List<CollectionItem>> list({bool refresh = false}) async {
    loads++;
    return List.of(stored);
  }

  @override
  Future<Set<String>> deleteMany(List<String> ids) async {
    deleted.add(List.of(ids));
    if (failSecondDelete && deleted.length == 2) throw StateError('Offline');
    final confirmed = deletion == null ? ids.toSet() : await deletion!.future;
    stored = stored.where((item) => !confirmed.contains(item.id)).toList();
    return confirmed;
  }

  @override
  Future<List<CollectionItem>> changeCategory(
    List<String> ids,
    String category,
  ) async {
    changed.add(List.of(ids));
    final saved = categoryReply == null
        ? [
            for (final item in stored)
              if (ids.contains(item.id))
                CollectionItem.fromJson({
                  ...item.toCreateJson(),
                  'category': category,
                }),
          ]
        : await categoryReply!.future;
    final map = {for (final item in saved) item.id: item};
    stored = [for (final item in stored) map[item.id] ?? item];
    return saved;
  }
}

class _Harness {
  _Harness({int count = 3}) {
    client = _Client();
    images = _Images(client);
    items = _Items(client, images, count);
    preferences = _Preferences(client, images);
  }
  late final _Client client;
  late final _Images images;
  late final _Items items;
  late final _Preferences preferences;
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: CollectionScreen(
          client: client,
          images: images,
          itemsRepository: items,
          preferencesRepository: preferences,
          local: _Local(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Finder card(int i) => find.widgetWithText(CollectionCard, '藏品 $i');

void main() {
  testWidgets(
    'Small screen with enlarged text keeps selection controls usable',
    (tester) async {
      final h = _Harness();
      await h.open(tester, size: const Size(320, 700), textScale: 1.5);
      await tester.tap(find.text('批量管理'));
      await tester.pumpAndSettle();
      await tester.tap(card(0));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 件'), findsOneWidget);
      await tester.tap(find.text('修改分类'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Long press exposes delete; cancel and back preserve items', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    await tester.longPress(card(0));
    await tester.pumpAndSettle();
    expect(find.text('删除收藏'), findsOneWidget);
    expect(find.text('收藏详情'), findsNothing);
    await tester.tap(find.text('删除收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(h.items.deleted, isEmpty);
    await tester.longPress(card(0));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('批量管理'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选 1 件'), findsOneWidget);
    expect(tester.widget<CollectionCard>(card(0)).selected, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Dearshelf'), findsOneWidget);
    expect(h.items.loads, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Category update shows progress and merges saved items without a fetch',
    (tester) async {
      final h = _Harness();
      await h.open(tester);
      await tester.tap(find.text('批量管理'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '修改分类'))
            .onPressed,
        isNull,
      );
      await tester.tap(card(0));
      await tester.tap(card(1));
      await tester.pumpAndSettle();
      h.items.categoryReply = Completer<List<CollectionItem>>();
      await tester.tap(find.text('修改分类'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(BottomSheet), matching: find.text('1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('正在修改分类'), findsOneWidget);
      expect(h.items.changed.single.toSet(), {'0', '1'});
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '退出批量管理',
              ),
            )
            .onPressed,
        isNull,
      );
      h.items.categoryReply!.complete([
        for (final i in [0, 1])
          CollectionItem.fromJson({...item(i).toCreateJson(), 'category': '1'}),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Dearshelf'), findsOneWidget);
      expect(h.items.loads, 1);
      expect(h.items.stored.first.gamePlatform, 'PC');
      expect(h.items.stored.first.description, '简介 0');
      expect(tester.widget<CollectionCard>(card(0)).item.category, '1');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'All selects only filtered items; delete cancel and confirm update dashboard',
    (tester) async {
      final h = _Harness();
      await h.open(tester);
      await tester.tap(find.text('游戏').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('批量管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 件'), findsOneWidget);
      await tester.tap(find.text('全不选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 件'), findsOneWidget);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除选中的 2 件收藏？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(h.items.deleted, isEmpty);
      h.items.deletion = Completer<Set<String>>();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('正在删除收藏'), findsOneWidget);
      expect(h.items.deleted.single.toSet(), {'0', '1'});
      h.items.deletion!.complete({'0', '1'});
      await tester.pumpAndSettle();
      expect(h.items.stored.single.id, '2');
      expect(find.text('0 / 1 件收藏'), findsOneWidget);
      expect(h.items.loads, 1);
      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      expect(find.text('藏品数量'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Large batch is bounded; partial failure retains remaining selection',
    (tester) async {
      final h = _Harness(count: 103);
      await h.open(tester);
      h.items.failSecondDelete = true;
      await tester.tap(find.text('批量管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 103 件'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.items.deleted.map((ids) => ids.length), [100, 3]);
      expect(h.items.stored.length, 3);
      expect(find.text('已选 3 件'), findsOneWidget);
      expect(find.textContaining('已确认完成 100 / 103 件'), findsOneWidget);
      expect(h.items.loads, 2);
      h.items.failSecondDelete = false;
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.items.deleted.last.length, 3);
      expect(h.items.stored, isEmpty);
      expect(find.text('Dearshelf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
