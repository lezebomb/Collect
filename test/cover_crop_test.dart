import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shou_cang_gui/core/app_theme.dart';
import 'package:shou_cang_gui/core/cover_crop.dart';
import 'package:shou_cang_gui/screens/cover_crop_screen.dart';

void main() {
  test(
    'Landscape and portrait frames remain in source bounds at pan extremes',
    () {
      for (final image in [const Size(1200, 400), const Size(400, 1200)]) {
        for (final zoom in [1.0, 2.0, 6.0]) {
          for (final pan in [
            const Offset(-9999, -9999),
            Offset.zero,
            const Offset(9999, 9999),
          ]) {
            final rect = CoverFrame.sourceRect(
              image,
              const Size(270, 200),
              zoom,
              pan,
            );
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(image.width + .001));
            expect(rect.bottom, lessThanOrEqualTo(image.height + .001));
            expect(
              rect.width / rect.height,
              closeTo(CoverFrame.aspectRatio, .001),
            );
          }
        }
      }
    },
  );

  testWidgets(
    'Pan and zoom produce the selected pixels; reset and cancel work',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 100, 200),
          Paint()..color = Colors.red,
        );
        canvas.drawRect(
          const Rect.fromLTWH(100, 0, 100, 200),
          Paint()..color = Colors.green,
        );
        canvas.drawRect(
          const Rect.fromLTWH(200, 0, 100, 200),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(300, 200);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      Uint8List? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.push<Uint8List>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CoverCropScreen(bytes: bytes!),
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
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(3);
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('cover-crop-frame'))),
      );
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-500, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.tap(find.text('使用此封面'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(selected, isNotNull);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(selected!);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final center =
            ((frame.image.height ~/ 2) * frame.image.width +
                frame.image.width ~/ 2) *
            4;
        expect(data!.getUint8(center + 2), greaterThan(200));
        expect(data.getUint8(center), lessThan(100));
        expect(
          frame.image.width / frame.image.height,
          closeTo(CoverFrame.aspectRatio, .04),
        );
        frame.image.dispose();
        codec.dispose();
      });
      await tester.tap(find.text('打开'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final fullImage = tester.widget<Slider>(find.byType(Slider));
      fullImage.onChanged!(fullImage.min);
      await tester.pump();
      await tester.tap(find.text('使用此封面'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(selected!);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final row = (frame.image.height ~/ 2) * frame.image.width * 4;
        expect(data!.getUint8(row + 8), greaterThan(200));
        expect(
          data.getUint8(row + (frame.image.width - 3) * 4 + 2),
          greaterThan(200),
        );
        frame.image.dispose();
        codec.dispose();
      });
      await tester.tap(find.text('打开'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(4);
      await tester.pump();
      await tester.tap(find.text('重置'));
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 1);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    },
  );
}
