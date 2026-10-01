import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shou_cang_gui/core/app_theme.dart';
import 'package:shou_cang_gui/models/collection_item.dart';
import 'package:shou_cang_gui/repositories/item_repository.dart';
import 'package:shou_cang_gui/repositories/preferences_repository.dart';
import 'package:shou_cang_gui/screens/item_form_screen.dart';
import 'package:shou_cang_gui/services/cover_image_service.dart';
import 'package:shou_cang_gui/services/local_workspace_store.dart';
import 'package:shou_cang_gui/widgets/item_image_section.dart';

class _Auth implements GoTrueClient {
  @override
  User get currentUser => const User(
    id: 'alice',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected auth request');
}

class _Client implements SupabaseClient {
  @override
  GoTrueClient get auth => _Auth();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected network request');
}

class _Preferences extends PreferencesRepository {
  _Preferences(super.client, super.images);
  @override
  Future<List<String>> categories({
    List<String> itemCategories = const [],
    bool refresh = false,
  }) async => {'游戏', '周边', ...itemCategories}.toList();
}

class _Drafts extends LocalWorkspaceStore {
  Map<String, dynamic>? draft;
  bool failSave = false;
  @override
  Future<Map<String, dynamic>?> loadDraft(String owner) async => draft;
  @override
  Future<void> saveDraft(String owner, Map<String, dynamic> value) async {
    if (failSave) throw StateError('disk full');
    draft = Map.of(value);
  }

  @override
  Future<void> clearDraft(String owner) async {
    draft = null;
  }
}

class _Items extends ItemRepository {
  _Items(super.client, super.images);
  int writes = 0;
  CollectionItem? requested;
  XFile? cover;
  Completer<CollectionItem>? reply;
  @override
  Future<CollectionItem> create(CollectionItem item, XFile? image) {
    writes++;
    requested = item;
    cover = image;
    return (reply = Completer<CollectionItem>()).future;
  }

  @override
  Future<CollectionItem> update(
    CollectionItem item, {
    XFile? newCover,
    bool removeCover = false,
  }) => create(item, newCover);
}

class _Harness {
  _Harness() {
    final client = _Client();
    images = CoverImageService(client);
    items = _Items(client, images);
    preferences = _Preferences(client, images);
  }
  late final CoverImageService images;
  late final _Items items;
  late final _Preferences preferences;
  final drafts = _Drafts();
  CollectionItem? saved;

  Future<void> open(WidgetTester tester, {CollectionItem? initial}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<CollectionItem>(
                  MaterialPageRoute(
                    builder: (_) => ItemFormScreen(
                      repository: items,
                      images: images,
                      preferences: preferences,
                      initial: initial,
                      drafts: drafts,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

Finder get _name => find.widgetWithText(TextFormField, '名称');

void main() {
  testWidgets('Blank add returns without a draft prompt', (tester) async {
    final h = _Harness();
    await h.open(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(h.drafts.draft, isNull);
  });

  testWidgets(
    'System back offers save, add reopens draft, discard removes it',
    (tester) async {
      final h = _Harness();
      await h.open(tester);
      await tester.enterText(_name, 'A dear thing');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('是否要保存至草稿箱'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(h.drafts.draft!['name'], 'A dear thing');
      expect(h.items.writes, 0);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(_name).controller!.text,
        'A dear thing',
      );
      expect(find.text('草稿箱'), findsOneWidget);
      await tester.enterText(_name, 'Unsaved change');
      await tester.tap(find.text('草稿箱'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A dear thing'));
      await tester.pumpAndSettle();
      expect(find.text('用草稿替换当前填写的内容吗'), findsOneWidget);
      await tester.tap(find.text('载入草稿'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(_name).controller!.text,
        'A dear thing',
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不保存'));
      await tester.pumpAndSettle();
      expect(h.drafts.draft, isNull);
    },
  );

  testWidgets('Draft write failure keeps form, content and old draft', (
    tester,
  ) async {
    final h = _Harness();
    h.drafts.failSave = true;
    await h.open(tester);
    await tester.enterText(_name, 'Keep me');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemFormScreen), findsOneWidget);
    expect(tester.widget<TextFormField>(_name).controller!.text, 'Keep me');
    expect(find.textContaining('草稿处理失败'), findsOneWidget);
    expect(h.items.writes, 0);
  });

  testWidgets(
    'Draft box deletion removes saved draft and keeps current input',
    (tester) async {
      final h = _Harness();
      h.drafts.draft = {'name': 'Stored', 'category': '周边'};
      await h.open(tester);
      await tester.enterText(_name, 'Still editing');
      await tester.tap(find.text('草稿箱'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除已保存的草稿'));
      await tester.pumpAndSettle();
      expect(find.text('当前页面已填写的内容会保留。'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(h.drafts.draft, isNull);
      expect(find.text('草稿箱'), findsNothing);
      expect(
        tester.widget<TextFormField>(_name).controller!.text,
        'Still editing',
      );
      expect(h.items.writes, 0);
    },
  );

  for (final success in [true, false]) {
    testWidgets('Edit back save awaits repository, success = $success', (
      tester,
    ) async {
      final h = _Harness();
      final original = CollectionItem(
        id: 'existing',
        userId: 'alice',
        name: 'Old',
        category: '游戏',
        createdAt: DateTime(2026),
      );
      await h.open(tester, initial: original);
      await tester.enterText(_name, 'Edited');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('是否保存修改'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(h.items.writes, 1);
      expect(h.items.requested!.id, 'existing');
      expect(find.text('正在保存修改…'), findsWidgets);
      expect(find.byType(ItemFormScreen), findsOneWidget);
      if (success) {
        h.items.reply!.complete(h.items.requested!);
      } else {
        h.items.reply!.completeError(StateError('offline'));
      }
      await tester.pumpAndSettle();
      if (success) {
        expect(h.saved!.name, 'Edited');
        expect(find.text('Open'), findsOneWidget);
      } else {
        expect(find.byType(ItemFormScreen), findsOneWidget);
        expect(find.textContaining('保存失败'), findsOneWidget);
      }
    });
  }

  testWidgets('Edit discard does not save, invalid edit save stays in form', (
    tester,
  ) async {
    final h = _Harness();
    final item = CollectionItem(
      id: 'existing',
      userId: 'alice',
      name: 'Old',
      category: '游戏',
      createdAt: DateTime(2026),
    );
    await h.open(tester, initial: item);
    await tester.enterText(_name, '');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(h.items.writes, 0);
    expect(find.text('请输入名称'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不保存'));
    await tester.pumpAndSettle();
    expect(h.saved, isNull);
    expect(h.items.writes, 0);
  });

  testWidgets(
    'Restored cover retains bytes and image extension, create clears draft',
    (tester) async {
      final h = _Harness();
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
      h.drafts.draft = {
        'name': 'Cover draft',
        'category': '周边',
        'cover_bytes': png,
        'cover_name': 'cat.png',
      };
      await h.open(tester);
      expect(
        tester.widget<ItemImageSection>(find.byType(ItemImageSection)).preview,
        base64Decode(png),
      );
      await tester.scrollUntilVisible(
        find.text('保存到收藏柜'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('保存到收藏柜'));
      await tester.pump();
      expect(h.items.cover!.name, 'cat.png');
      expect(await h.items.cover!.readAsBytes(), base64Decode(png));
      h.items.reply!.complete(h.items.requested!);
      await tester.pumpAndSettle();
      expect(h.drafts.draft, isNull);
      expect(h.saved!.category, '周边');
    },
  );
}
