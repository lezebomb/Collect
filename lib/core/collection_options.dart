const gamePlatforms = <String>['Nintendo', 'PC'];
const gameContentTypes = <String>['本体', 'DLC', '本体+DLC'];
const gameEditions = <String>['实体版', '数字版'];
const gamePlayStatuses = <String>['吃灰中', '游玩中', '已通关', '全成就'];
const currencies = <String, String>{
  'CNY': '人民币 ¥',
  'USD': '美元 \$',
  'HKD': '港币 HK\$',
  'JPY': '日元 ¥',
  'EUR': '欧元 €',
  'GBP': '英镑 £',
};

String currencySymbol(String code) => switch (code) {
  'USD' => '\$',
  'HKD' => 'HK\$',
  'EUR' => '€',
  'GBP' => '£',
  _ => '¥',
};

String money(double value, String currency) =>
    '${currencySymbol(currency)}${value.toStringAsFixed(currency == 'JPY' ? 0 : 2)}';

String dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
