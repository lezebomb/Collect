import 'package:flutter_test/flutter_test.dart';
import 'package:shou_cang_gui/core/collection_stats.dart';
import 'package:shou_cang_gui/models/collection_item.dart';

void main() {
  CollectionItem item(
    String id,
    String category,
    double cny, {
    String? playStatus,
    DateTime? purchaseDate,
  }) => CollectionItem(
    id: id,
    userId: 'user',
    name: id,
    category: category,
    createdAt: DateTime.utc(2026, 9, 30),
    price: cny,
    priceCny: cny,
    gamePlayStatus: playStatus,
    purchaseDate: purchaseDate,
  );

  test('spending, in-hand, category and game totals remain distinct', () {
    final stats = CollectionStats([
      item(
        'a',
        '游戏',
        100,
        playStatus: '游玩中',
        purchaseDate: DateTime(2026, 8, 1),
      ),
      item('b', '周边', 50, purchaseDate: DateTime(2026, 9, 1)),
      item('c', '游戏', 30, playStatus: '已通关'),
      item('d', '游戏', 999),
    ]);
    expect(stats.totalInvestment, 1179);
    expect(stats.inHand.length, 4);
    expect(stats.inHandValue, 1179);
    expect(stats.categoryCounts, {'游戏': 3, '周边': 1});
    expect(stats.categorySpending, {'游戏': 1129, '周边': 50});
    expect(stats.gameStatuses, {'游玩中': 1, '已通关': 1, '未设置': 1});
    expect(stats.monthlySpending['2026-08'], 100);
  });

  test('legacy records default to CNY and retain a usable value', () {
    final parsed = CollectionItem.fromJson({
      'id': 'item',
      'user_id': 'user',
      'name': '旧收藏',
      'category': '书籍',
      'price': 42,
      'created_at': '2026-09-30T00:00:00Z',
    });
    expect(parsed.currency, 'CNY');
    expect(parsed.priceCny, 42);
    expect(parsed.toUpdateJson()['price_cny'], 42);
  });
}
