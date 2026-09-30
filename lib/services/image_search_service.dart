import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/catalog_candidate.dart';
import 'search_http.dart';
import 'search_terms.dart';
import 'tavily_search_service.dart';

class ImageSearchService {
  ImageSearchService({SearchHttp? api, this.tavily})
    : _api = api ?? const SearchHttp();

  final SearchHttp _api;
  final TavilySearchService? tavily;
  final _pendingImages = <String, Future<XFile>>{};
  final _cachedImages = <String, (XFile, int)>{};
  var _cachedBytes = 0;

  Future<List<CatalogCandidate>> search(String query) async {
    final alias = englishGameAlias(query);
    final results = await Future.wait([
      if (tavily != null)
        tavily!.search(query).catchError((_) => <CatalogCandidate>[]),
      _searchOpenverse(query).catchError((_) => <CatalogCandidate>[]),
      _searchCommons(query).catchError((_) => <CatalogCandidate>[]),
      _searchBing(alias ?? query).catchError((_) => <CatalogCandidate>[]),
    ]);
    return results.expand((part) => part).toList();
  }

  Future<List<CatalogCandidate>> _searchBing(String query) async {
    final response = await http
        .get(
          Uri.https('global.bing.com', '/images/async', {
            'q': query,
            'first': '0',
            'count': '24',
            'adlt': 'moderate',
            // The regular entry redirects to a regional engine that can return
            // unrelated results. This image endpoint preserves the whole query.
            'mkt': 'en-US',
          }),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          },
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200 || response.bodyBytes.length > 1024 * 1024) {
      return [];
    }
    final page = utf8.decode(response.bodyBytes);
    final matches = RegExp(r'class="iusc"[^>]*\bm="([^"]+)"').allMatches(page);
    final results = <CatalogCandidate>[];
    for (final match in matches.take(24)) {
      try {
        final data = jsonDecode(
          _decodeAttribute(match.group(1)!),
        ) as Map<String, dynamic>;
        final image = data['murl'] as String?;
        if (image == null || Uri.tryParse(image)?.scheme != 'https') continue;
        final pageUrl = Uri.tryParse(data['purl'] as String? ?? '');
        results.add(
          CatalogCandidate(
            title: (data['t'] as String?)?.trim().isNotEmpty == true
                ? data['t'] as String
                : query,
            source: pageUrl?.host.isNotEmpty == true
                ? 'Bing 图片 · ${pageUrl!.host}'
                : 'Bing 图片',
            imageUrl: image,
            previewUrl: data['turl'] as String?,
          ),
        );
      } catch (_) {}
    }
    return results;
  }

  String _decodeAttribute(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  Future<List<CatalogCandidate>> _searchOpenverse(String query) async {
    final data = await _api.json(
      Uri.https('api.openverse.org', '/v1/images/', {
        'q': query,
        'page_size': '16',
      }),
    );
    if (data is! Map<String, dynamic>) return [];
    return (data['results'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final url = item['url'] as String?;
          if (url == null) return null;
          final title = (item['title'] as String?)?.trim();
          return CatalogCandidate(
            title: title == null || title.isEmpty ? query : title,
            source: 'Openverse',
            imageUrl: url,
            previewUrl: item['thumbnail'] as String?,
            // Attribution describes the image creator, not the collected item.
          );
        })
        .whereType<CatalogCandidate>()
        .toList();
  }

  Future<List<CatalogCandidate>> _searchCommons(String query) async {
    final data = await _api.json(
      Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': query,
        'gsrnamespace': '6',
        'gsrlimit': '12',
        'prop': 'imageinfo',
        'iiprop': 'url|extmetadata',
        'iiurlwidth': '500',
        'format': 'json',
      }),
    );
    if (data is! Map<String, dynamic>) return [];
    final pages =
        (data['query'] as Map<String, dynamic>?)?['pages']
            as Map<String, dynamic>? ??
        {};
    return pages.values
        .whereType<Map<String, dynamic>>()
        .map((page) {
          final infos = page['imageinfo'] as List<dynamic>?;
          final info = infos?.firstOrNull as Map<String, dynamic>?;
          final url = info?['thumburl'] as String?;
          if (url == null) return null;
          final metadata = info?['extmetadata'] as Map<String, dynamic>?;
          final raw = metadata?['ImageDescription'] as Map<String, dynamic>?;
          return CatalogCandidate(
            title: (page['title'] as String? ?? query)
                .replaceFirst('File:', '')
                .replaceAll(RegExp(r'\.[^.]+$'), '')
                .replaceAll('_', ' '),
            source: 'Wikimedia Commons',
            imageUrl: url,
            previewUrl: url,
            description: (raw?['value'] as String? ?? '')
                .replaceAll(RegExp(r'<[^>]*>'), ' ')
                .trim(),
          );
        })
        .whereType<CatalogCandidate>()
        .toList();
  }

  Future<XFile> download(CatalogCandidate candidate) async {
    try {
      return await _downloadUrl(candidate.imageUrl);
    } catch (_) {
      final preview = candidate.previewUrl;
      if (preview == null || preview == candidate.imageUrl) rethrow;
      return _downloadUrl(preview);
    }
  }

  Future<Uint8List> previewBytes(CatalogCandidate candidate) async {
    final image = await _downloadUrl(
      candidate.previewUrl ?? candidate.imageUrl,
    );
    return image.readAsBytes();
  }

  Future<XFile> _downloadUrl(String url) async {
    final cached = _cachedImages[url];
    if (cached != null) return cached.$1;
    final pending = _pendingImages[url];
    if (pending != null) return pending;
    final future = _fetchImage(url);
    _pendingImages[url] = future;
    try {
      final image = await future;
      final length = await image.length();
      const cacheLimit = 32 * 1024 * 1024;
      while (_cachedBytes + length > cacheLimit && _cachedImages.isNotEmpty) {
        final removed = _cachedImages.remove(_cachedImages.keys.first)!;
        _cachedBytes -= removed.$2;
      }
      _cachedImages[url] = (image, length);
      _cachedBytes += length;
      return image;
    } finally {
      _pendingImages.remove(url);
    }
  }

  Future<XFile> _fetchImage(String url) async {
    final response = await http
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'Collect/1.0 (https://github.com/lezebomb/Collect)',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 10 * 1024 * 1024) {
      throw StateError('图片下载失败（HTTP ${response.statusCode}）');
    }
    final type = response.headers['content-type'] ?? '';
    final ext = type.contains('png')
        ? 'png'
        : type.contains('webp')
        ? 'webp'
        : type.contains('jpeg') || type.contains('jpg')
        ? 'jpg'
        : null;
    if (ext == null) throw StateError('请选择 JPG、PNG 或 WebP 图片');
    return XFile.fromData(
      response.bodyBytes,
      name: 'catalog.$ext',
      mimeType: 'image/${ext == 'jpg' ? 'jpeg' : ext}',
    );
  }
}
