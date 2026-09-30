import 'dart:convert';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CatalogResult {
  const CatalogResult({
    required this.name,
    required this.description,
    required this.source,
    this.imageUrl,
    this.englishName,
  });
  final String name;
  final String description;
  final String source;
  final String? imageUrl;
  final String? englishName;
}

class CatalogImage {
  const CatalogImage({
    required this.title,
    required this.source,
    required this.imageUrl,
    this.previewUrl,
    this.description = '',
    this.productTitle = false,
  });

  final String title;
  final String source;
  final String imageUrl;
  final String? previewUrl;
  final String description;
  final bool productTitle;
}

class CatalogService {
  Future<List<String>>? _switchTitles;

  Future<List<CatalogImage>> searchImages(
    String query, {
    String? category,
  }) async {
    final term = query.trim();
    if (term.runes.length < 2) {
      throw const FormatException('至少输入两个字再搜索图片');
    }
    final results = <CatalogImage>[];
    final generalFuture = Future.wait([
      _searchOpenverse(term).catchError((_) => <CatalogImage>[]),
      _searchCommons(term).catchError((_) => <CatalogImage>[]),
      _searchBooks(term).catchError((_) => <CatalogImage>[]),
    ]);
    if (category == '游戏') {
      final directFuture = Future.wait([
        _searchGameTdb(term).catchError((_) => <CatalogImage>[]),
        _searchCheapShark(term).catchError((_) => <CatalogImage>[]),
      ]);
      final names = <String>[term];
      try {
        final items = await _searchWikidata(term);
        names.addAll(
          items
              .map((item) => item.englishName ?? '')
              .where((name) => name.isNotEmpty)
              .take(3),
        );
      } catch (_) {}
      results.addAll((await directFuture).expand((items) => items));
      final distinct = names.toSet().skip(1).take(2).toList();
      final games = await Future.wait(
        distinct.map((name) async {
          final found = await Future.wait([
            _searchGameTdb(name).catchError((_) => <CatalogImage>[]),
            _searchCheapShark(name).catchError((_) => <CatalogImage>[]),
          ]);
          return found.expand((items) => items).toList();
        }),
      );
      results.addAll(games.expand((items) => items));
    }
    final general = await generalFuture;
    results.addAll(general.expand((items) => items));
    final unique = <String, CatalogImage>{};
    for (final image in results) {
      unique.putIfAbsent(image.imageUrl, () => image);
    }
    return unique.values.take(40).toList();
  }

