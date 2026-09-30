import 'dart:convert';

import 'package:http/http.dart' as http;

class SearchHttp {
  const SearchHttp();

  Future<dynamic> json(
    Uri uri, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final response = await http
        .get(
          uri,
          headers: {'User-Agent': 'Collect/1.0 (personal collection app)'},
        )
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}

String normalizedTitle(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
