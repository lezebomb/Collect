import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:shou_cang_gui/harmony_media.dart';
import 'package:shou_cang_gui/harmony_support.dart';
import 'package:shou_cang_gui/services/ocr_service.dart';

/// Separate diagnostic entry point. The delivered app starts lib/main.dart.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: NativeSmokePage()));
}

class NativeSmokePage extends StatefulWidget {
  const NativeSmokePage({super.key});
  @override
  State<NativeSmokePage> createState() => _NativeSmokePageState();
}

class _NativeSmokePageState extends State<NativeSmokePage> {
  String status = 'Running native platform checks…';
  final results = <String, Object?>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => runChecks());
  }

  Future<void> check(String name, Future<void> Function() test) async {
    try {
      await test().timeout(
        Duration(seconds: name.startsWith('document_') ? 180 : 40),
      );
      results[name] = 'PASS';
    } catch (error) {
      if (name == 'system_ocr' && error.toString().contains('当前系统未提供文字识别服务')) {
        results[name] = 'UNAVAILABLE_IN_THIS_EMULATOR';
      } else {
        results[name] = 'FAIL: $error';
      }
    }
    if (mounted) {
      setState(
        () => status = const JsonEncoder.withIndent('  ').convert(results),
      );
    }
  }

  Future<void> runChecks() async {
    await registerHarmonyPlatform();
    final paths = await harmonyChannel.invokeMapMethod<String, String>('paths');
    final cache = paths!['cache']!;
    final files = paths['files']!;
    await check('private_storage', () async {
      final storage = HarmonyStorage('native-smoke');
      await Future.wait([
        storage.write('probe', 'first'),
        storage.write('probe', 'last'),
      ]);
      if (await HarmonyStorage('native-smoke').read('probe') != 'last') {
        throw StateError('Storage did not retain the last complete value');
      }
      await storage.write('probe', null);
    });
    Future<String> normalize(String path) async =>
        (await harmonyChannel.invokeMethod<String>('normalizeImage', {
          'path': path,
          'maxWidth': 2000,
          'maxHeight': 2000,
          'quality': 90,
        }))!;
    await check('jpeg_orientation', () async {
      final source = img.Image(width: 80, height: 40);
      img.fill(source, color: img.ColorRgb8(210, 40, 20));
      source.exif.imageIfd.orientation = 6;
      final file = File('$cache/smoke-rotated.jpg');
      await file.writeAsBytes(img.encodeJpg(source));
      final output = img.decodeImage(
        await File(await normalize(file.path)).readAsBytes(),
      )!;
      if (output.width != 40 || output.height != 80) {
        throw StateError(
          'Expected upright 40x80, got ${output.width}x${output.height}',
        );
      }
    });
    await check('png_transparency_and_recovery', () async {
      final source = img.Image(width: 40, height: 40, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(220, 30, 20, 64));
      final file = File('$cache/smoke-alpha.png');
      await file.writeAsBytes(img.encodePng(source));
      final path = await normalize(file.path);
      final output = img.decodeImage(await File(path).readAsBytes())!;
      if (!path.endsWith('.png') || output.getPixel(20, 20).a > 100) {
        throw StateError(
          'Transparent image became opaque: $path alpha=${output.getPixel(20, 20).a}',
        );
      }
      final marker = File('$files/pending-image.txt');
      await marker.writeAsString(path, flush: true);
      final recovered = await ImagePicker().retrieveLostData();
      if (recovered.files?.single.path != path || await marker.exists()) {
        throw StateError('Image recovery was not acknowledged');
      }
    });
    await check('system_ocr', () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      final paragraph =
          (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 90))
                ..pushStyle(ui.TextStyle(color: Colors.black))
                ..addText('Dearshelf 123'))
              .build()
            ..layout(const ui.ParagraphConstraints(width: 800));
      canvas.drawParagraph(paragraph, const Offset(24, 24));
      final picture = recorder.endRecording();
      final image = await picture.toImage(840, 180);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$cache/smoke-ocr.png');
      await file.writeAsBytes(data!.buffer.asUint8List());
      paragraph.dispose();
      picture.dispose();
      image.dispose();
      final lines = await OcrService().recognize(XFile(file.path));
      results['ocr_lines'] = lines;
      if (!lines.join(' ').toLowerCase().contains('dearshelf')) {
        throw StateError('Known text was not recognized');
      }
    });
    await saveReport();
  }

  Future<void> saveReport() async {
    final paths = await harmonyChannel.invokeMapMethod<String, String>('paths');
    final report = jsonEncode(results);
    await File(
      '${paths!['files']}/native-smoke.json',
    ).writeAsString(report, flush: true);
    debugPrint('DEARSHELF_NATIVE_SMOKE $report');
  }

  Future<void> testExport() async {
    await check('document_export', () async {
      final uri = await FilePicker.saveFile(
        fileName: 'dearshelf-native-probe-${DateTime.now().millisecondsSinceEpoch}.json',
        bytes: utf8.encode('{"dearshelf_native_probe":true}'),
        mimeType: 'application/json',
      );
      if (uri == null) throw StateError('Export was cancelled');
    });
    await saveReport();
  }

  Future<void> testImport() async {
    await check('document_import', () async {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null ||
          await file.readAsString() != '{"dearshelf_native_probe":true}') {
        throw StateError('Probe file did not round trip');
      }
    });
    await saveReport();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Native platform checks')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: testExport,
            child: const Text('Test document export'),
          ),
          FilledButton(
            onPressed: testImport,
            child: const Text('Test document import'),
          ),
        ],
      ),
    ),
  );
}
