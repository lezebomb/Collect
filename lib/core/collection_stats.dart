import '../models/collection_item.dart';

class CollectionStats {
  CollectionStats(this.items);

  final List<CollectionItem> items;

  double get totalInvestment =>
      items.fold(0, (sum, item) => sum + (item.priceCny ?? 0));
  List<CollectionItem> get inHand => items;
  double get inHandValue =>
      inHand.fold(0, (sum, item) => sum + (item.priceCny ?? 0));

  Map<String, int> get categoryCounts {
    final result = <String, int>{};
    for (final item in items) {
      result.update(item.category, (value) => value + 1, ifAbsent: () => 1);
    }
    return result;
  }

  Map<String, double> get categorySpending {
    final result = <String, double>{};
    for (final item in items) {
      result.update(
        item.category,
        (value) => value + (item.priceCny ?? 0),
        ifAbsent: () => item.priceCny ?? 0,
      );
    }
    return result;
  }

  Map<String, double> get monthlySpending {
    final result = <String, double>{};
    for (final item in items) {
      final date = item.purchaseDate ?? item.createdAt;
      final month = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      result.update(
        month,
        (value) => value + (item.priceCny ?? 0),
        ifAbsent: () => item.priceCny ?? 0,
      );
    }
    return result;
  }

  Map<String, int> get gameStatuses {
    final result = <String, int>{};
    for (final item in items.where((item) => item.isGame)) {
      final key = item.gamePlayStatus ?? '未设置';
      result.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
    return result;
  }
}
