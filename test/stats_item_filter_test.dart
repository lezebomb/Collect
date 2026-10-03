import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shou_cang_gui/core/app_theme.dart';
import 'package:shou_cang_gui/models/collection_item.dart';
import 'package:shou_cang_gui/screens/stats_screen.dart';
import 'package:shou_cang_gui/widgets/monthly_spending_chart.dart';
import 'package:shou_cang_gui/widgets/stats_item_selection.dart';

CollectionItem item(
  String id,
  String name,
  double price, {
  int year = 2026,
  String category = '数码产品',
}) => CollectionItem(
  id: id,
  userId: 'owner',
  name: name,
  category: category,
  priceCny: price,
  purchaseDate: DateTime(year, 3),
  createdAt: DateTime(year, 3),
);

final fixtures = [
  item('computer', '电脑', 5000),
  item('phone', '手机', 2000),
  item('band', '手环', 280),
  item('old-phone', '手机', 1000, year: 2025),
  item('game', '游戏', 100, category: '游戏'),
];

Widget app(GlobalKey<StatsScreenState> key, List<CollectionItem> items) =>
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        appBar: AppBar(
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
            IconButton(
              tooltip: '筛选藏品',
              icon: const Icon(Icons.checklist_rounded),
              onPressed: () => key.currentState!.chooseItems(),
            ),
          ],
        ),
        body: StatsScreen(key: key, items: items),
      ),
    );

Finder summary(String text) => find.descendant(
  of: find.ancestor(of: find.text('藏品价值'), matching: find.byType(Card)).first,
  matching: find.text(text),
);

Future<void> choose(WidgetTester tester, String tooltip, String value) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(BottomSheet), matching: find.text(value)),
  );
  await tester.pumpAndSettle();
}

Future<void> openItems(WidgetTester tester) async {
  await tester.tap(find.byTooltip('筛选藏品'));
  await tester.pumpAndSettle();
}

Future<void> apply(WidgetTester tester) async {
  await tester.tap(find.text('应用筛选'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Individual exclusions update totals, counts and cross-year monthly curve; cancel is safe',
    (tester) async {
      final key = GlobalKey<StatsScreenState>();
      await tester.pumpWidget(app(key, fixtures));
      await tester.pumpAndSettle();
      await choose(tester, '筛选分类', '数码产品');
      expect(summary('¥8280.00'), findsOneWidget);
      await openItems(tester);
      expect(find.text('已选 4 / 4 件'), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-item-game')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('stats-item-computer')));
      await tester.pump();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(summary('¥8280.00'), findsOneWidget);
      await openItems(tester);
      await tester.tap(find.byKey(const ValueKey('stats-item-computer')));
      await apply(tester);
      expect(summary('¥3280.00'), findsOneWidget);
      expect(summary('3 件物品'), findsOneWidget);
      await choose(tester, '筛选年份', '2026 年');
      expect(summary('¥2280.00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(MonthlySpendingChart),
        200,
        scrollable: find
            .descendant(
              of: find.byType(StatsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final chart = tester.widget<MonthlySpendingChart>(
        find.byType(MonthlySpendingChart),
      );
      expect(chart.values, {'2025-03': 1000.0, '2026-03': 2280.0});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'All-none is zero; IDs distinguish equal names; category change resets selection',
    (tester) async {
      final key = GlobalKey<StatsScreenState>();
      await tester.pumpWidget(app(key, fixtures));
      await tester.pumpAndSettle();
      await choose(tester, '筛选分类', '数码产品');
      await openItems(tester);
      await tester.tap(find.byKey(const ValueKey('stats-item-phone')));
      await apply(tester);
      expect(summary('¥6280.00'), findsOneWidget);
      await openItems(tester);
      await tester.tap(find.text('全不选'));
      await apply(tester);
      expect(summary('¥0.00'), findsOneWidget);
      expect(summary('0 件物品'), findsOneWidget);
      await tester.tap(find.text('恢复全部'));
      await tester.pumpAndSettle();
      expect(summary('¥8280.00'), findsOneWidget);
      await openItems(tester);
      await tester.tap(find.text('全不选'));
      await apply(tester);
      await choose(tester, '筛选分类', '游戏');
      expect(summary('¥100.00'), findsOneWidget);
      await choose(tester, '筛选分类', '数码产品');
      expect(summary('¥8280.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Refresh retains exclusions by ID and includes newly added items; deleted exclusions expire',
    (tester) async {
      final key = GlobalKey<StatsScreenState>();
      await tester.pumpWidget(app(key, fixtures));
      await tester.pumpAndSettle();
      await choose(tester, '筛选分类', '数码产品');
      await openItems(tester);
      await tester.tap(find.byKey(const ValueKey('stats-item-computer')));
      await apply(tester);
      final updated = [...fixtures, item('new', '新藏品', 20)];
      await tester.pumpWidget(app(key, updated));
      await tester.pumpAndSettle();
      expect(summary('¥3300.00'), findsOneWidget);
      await tester.pumpWidget(
        app(key, updated.where((i) => i.id != 'computer').toList()),
      );
      await tester.pumpAndSettle();
      expect(find.text('恢复全部'), findsNothing);
      await tester.pumpWidget(app(key, updated));
      await tester.pumpAndSettle();
      expect(summary('¥8300.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Long names and large text remain usable in the selection sheet on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: SizedBox(
                height: 420,
                child: StatsItemSelection(
                  items: [
                    item('long', '这是一件有很长很长名称的数码收藏品它的名称应该完整显示在选择框中', 280),
                  ],
                  excludedIds: const {},
                  scope: '数码产品 · 全部年份',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('全不选'));
      await tester.pump();
      expect(find.text('已选 0 / 1 件'), findsOneWidget);
      expect(find.text('应用筛选'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