  Future<List<CatalogImage>> _searchCheapShark(String query) async {
    final uri = Uri.https('www.cheapshark.com', '/api/1.0/games', {
      'title': query,
      'limit': '12',
    });
    final response = await http
        .get(
          uri,
          headers: {'User-Agent': 'Collect/1.0 (personal collection app)'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return [];
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((item) => item['thumb'] is String && item['external'] is String)
        .map(
          (item) => CatalogImage(
            title: item['external'] as String,
            source: 'CheapShark',
            imageUrl: item['thumb'] as String,
            productTitle: true,
          ),
        )
        .toList();
  }

  Future<List<String>> _loadSwitchTitles() async {
    final uri = Uri.https('www.gametdb.com', '/switchtdb.txt', {
      'LANG': 'ZHCN',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return [];
    return const LineSplitter().convert(utf8.decode(response.bodyBytes));
  }

  Future<List<CatalogImage>> _searchGameTdb(String query) async {
    final lines = await (_switchTitles ??= _loadSwitchTitles());
    final term = _normalized(query);
    if (term.isEmpty) return [];
    final matches = <(String, String)>[];
    for (final line in lines) {
      final separator = line.indexOf(' = ');
      if (separator < 0) continue;
      final id = line.substring(0, separator);
      final title = line.substring(separator + 3).trim();
      if (_normalized(title).contains(term)) matches.add((id, title));
    }
    matches.sort((a, b) {
      final aExact = _normalized(a.$2) == term ? 0 : 1;
      final bExact = _normalized(b.$2) == term ? 0 : 1;
      return aExact.compareTo(bExact);
    });
    final candidates = matches.take(12).map((entry) {
      final path = '/switch/coverHQ/US/${entry.$1}.jpg';
      return CatalogImage(
        title: entry.$2,
        source: 'GameTDB',
        imageUrl: Uri.https('art.gametdb.com', path).toString(),
        previewUrl: Uri.https(
          'art.gametdb.com',
          '/switch/coverM/US/${entry.$1}.jpg',
        ).toString(),
        productTitle: true,
      );
    }).toList();
    final checked = await Future.wait(
      candidates.map((candidate) async {
        try {
          final response = await http
              .head(Uri.parse(candidate.previewUrl!))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 &&
              (response.headers['content-type'] ?? '').startsWith('image/')) {
            return candidate;
          }
        } catch (_) {}
        return null;
      }),
    );
    return checked.whereType<CatalogImage>().toList();
  }

  Future<List<CatalogImage>> _searchOpenverse(String query) async {
    final uri = Uri.https('api.openverse.org', '/v1/images/', {
      'q': query,
      'page_size': '12',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return [];
    final root =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = (root['results'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return items
        .where((item) => item['url'] is String)
        .map(
          (item) => CatalogImage(
            title: (item['title'] as String?)?.trim().isNotEmpty == true
                ? item['title'] as String
                : query,
            source: 'Openverse',
            imageUrl: item['url'] as String,
            previewUrl: item['thumbnail'] as String?,
            description: item['attribution'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<List<CatalogImage>> _searchCommons(String query) async {
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'generator': 'search',
      'gsrsearch': query,
      'gsrnamespace': '6',
      'gsrlimit': '12',
      'prop': 'imageinfo',
      'iiprop': 'url',
      'iiurlwidth': '400',
      'format': 'json',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return [];
    final root =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final pages =
        (root['query'] as Map<String, dynamic>?)?['pages']
            as Map<String, dynamic>? ??
        <String, dynamic>{};
    return pages.values
        .map((raw) {
          final page = raw as Map<String, dynamic>;
          final info =
              (page['imageinfo'] as List<dynamic>?)?.firstOrNull
                  as Map<String, dynamic>?;
          final imageUrl = info?['thumburl'] as String?;
          if (imageUrl == null) return null;
          return CatalogImage(
            title: (page['title'] as String)
                .replaceFirst('File:', '')
                .replaceAll(RegExp(r'\.[^.]+$'), '')
                .replaceAll('_', ' '),
            source: 'Wikimedia Commons',
            imageUrl: imageUrl,
            previewUrl: imageUrl,
          );
        })
        .whereType<CatalogImage>()
        .toList();
  }

  Future<List<CatalogImage>> _searchBooks(String query) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': query,
      'limit': '8',
      'fields': 'title,cover_i,first_publish_year',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return [];
    final root =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (root['docs'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((item) => item['cover_i'] is int && item['title'] is String)
        .map((item) {
          final id = item['cover_i'] as int;
          return CatalogImage(
            title: item['title'] as String,
            source: 'Open Library',
            imageUrl: 'https://covers.openlibrary.org/b/id/$id-L.jpg',
            previewUrl: 'https://covers.openlibrary.org/b/id/$id-M.jpg',
            productTitle: true,
          );
        })
        .toList();
  }

  Future<List<CatalogResult>> search(String query, {String? category}) async {
    final trimmed = query.trim();
    if (trimmed.runes.length < 2) {
      throw const FormatException('至少输入两个字再搜索物品');
    }
    final searches = await Future.wait([
      _searchWikidata(trimmed).catchError((_) => <CatalogResult>[]),
      _searchWikipedia(trimmed).catchError((_) => <CatalogResult>[]),
    ]);
    final unique = <String, CatalogResult>{};
    for (final result in searches.expand((items) => items)) {
      final key = _normalized(result.name);
      final existing = unique[key];
      if (existing == null ||
          (existing.imageUrl == null && result.imageUrl != null)) {
        unique[key] = result;
      }
    }
    final results = unique.values.toList()
      ..sort(
        (a, b) => _score(
          b,
          trimmed,
          category,
        ).compareTo(_score(a, trimmed, category)),
      );
    return results.take(10).toList();
  }

  static String _normalized(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );

  static int _score(CatalogResult result, String query, String? category) {
    final title = _normalized(result.name);
    final term = _normalized(query);
    var score = result.imageUrl == null ? 0 : 100;
    if (title == term) {
      score += 100;
    } else if (title.startsWith(term)) {
      score += 60;
    } else if (title.contains(term)) {
      score += 35;
    }
    if (result.source == '维基数据') score += 15;
    if (category == '游戏' &&
        RegExp(
          r'游戏|遊戲|game',
          caseSensitive: false,
        ).hasMatch(result.description)) {
      score += 20;
    }
    return score;
  }

  Future<List<CatalogResult>> _searchWikidata(String query) async {
    final searchUri = Uri.https('www.wikidata.org', '/w/api.php', {
      'action': 'wbsearchentities',
      'search': query,
      'language': 'zh',
      'uselang': 'zh',
      'type': 'item',
      'limit': '10',
      'format': 'json',
    });
    final response = await http
        .get(searchUri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw StateError('物品目录暂时不可用');
    final root =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final matches = (root['search'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    if (matches.isEmpty) return [];
    final ids = matches.map((match) => match['id'] as String).join('|');
    final detailUri = Uri.https('www.wikidata.org', '/w/api.php', {
      'action': 'wbgetentities',
      'ids': ids,
      'props': 'claims|labels',
      'languages': 'en|zh',
      'format': 'json',
    });
    final detailResponse = await http
        .get(detailUri)
        .timeout(const Duration(seconds: 12));
    final entities = detailResponse.statusCode == 200
        ? (jsonDecode(utf8.decode(detailResponse.bodyBytes))
                      as Map<String, dynamic>)['entities']
                  as Map<String, dynamic>? ??
              <String, dynamic>{}
        : <String, dynamic>{};
    return matches
        .map((match) {
          final id = match['id'] as String;
          final entity = entities[id] as Map<String, dynamic>?;
          final labels = entity?['labels'] as Map<String, dynamic>?;
          final englishLabel = labels?['en'] as Map<String, dynamic>?;
          final claims = entity?['claims'] as Map<String, dynamic>?;
          final images = claims?['P18'] as List<dynamic>?;
          final first = images?.firstOrNull as Map<String, dynamic>?;
          final snak = first?['mainsnak'] as Map<String, dynamic>?;
          final data = snak?['datavalue'] as Map<String, dynamic>?;
          final filename = data?['value'] as String?;
          final label =
              (match['display'] as Map<String, dynamic>?)?['label']
                  as Map<String, dynamic>?;
          final description =
              (match['display'] as Map<String, dynamic>?)?['description']
                  as Map<String, dynamic>?;
          return CatalogResult(
            name:
                (label?['value'] as String?) ??
                (match['label'] as String? ?? ''),
            description:
                (description?['value'] as String?) ??
                (match['description'] as String? ?? ''),
            source: '维基数据',
            englishName: englishLabel?['value'] as String?,
            imageUrl: filename == null
                ? null
                : Uri.https(
                    'commons.wikimedia.org',
                    '/wiki/Special:Redirect/file/$filename',
                    {'width': '500'},
                  ).toString(),
          );
        })
        .where((item) => item.name.isNotEmpty)
        .toList();
  }

  Future<List<CatalogResult>> _searchWikipedia(String query) async {
    final uri = Uri.https('zh.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'generator': 'search',
      'gsrsearch': query,
      'gsrlimit': '15',
      'prop': 'pageimages|extracts',
      'pithumbsize': '600',
      'exintro': '1',
      'explaintext': '1',
      'exchars': '100',
      'format': 'json',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw StateError('资料搜索服务暂时不可用');
    final root =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final pages =
        (root['query'] as Map<String, dynamic>?)?['pages']
            as Map<String, dynamic>?;
    if (pages == null) return [];
    return pages.values
        .map((raw) {
          final page = raw as Map<String, dynamic>;
          final thumbnail = page['thumbnail'] as Map<String, dynamic>?;
          return CatalogResult(
            name: page['title'] as String,
            description: (page['extract'] as String?) ?? '',
            source: '维基百科',
            imageUrl: thumbnail?['source'] as String?,
          );
        })
        .where((item) {
          final title = _normalized(item.name);
          return title.contains(_normalized(query)) &&
              !RegExp(r'新闻|新聞|报道|報道|评测|評測|销量|銷量|预告|預告').hasMatch(item.name);
        })
        .toList();
  }

  Future<XFile> coverFile(String url) async {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 10 * 1024 * 1024) {
      throw StateError('封面下载失败');
    }
    final type = response.headers['content-type'] ?? '';
    if (!type.contains('image/jpeg') &&
        !type.contains('image/png') &&
        !type.contains('image/webp')) {
      throw StateError('该条目没有可用的 JPG、PNG 或 WebP 封面');
    }
    final ext = type.contains('png')
        ? 'png'
        : type.contains('webp')
        ? 'webp'
        : 'jpg';
    return XFile.fromData(
      response.bodyBytes,
      name: 'catalog.$ext',
      mimeType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
    );
  }

  Future<List<String>> recognize(XFile photo) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      return result.blocks
          .expand((block) => block.lines)
          .map((line) => line.text.trim())
          .where((line) => line.length >= 2 && line.length <= 80)
          .toSet()
          .take(12)
          .toList();
    } finally {
      await recognizer.close();
    }
  }

  Future<double> cnyRate(String currency) async {
    if (currency == 'CNY') return 1;
    final uri = Uri.https('api.frankfurter.dev', '/v1/latest', {
      'base': currency,
      'symbols': 'CNY',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw StateError('汇率暂时不可用');
    final root = jsonDecode(response.body) as Map<String, dynamic>;
    final rates = root['rates'] as Map<String, dynamic>;
    return (rates['CNY'] as num).toDouble();
  }
}
