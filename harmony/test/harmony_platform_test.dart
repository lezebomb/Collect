import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shou_cang_gui/harmony_media.dart';
import 'package:shou_cang_gui/harmony_support.dart';
import 'package:shou_cang_gui/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory sandbox;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('dearshelf-harmony-test-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = HarmonyPaths({
      'files': sandbox.path,
      'cache': sandbox.path,
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(harmonyChannel, null);
    PathProviderPlatform.instance = previousPaths;
    await sandbox.delete(recursive: true);
  });

  test(
    'session survives a new storage instance and logout removes it',
    () async {
      final first = HarmonyAuthStorage();
      await first.initialize();
      expect(await first.hasAccessToken(), false);
      await first.persistSession('{"access_token":"test-only"}');
      final restarted = HarmonyAuthStorage();
      expect(await restarted.accessToken(), '{"access_token":"test-only"}');
      await restarted.removePersistedSession();
      expect(await HarmonyAuthStorage().hasAccessToken(), false);
    },
  );

  test('PKCE verifier is durable and isolated from session data', () async {
    final pkce = HarmonyPkceStorage();
    final session = HarmonyAuthStorage();
    await pkce.setItem(key: '../../supabase', value: 'verifier');
    await session.persistSession('session');
    expect(
      await HarmonyPkceStorage().getItem(key: '../../supabase'),
      'verifier',
    );
    await pkce.removeItem(key: '../../supabase');
    expect(await session.accessToken(), 'session');
  });

  test('serialized writes preserve the latest complete session', () async {
    final storage = HarmonyAuthStorage();
    await Future.wait([
      storage.persistSession('first'),
      storage.persistSession('second'),
      storage.persistSession('last'),
    ]);
    expect(await HarmonyAuthStorage().accessToken(), 'last');
  });

  test('cancelling gallery and file pickers changes no files', () async {
    messenger.setMockMethodCallHandler(harmonyChannel, (call) async {
      if (call.method == 'pickFiles') return <String>[];
      if (call.method == 'pickImage') return null;
      throw StateError('Unexpected call: ${call.method}');
    });
    expect(await ImagePicker().pickImage(source: ImageSource.gallery), null);
    expect(await FilePicker.pickFile(), null);
    expect(await FilePicker.pickFiles(), isEmpty);
  });

  test(
    'export transfers bytes by private file and cleans up on success',
    () async {
      String? temporaryPath;
      messenger.setMockMethodCallHandler(harmonyChannel, (call) async {
        expect(call.method, 'saveFile');
        final arguments = call.arguments as Map;
        expect(arguments.containsKey('bytes'), false);
        temporaryPath = arguments['path'] as String;
        expect(await File(temporaryPath!).readAsBytes(), [0x50, 0x4b, 1, 2]);
        return 'file://test/Collect.zip';
      });
      final uri = await FilePicker.saveFile(
        fileName: 'Collect.zip',
        bytes: Uint8List.fromList([0x50, 0x4b, 1, 2]),
      );
      expect(uri.toString(), 'file://test/Collect.zip');
      expect(await File(temporaryPath!).exists(), false);
    },
  );

  test('export also cleans up when the system picker fails', () async {
    String? temporaryPath;
    messenger.setMockMethodCallHandler(harmonyChannel, (call) async {
      temporaryPath = (call.arguments as Map)['path'] as String;
      throw PlatformException(code: 'PICKER_FAILED');
    });
    await expectLater(
      FilePicker.saveFile(
        fileName: 'Collect.zip',
        bytes: Uint8List.fromList([1]),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(await File(temporaryPath!).exists(), false);
  });

  test('OCR preserves useful unique lines and bounds the results', () async {
    messenger.setMockMethodCallHandler(harmonyChannel, (call) async {
      expect(call.method, 'recognizeText');
      return [
        '  游戏名称  ',
        '游戏名称',
        'a',
        'x' * 81,
        ...List.generate(20, (index) => '有效文字$index'),
      ];
    });
    final lines = await OcrService().recognize(
      XFile('${sandbox.path}/photo.jpg'),
    );
    expect(lines.first, '游戏名称');
    expect(lines.length, 12);
    expect(lines.toSet().length, 12);
  });

  test('successful image pick acknowledges recovery after receipt', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(harmonyChannel, (call) async {
      calls.add(call.method);
      return call.method == 'pickImage' ? '${sandbox.path}/cover.jpg' : null;
    });
    final image = await ImagePicker().pickImage(source: ImageSource.camera);
    expect(image!.path, '${sandbox.path}/cover.jpg');
    expect(calls, ['pickImage', 'consumeImage']);
  });
}
