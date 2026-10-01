import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shou_cang_gui/core/app_theme.dart';
import 'package:shou_cang_gui/models/collection_item.dart';
import 'package:shou_cang_gui/models/user_preferences.dart';
import 'package:shou_cang_gui/repositories/item_repository.dart';
import 'package:shou_cang_gui/repositories/preferences_repository.dart';
import 'package:shou_cang_gui/screens/settings_screen.dart';
import 'package:shou_cang_gui/services/backup_service.dart';
import 'package:shou_cang_gui/services/cover_image_service.dart';
import 'package:shou_cang_gui/widgets/collection_card.dart';
import 'package:shou_cang_gui/widgets/collection_wall.dart';
import 'package:shou_cang_gui/widgets/category_chip.dart';
import 'package:shou_cang_gui/widgets/item_image_section.dart';
import 'package:shou_cang_gui/widgets/rounded_choice_field.dart';
import 'package:shou_cang_gui/widgets/selection_sheet.dart';

class _UnusedClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected request');
}

class _DelayedPreferences extends PreferencesRepository {
  _DelayedPreferences(super.client, super.images);
  final requests = <UserPreferences>[];
  final replies = <Completer<UserPreferences>>[];
  Completer<void>? deletion;
  @override
  Future<UserPreferences> save(UserPreferences prefs) {
    requests.add(prefs);
    final reply = Completer<UserPreferences>();
    replies.add(reply);
    return reply.future;
  }

  @override
  Future<void> removeCategory(String name) =>
      (deletion = Completer<void>()).future;
}

void main() {
  for (final size in [
    const Size(360, 780),
    const Size(390, 844),
    const Size(320, 700),
  ]) {
    testWidgets('Six complete cards and full long names fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final search = TextEditingController();
      addTearDown(search.dispose);
      final name = List.filled(10, '很长的收藏品名称').join();
      final items = List.generate(
        6,
        (i) => CollectionItem(
          id: '$i',
          userId: 'test',
          name: i == 0 ? name : '收藏 $i',
          category: '游戏',
          createdAt: DateTime(2026),
          price: 123.45,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            appBar: AppBar(title: const Text('收藏柜')),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(icon: Icon(Icons.shelves), label: '展柜'),
                NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
              ],
            ),
            body: CollectionWall(
              items: items,
              total: 6,
              categories: const ['游戏'],
              category: null,
              preferences: const UserPreferences(
                showPrice: true,
                showDailyCost: true,
                showOwnedDays: true,
              ),
              images: CoverImageService(_UnusedClient()),
              search: search,
              searchExpanded: false,
              onSearch: () {},
              onCloseSearch: () {},
              onCategory: (_) {},
              onOpen: (_) {},
              onRefresh: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final wall = tester.getRect(find.byType(CollectionWall));
      for (final card in find.byType(CollectionCard).evaluate()) {
        final rect = tester.getRect(find.byWidget(card.widget));
        expect(rect.bottom, lessThanOrEqualTo(wall.bottom));
      }
      expect(find.byType(CollectionCard), findsNWidgets(6));
      final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.height, lessThanOrEqualTo(36.1));
      expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
      final label = tester.widget<Text>(find.text(name));
      expect(label.style!.fontSize, lessThan(14));
    });
  }

  testWidgets(
    'Narrow currency field shows its complete value and rounded choices',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 84,
              child: RoundedChoiceField(
                label: '货币',
                value: 'CNY',
                values: const ['CNY', 'USD'],
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('CNY')).overflow,
        isNot(TextOverflow.ellipsis),
      );
      await tester.tap(find.text('CNY'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionOption), findsNWidgets(2));
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(selected, 'USD');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Default and custom category chips share height and deletion behavior',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: [
                CategoryChip(label: '游戏', onDeleted: () {}),
                CategoryChip(label: '1', onDeleted: () {}),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(CategoryChip).first).height,
        tester.getSize(find.byType(CategoryChip).last).height,
      );
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
    },
  );

  testWidgets('Entire cover opens gallery and camera sheet', (tester) async {
    var gallery = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ItemImageSection(
            preview: null,
            imageUrl: null,
            images: CoverImageService(_UnusedClient()),
            busy: false,
            onGallery: () => gallery++,
            onCamera: () {},
            onRemove: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('为收藏选一张封面'));
    await tester.pumpAndSettle();
    expect(find.text('从相册选择'), findsOneWidget);
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();
    expect(gallery, 1);
  });

  testWidgets(
    'Switches update immediately, serialize saves, and roll back failures',
    (tester) async {
      final client = _UnusedClient();
      final images = CoverImageService(client);
      final repository = _DelayedPreferences(client, images);
      final items = ItemRepository(client, images);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SettingsScreen(
              repository: repository,
              backup: BackupService(client, items, repository, images),
              images: images,
              initialPreferences: const UserPreferences(),
              initialCategories: const ['游戏', '1'],
              onChanged: (_, categories) {},
              onDataChanged: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('展示价格'));
      await tester.pump();
      expect(
        tester
            .widgetList<SwitchListTile>(find.byType(SwitchListTile))
            .first
            .value,
        isTrue,
      );
      expect(find.text('正在更新，请稍候…'), findsNothing);
      await tester.tap(find.text('展示日均价格'));
      await tester.pump();
      expect(repository.requests.length, 1);
      repository.replies.first.complete(repository.requests.first);
      await tester.pump();
      expect(repository.requests.length, 2);
      expect(repository.requests.last.showPrice, isTrue);
      expect(repository.requests.last.showDailyCost, isTrue);
      repository.replies.last.completeError(StateError('offline'));
      await tester.pump();
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches[0].value, isTrue);
      expect(switches[2].value, isFalse);
      await tester.drag(find.byType(ListView), const Offset(0, -380));
      await tester.pump();
      expect(find.byTooltip('删除游戏分类'), findsNothing);
      await tester.tap(find.byTooltip('删除分类'));
      await tester.pump();
      await tester.tap(find.byTooltip('删除游戏分类'));
      await tester.pump();
      expect(find.text('游戏'), findsNothing);
      repository.deletion!.completeError(StateError('offline'));
      await tester.pump();
      expect(find.text('游戏'), findsOneWidget);
    },
  );
}
