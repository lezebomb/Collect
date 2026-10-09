import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links_platform_interface/app_links_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'harmony_media.dart';

Future<void> registerHarmonyPlatform() async {
  final paths = await harmonyChannel.invokeMapMethod<String, String>('paths');
  if (paths == null || paths['files'] == null || paths['cache'] == null) {
    throw StateError('鸿蒙应用存储目录初始化失败');
  }
  PathProviderPlatform.instance = HarmonyPaths(paths);
  AppLinksPlatform.instance = HarmonyLinks();
}

class HarmonyPaths extends PathProviderPlatform {
  HarmonyPaths(this.paths);
  final Map<String, String> paths;
  @override
  Future<String?> getTemporaryPath() async => paths['cache'];
  @override
  Future<String?> getApplicationCachePath() async => paths['cache'];
  @override
  Future<String?> getApplicationDocumentsPath() async => paths['files'];
  @override
  Future<String?> getApplicationSupportPath() async => paths['files'];
  @override
  Future<String?> getLibraryPath() async => paths['files'];
}

class HarmonyLinks extends AppLinksPlatform {
  static const _events = EventChannel('app.dearshelf/links');
  late final Stream<String> _stream = _events
      .receiveBroadcastStream()
      .where((event) => event is String)
      .cast<String>();
  @override
  Stream<String> get stringLinkStream => _stream;
  @override
  Stream<Uri> get uriLinkStream => _stream.map(Uri.parse);
  @override
  Future<String?> getInitialLinkString() =>
      harmonyChannel.invokeMethod<String>('initialLink');
  @override
  Future<String?> getLatestLinkString() =>
      harmonyChannel.invokeMethod<String>('latestLink');
  @override
  Future<Uri?> getInitialLink() async {
    final link = await getInitialLinkString();
    return link == null ? null : Uri.parse(link);
  }

  @override
  Future<Uri?> getLatestLink() async {
    final link = await getLatestLinkString();
    return link == null ? null : Uri.parse(link);
  }
}

/// Session and PKCE verifier remain in the application's private sandbox.
class HarmonyStorage {
  HarmonyStorage(this.namespace);
  final String namespace;
  Future<void> _pending = Future<void>.value();
  Future<File> _file(String key) async {
    final root = await PathProviderPlatform.instance
        .getApplicationSupportPath();
    final directory = Directory('$root/auth/$namespace');
    await directory.create(recursive: true);
    return File('${directory.path}/${base64Url.encode(utf8.encode(key))}.json');
  }

  Future<String?> read(String key) async {
    await _pending;
    final file = await _file(key);
    return await file.exists() ? await file.readAsString() : null;
  }

  Future<void> write(String key, String? value) {
    final operation = _pending.catchError((Object _) {}).then((_) async {
      final file = await _file(key);
      if (value == null) {
        if (await file.exists()) await file.delete();
        return;
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(value, flush: true);
      await temporary.rename(file.path);
    });
    _pending = operation;
    return operation;
  }
}

class HarmonyAuthStorage extends LocalStorage {
  HarmonyAuthStorage();
  final _store = HarmonyStorage('session');
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() => _store.read('supabase');
  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write('supabase', persistSessionString);
  @override
  Future<void> removePersistedSession() => _store.write('supabase', null);
}

class HarmonyPkceStorage extends GotrueAsyncStorage {
  final _store = HarmonyStorage('pkce');
  @override
  Future<String?> getItem({required String key}) => _store.read(key);
  @override
  Future<void> setItem({required String key, required String value}) =>
      _store.write(key, value);
  @override
  Future<void> removeItem({required String key}) => _store.write(key, null);
}
