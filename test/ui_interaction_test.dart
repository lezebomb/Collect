import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shou_cang_gui/core/app_theme.dart';
import 'package:shou_cang_gui/models/collection_item.dart';
import 'package:shou_cang_gui/screens/stats_screen.dart';
import 'package:shou_cang_gui/widgets/catalog_selection_dialog.dart';
import 'package:shou_cang_gui/widgets/loading_overlay.dart';
import 'package:shou_cang_gui/widgets/collection_card.dart';
import 'package:shou_cang_gui/models/user_preferences.dart';
import 'package:shou_cang_gui/services/cover_image_service.dart';

void main() {
  testWidgets(
    'Compact collection card fits all optional information and responds to taps',
    (tester) async {
      var taps = 0;
      final client = _UnusedSupabaseClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Center(
                child: SizedBox(
                  width: 134,
                  height: 255,
                  child: CollectionCard(
                    item: CollectionItem(
                      id: 'test',
                      userId: 'test',
                      name: '长名称收藏长名称收藏',
                      category: '自定义长分类名称',
                      createdAt: DateTime(2026),
                      price: 123456.78,
                    ),
                    images: CoverImageService(client),
                    preferences: const UserPreferences(
                      showPrice: true,
                      showOwnedDays: true,
                      showDailyCost: true,
                    ),
                    onTap: () => taps++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(CollectionCard));
      expect(taps, 1);
    },
  );
  for (final choice in [
    (useImage: true, useTitle: false),
    (useImage: false, useTitle: true),
    (useImage: true, useTitle: true),
  ]) {
    testWidgets('Search choices remain independent: $choice', (tester) async {
      CatalogSelection? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showDialog<CatalogSelection>(
                    context: context,
                    builder: (_) =>
                        const CatalogSelectionDialog(title: '搜索结果名称'),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final tiles = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(tiles[0].value, isTrue);
      expect(tiles[1].value, isFalse);
      expect(find.text('填充简介'), findsNothing);
      if (!choice.useImage) await tester.tap(find.text('使用该图片作为封面'));
      if (choice.useTitle) await tester.tap(find.text('使用该结果名称'));
      await tester.pump();
      await tester.tap(find.text('确认使用'));
      await tester.pumpAndSettle();
      expect(selected, choice);
    });
  }

  testWidgets('No selection disables apply', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const CatalogSelectionDialog(title: '结果'),
      ),
    );
    await tester.tap(find.text('使用该图片作为封面'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'Loading overlay gives visible feedback and blocks repeated taps',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: LoadingOverlay(
              loading: true,
              message: '正在下载封面图片…',
              child: Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('再次请求'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('正在下载封面图片…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('再次请求'), warnIfMissed: false);
      expect(taps, 0);
    },
  );

  testWidgets(
    'Statistics fit narrow screens with larger text and long labels',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: StatsScreen(
              items: [
                CollectionItem(
                  id: '1',
                  userId: 'test',
                  name: '收藏',
                  category: '一个比较长的自定义收藏分类',
                  createdAt: DateTime(2026, 9),
                  price: 12345678.90,
                  priceCny: 12345678.90,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

// A missing cover never requests a signed URL. Fail if this layout test makes
// a network call rather than starting a real authentication client.
class _UnusedSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected client access: ${invocation.memberName}');
}
