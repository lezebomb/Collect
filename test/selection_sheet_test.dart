import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shou_cang_gui/core/app_theme.dart';
import 'package:shou_cang_gui/widgets/selection_sheet.dart';

void main() {
  for (final size in [const Size(360, 800), const Size(320, 568)]) {
    for (final count in [2, 7, 40]) {
      testWidgets('Full-width sheet $size with $count options', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? selection;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selection = await showSelectionSheet<String>(
                      context: context,
                      title: '选择分类',
                      builder: (context) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < count; i++)
                            SelectionOption(
                              label: '分类 $i',
                              onTap: () => Navigator.pop(context, '$i'),
                            ),
                        ],
                      ),
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
        final sheet = tester.getRect(find.byType(BottomSheet));
        expect(sheet.width, size.width);
        expect(sheet.height, greaterThanOrEqualTo(size.height / 3 - 1));
        expect(sheet.height, lessThanOrEqualTo(size.height * .87));
        expect(tester.takeException(), isNull);
        if (count == 2) {
          tester.view.physicalSize = Size(size.height, size.width);
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(BottomSheet)).width, size.height);
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(find.text('分类 ${count - 1}'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('分类 ${count - 1}'));
        await tester.pumpAndSettle();
        expect(selection, '${count - 1}');
      });
    }
  }

  testWidgets('Large labels wrap on a landscape screen', (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longLabel = '原币种显示，保留每件藏品的 CNY、HKD、USD 及其他购入货币';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSelectionSheet<void>(
                context: context,
                title: '选择价格展示形式',
                builder: (_) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SelectionOption(label: longLabel, onTap: () {}),
                    SelectionOption(label: 'CNY 折算金额', onTap: () {}),
                  ],
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final label = tester.renderObject<RenderParagraph>(find.text(longLabel));
    expect(label.didExceedMaxLines, isFalse);
    expect(label.overflow, isNot(TextOverflow.ellipsis));
    await tester.ensureVisible(find.text('CNY 折算金额'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Image sheet can scroll a long heading at large text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSelectionSheet<void>(
                context: context,
                heightFraction: .78,
                scrollable: false,
                builder: (_) => CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Text('为“${'很长的搜索关键词' * 12}”选择图片'),
                    ),
                    const SliverToBoxAdapter(child: Text('候选图片')),
                  ],
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('候选图片'),
      200,
      scrollable: find.descendant(
        of: find.byType(SelectionSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
