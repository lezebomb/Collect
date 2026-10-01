import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shou_cang_gui/core/app_theme.dart';
import 'package:shou_cang_gui/core/price_display.dart';
import 'package:shou_cang_gui/models/collection_item.dart';
import 'package:shou_cang_gui/models/user_preferences.dart';
import 'package:shou_cang_gui/repositories/item_repository.dart';
import 'package:shou_cang_gui/repositories/preferences_repository.dart';
import 'package:shou_cang_gui/screens/settings_screen.dart';
import 'package:shou_cang_gui/screens/stats_screen.dart';
import 'package:shou_cang_gui/services/backup_service.dart';
import 'package:shou_cang_gui/services/cover_image_service.dart';
import 'package:shou_cang_gui/widgets/confirmation_dialog.dart';
import 'package:shou_cang_gui/widgets/monthly_spending_chart.dart';
import 'package:shou_cang_gui/widgets/category_chip.dart';
import 'package:shou_cang_gui/widgets/collection_card.dart';
import 'package:shou_cang_gui/widgets/controller_symbols.dart';

class _Client implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected network access');
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
  }) async => ['游戏', '1'];
}

class _Backup extends BackupService {
  _Backup(super.client, super.items, super.preferences, super.images);
  final exported = Completer<Uri?>();
  final imported = Completer<int?>();
  @override
  Future<Uri?> export() => exported.future;
  @override
  Future<int?> import() => imported.future;
}

void main() {
  testWidgets(
    'Trend has all months, fills gaps, scrolls both ways and preserves offset',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const values = {'2024-01': 10.0, '2026-06': 90.0};
      Widget chart() => const MaterialApp(
        home: Scaffold(body: MonthlySpendingChart(values: values)),
      );
      await tester.pumpWidget(chart());
      await tester.pumpAndSettle();
      final scrollFinder = find.byKey(const ValueKey('monthly-chart-scroll'));
      final controller = tester.widget<ListView>(scrollFinder).controller!;
      expect(find.text('2026 年'), findsOneWidget);
      expect(find.text('6月'), findsWidgets);
      expect(find.text('金额 / CNY'), findsNothing);
      expect(find.text('¥0.00'), findsWidgets);
      final latest = controller.offset;
      expect(latest, greaterThan(0));
      await tester.drag(scrollFinder, const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(latest));
      expect(find.text('2025 年'), findsOneWidget);
      final previous = controller.offset;
      await tester.pumpWidget(chart());
      await tester.pumpAndSettle();
      expect(controller.offset, previous);
      await tester.drag(scrollFinder, const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(previous));
      await tester.tap(find.byKey(const ValueKey('monthly-chart-year')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2024 年'));
      await tester.pumpAndSettle();
      expect(find.text('1月'), findsWidgets);
      expect(find.text('¥10.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Year/category icon sheets filter totals; bars have distinct colors',
    (tester) async {
      final key = GlobalKey<StatsScreenState>();
      final items = [
        CollectionItem(
          id: '1',
          userId: 'a',
          name: 'Game',
          category: '游戏',
          createdAt: DateTime(2025),
          priceCny: 10,
        ),
        CollectionItem(
          id: '2',
          userId: 'a',
          name: 'Thing',
          category: '周边',
          createdAt: DateTime(2026),
          priceCny: 20,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            appBar: AppBar(
              title: const Text('收藏统计'),
              actions: [
                IconButton(
                  tooltip: '筛选分类',
                  icon: const Icon(Icons.category_outlined),
                  onPressed: () => key.currentState!.chooseCategory(),
                ),
                IconButton(
                  tooltip: '筛选年份',
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: () => key.currentState!.chooseYear(),
                ),
              ],
            ),
            body: StatsScreen(key: key, items: items),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('收藏的足迹'), findsNothing);
      expect(find.text('藏品数量'), findsOneWidget);
      expect(find.text('¥30.00'), findsOneWidget);
      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(bars[0].color, isNot(bars[1].color));
      await tester.tap(find.byTooltip('筛选年份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026 年'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('¥20.00'), findsWidgets);
      await tester.tap(find.byTooltip('筛选分类'));
      await tester.pumpAndSettle();
      final game = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('游戏'),
      );
      await tester.tap(game);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find
              .ancestor(of: find.text('藏品价值'), matching: find.byType(Card))
              .first,
          matching: find.text('¥0.00'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Settings hides deletes until minus; blank tap exits; export/import identify task',
    (tester) async {
      final client = _Client();
      final images = CoverImageService(client);
      final preferences = _Preferences(client, images);
      final backup = _Backup(
        client,
        ItemRepository(client, images),
        preferences,
        images,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SettingsScreen(
              repository: preferences,
              backup: backup,
              images: images,
              initialPreferences: const UserPreferences(),
              initialCategories: const ['游戏', '1'],
              onChanged: (_, categories) {},
              onDataChanged: () {},
            ),
          ),
        ),
      );
      expect(find.text('展柜壁纸'), findsNothing);
      expect(find.text('让展柜更像你'), findsNothing);
      expect(
        tester.getSize(find.byType(ControllerSymbols)),
        const Size(20, 20),
      );
      expect(find.byTooltip('删除游戏分类'), findsNothing);
      await tester.ensureVisible(find.byTooltip('删除分类'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除分类'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('删除游戏分类'), findsOneWidget);
      final chips = tester
          .widgetList<CategoryChip>(find.byType(CategoryChip))
          .toList();
      expect(chips.every((c) => c.onDeleted != null), isTrue);
      await tester.tapAt(const Offset(5, 100));
      await tester.pumpAndSettle();
      expect(find.byTooltip('删除游戏分类'), findsNothing);
      await tester.ensureVisible(find.text('导出备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出备份'));
      await tester.pump();
      expect(find.text('正在导出，请稍候...'), findsOneWidget);
      backup.exported.complete(null);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('导入备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导入备份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pump();
      expect(find.text('正在导入，请稍候...'), findsOneWidget);
      backup.imported.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('CNY card price and daily price use converted amount', (
    tester,
  ) async {
    final item = CollectionItem(
      id: '1',
      userId: 'a',
      name: 'Game',
      category: '游戏',
      createdAt: DateTime.now(),
      price: 100,
      currency: 'HKD',
      priceCny: 92,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 160,
            height: 200,
            child: CollectionCard(
              item: item,
              images: CoverImageService(_Client()),
              onTap: () {},
              priceDisplay: PriceDisplay.cny,
              preferences: const UserPreferences(
                showPrice: true,
                showDailyCost: true,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('¥92.00 · ¥92.00/天'), findsOneWidget);
  });

  testWidgets('Logout confirmation cancels without invoking sign out', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: IconButton(
              tooltip: '退出登录',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                if (await confirmAction(context, title: '确认要退出登录吗') == true) {
                  calls++;
                }
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('退出登录'));
    await tester.pumpAndSettle();
    expect(find.text('确认要退出登录吗'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byTooltip('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
}
