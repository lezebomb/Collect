// A small alias list for names that commonly differ across Chinese and English catalogs.
// Users can also enter another search term without changing their saved item name.
String? englishGameAlias(String query) {
  final term = query.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (term.contains('蕉力全开') || term.contains('蕉力全開')) {
    return 'Donkey Kong Bananza';
  }
  if (term.contains('咚奇刚') || term.contains('咚奇剛')) return 'Donkey Kong';
  if (term.contains('塞尔达') || term.contains('薩爾達')) {
    return 'The Legend of Zelda';
  }
  if (term.contains('马力欧') || term.contains('瑪利歐')) return 'Mario';
  if (term.contains('宝可梦') || term.contains('寶可夢')) return 'Pokemon';
  if (term.contains('星之卡比')) return 'Kirby';
  if (term.contains('动物森友会') || term.contains('動物森友會')) {
    return 'Animal Crossing';
  }
  if (term.contains('斯普拉遁') || term.contains('喷射战士')) return 'Splatoon';
  return null;
}
