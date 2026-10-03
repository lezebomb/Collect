import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/price_display.dart';
import '../core/collection_snapshot.dart';

/// Device-local, account-scoped data; never changes cloud rows or backup format.
class LocalWorkspaceStore {
  LocalWorkspaceStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  final _snapshotWrites = <String, Future<void>>{};

  Future<File> _file(String owner, String name) async {
    if (owner.isEmpty) throw StateError('请先登录');
    final root = await _directory();
    final key = base64Url.encode(utf8.encode(owner));
    final folder = Directory('${root.path}/dearshelf/$key');
    await folder.create(recursive: true);
    return File('${folder.path}/$name.json');
  }

  Future<Map<String, dynamic>?> _read(String owner, String name) async {
    final file = await _file(owner, name);
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) throw const FormatException('本地数据格式异常');
    return value;
  }

  Future<void> _write(
    String owner,
    String name,
    Map<String, dynamic> data,
  ) async {
    final file = await _file(owner, name);
    final temporary = File('${file.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(data), flush: true);
      // Commit only the complete document; a failed write keeps the last draft.
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Map<String, dynamic>?> loadDraft(String owner) =>
      _read(owner, 'draft');
  Future<void> saveDraft(String owner, Map<String, dynamic> draft) =>
      _write(owner, 'draft', draft);
  Future<void> clearDraft(String owner) async {
    final file = await _file(owner, 'draft');
    if (await file.exists()) await file.delete();
  }

  Future<PriceDisplay> loadPriceDisplay(String owner) async =>
      (await _read(owner, 'display'))?['price_display'] == 'cny'
      ? PriceDisplay.cny
      : PriceDisplay.original;

  Future<void> savePriceDisplay(String owner, PriceDisplay display) =>
      _write(owner, 'display', {'price_display': display.name});

  Future<CollectionSnapshot?> loadCollectionSnapshot(String owner) async {
    final json = await _read(owner, 'collection-cache');
    return json == null ? null : CollectionSnapshot.fromJson(json, owner);
  }

  Future<void> saveCollectionSnapshot(String owner, CollectionSnapshot view) {
    // Serialize writes so a slower old write cannot replace a newer view.
    final previous = _snapshotWrites[owner] ?? Future<void>.value();
    final next = previous
        .catchError((Object _) {})
        .then((_) => _write(owner, 'collection-cache', view.toJson(owner)));
    _snapshotWrites[owner] = next;
    return next;
  }

  Future<void> clearCollectionSnapshot(String owner) async {
    await (_snapshotWrites[owner] ?? Future<void>.value()).catchError(
      (Object _) {},
    );
    final file = await _file(owner, 'collection-cache');
    if (await file.exists()) await file.delete();
  }
}
