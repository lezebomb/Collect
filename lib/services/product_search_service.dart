import '../models/catalog_candidate.dart';
import 'search_http.dart';

class ProductSearchService {
  ProductSearchService({SearchHttp? api}) : _api = api ?? const SearchHttp();

  final SearchHttp _api;

  Future<List<CatalogCandidate>> search(String query) async {
    final results = await Future.wait([
      _searchGoogleBooks(query).catchError((_) => <CatalogCandidate>[]),
      _searchOpenLibrary(query).catchError((_) => <CatalogCandidate>[]),
    ]);
    return results.expand((part) => part).toList();
  }

  Future<List<CatalogCandidate>> _searchGoogleBooks(String query) async {
    final data = await _api.json(
      Uri.https('www.googleapis.com', '/books/v1/volumes', {
        'q': query,
        'maxResults': '8',
        'printType': 'books',
      }),
    );
    if (data is! Map<String, dynamic>) return [];
    return (data['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final info = item['volumeInfo'] as Map<String, dynamic>?;
          final images = info?['imageLinks'] as Map<String, dynamic>?;
          final image = images?['thumbnail'] as String?;
          final title = info?['title'] as String?;
          if (image == null || title == null) return null;
          return CatalogCandidate(
            title: title,
            source: 'Google Books',
            imageUrl: image.replaceFirst('http://', 'https://'),
            description: (info?['description'] as String? ?? '')
                .replaceAll(RegExp(r'<[^>]*>'), '')
                .trim(),
            officialTitle: true,
          );
        })
        .whereType<CatalogCandidate>()
        .toList();
  }

  Future<List<CatalogCandidate>> _searchOpenLibrary(String query) async {
    final data = await _api.json(
      Uri.https('openlibrary.org', '/search.json', {
        'q': query,
        'limit': '8',
        'fields': 'title,cover_i,first_publish_year,author_name',
      }),
    );
    if (data is! Map<String, dynamic>) return [];
    return (data['docs'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final id = item['cover_i'];
          final title = item['title'];
          if (id is! int || title is! String) return null;
          final authors = (item['author_name'] as List<dynamic>? ?? [])
              .take(2)
              .join('、');
          final year = item['first_publish_year'];
          return CatalogCandidate(
            title: title,
            source: 'Open Library',
            imageUrl: 'https://covers.openlibrary.org/b/id/$id-L.jpg',
            previewUrl: 'https://covers.openlibrary.org/b/id/$id-M.jpg',
            description: [
              if (authors.isNotEmpty) authors,
              if (year != null) '$year 年出版',
            ].join(' · '),
            officialTitle: true,
          );
        })
        .whereType<CatalogCandidate>()
        .toList();
  }
}
