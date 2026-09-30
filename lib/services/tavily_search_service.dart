import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog_candidate.dart';

// The API key stays in Supabase Secrets. The app sends only the search term
// and its current user session to the authenticated search function.
class TavilySearchService {
  TavilySearchService(this.client);

  final SupabaseClient client;
  final _cache = <String, List<CatalogCandidate>>{};

  Future<List<CatalogCandidate>> search(String query) async {
    final term = query.trim();
    final cached = _cache[term];
    if (cached != null) return cached;
    final response = await client.functions
        .invoke('catalog-search', body: {'query': term})
        .timeout(const Duration(seconds: 9));
    final data = response.data;
    if (data is! Map || data['candidates'] is! List) return [];
    final candidates = (data['candidates'] as List)
        .whereType<Map>()
        .map((item) {
          final image = item['image_url'];
          if (image is! String || Uri.tryParse(image)?.scheme != 'https') {
            return null;
          }
          return CatalogCandidate(
            title: item['title'] as String? ?? term,
            source: item['source'] as String? ?? 'Tavily',
            imageUrl: image,
            description: item['description'] as String? ?? '',
          );
        })
        .whereType<CatalogCandidate>()
        .toList();
    if (candidates.isNotEmpty) {
      if (_cache.length >= 20) _cache.remove(_cache.keys.first);
      _cache[term] = candidates;
    }
    return candidates;
  }
}
