import 'search_http.dart';

class CurrencyRateService {
  CurrencyRateService({SearchHttp? api}) : _api = api ?? const SearchHttp();
  final SearchHttp _api;

  Future<double> cnyRate(String currency) async {
    if (currency == 'CNY') return 1;
    final data = await _api.json(
      Uri.https('api.frankfurter.dev', '/v1/latest', {
        'base': currency,
        'symbols': 'CNY',
      }),
    );
    if (data is! Map<String, dynamic>) throw StateError('汇率暂时不可用');
    final rates = data['rates'] as Map<String, dynamic>?;
    final value = rates?['CNY'];
    if (value is! num) throw StateError('汇率暂时不可用');
    return value.toDouble();
  }
}
