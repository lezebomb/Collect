import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/catalog_candidate.dart';
import 'search_http.dart';
import 'search_terms.dart';

class GameSearchService {
  GameSearchService({SearchHttp? api}) : _api = api ?? const SearchHttp();

  final SearchHttp _api;
  Future<List<String>>? _switchTitles;

  Future<List<CatalogCandidate>> search(String query) async {
    final alias = englishGameAlias(query);
    final found = await Future.wait([
      _searchGameTdb(query).catchError((_) => <CatalogCandidate>[]),
      _searchCheapShark(query).catchError((_) => <CatalogCandidate>[]),
      _searchSteam(query).catchError((_) => <CatalogCandidate>[]),
      if (alias != null)
        _searchGameTdb(alias).catchError((_) => <CatalogCandidate>[]),
      if (alias != null)
        _searchCheapShark(alias).catchError((_) => <CatalogCandidate>[]),
    ]);
    return found.expand((part) => part).toList();
  }

  Future<List<String>> _loadSwitchTitles() async {
    final uri = Uri.https('www.gametdb.com', '/switchtdb.txt', {
      'LANG': 'ZHCN',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw StateError('GameTDB index unavailable');
    }
    return const LineSplitter().convert(utf8.decode(response.bodyBytes));
  }

  Future<List<CatalogCandidate>> _searchGameTdb(String query) async {
    late final List<String> lines;
    try {
      lines = await (_switchTitles ??= _loadSwitchTitles());
    } catch (_) {
      // Let the next search retry after a temporary network failure.
      _switchTitles = null;
      rethrow;
    }
    final term = normalizedTitle(query);
    final matches = <(String, String)>[];
    for (final line in lines) {
      final separator = line.indexOf(' = ');
      if (separator < 0) continue;
      final title = line.substring(separator + 3).trim();
      if (normalizedTitle(title).contains(term)) {
        matches.add((line.substring(0, separator), title));
      }
    }
    matches.sort((a, b) {
      final aExact = normalizedTitle(a.$2) == term ? 0 : 1;
      final bExact = normalizedTitle(b.$2) == term ? 0 : 1;
      return aExact.compareTo(bExact);
    });
    return matches
        .take(12)
        .map(
          (entry) => CatalogCandidate(
            title: entry.$2,
            source: 'GameTDB',
            imageUrl: Uri.https(
              'art.gametdb.com',
              '/switch/coverHQ/US/${entry.$1}.jpg',
            ).toString(),
            previewUrl: Uri.https(
              'art.gametdb.com',
              '/switch/coverM/US/${entry.$1}.jpg',
            ).toString(),
            officialTitle: true,
          ),
        )
        .toList();
  }

  Future<List<CatalogCandidate>> _searchCheapShark(String query) async {
    final data = await _api.json(
      Uri.https('www.cheapshark.com', '/api/1.0/games', {
        'title': query,
        'limit': '12',
      }),
    );
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .where((item) => item['thumb'] is String && item['external'] is String)
        .map(
          (item) => CatalogCandidate(
            title: item['external'] as String,
            source: 'CheapShark',
            imageUrl: item['thumb'] as String,
            officialTitle: true,
          ),
        )
        .toList();
  }

  Future<List<CatalogCandidate>> _searchSteam(String query) async {
    final data = await _api.json(
      Uri.https('store.steampowered.com', '/api/storesearch/', {
        'term': query,
        'l': 'schinese',
        'cc': 'cn',
      }),
      timeout: const Duration(seconds: 3),
    );
    if (data is! Map<String, dynamic>) return [];
    final raw = data['items'];
    if (raw is! List) return [];
    final items = raw.whereType<Map<String, dynamic>>().take(8).toList();
    return Future.wait(
      items.map((item) async {
        final id = item['id'];
        final name = item['name'];
        if (id is! int || name is! String) return null;
        var description = '';
        var imageUrl = item['tiny_image'] as String?;
        try {
          final details = await _api.json(
            Uri.https('store.steampowered.com', '/api/appdetails/', {
              'appids': '$id',
              'l': 'schinese',
              'cc': 'cn',
              'filters': 'basic',
            }),
            timeout: const Duration(seconds: 3),
          );
          final app =
              (details as Map<String, dynamic>?)?['$id']
                  as Map<String, dynamic>?;
          final info = app?['data'] as Map<String, dynamic>?;
          description =
              (info?['short_description'] as String?)
                  ?.replaceAll(RegExp(r'<[^>]*>'), '')
                  .trim() ??
              description;
          imageUrl = info?['header_image'] as String? ?? imageUrl;
        } catch (_) {}
        if (imageUrl == null) return null;
        return CatalogCandidate(
          title: name,
          source: 'Steam',
          description: description,
          imageUrl: imageUrl,
          officialTitle: true,
        );
      }),
    ).then((results) => results.whereType<CatalogCandidate>().toList());
  }
}
