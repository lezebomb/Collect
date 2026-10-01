import '../models/collection_item.dart';

enum PriceDisplay { original, cny }

({double? amount, String currency}) displayedPrice(
  CollectionItem item,
  PriceDisplay display,
) => display == PriceDisplay.cny
    ? (
        amount: item.priceCny ?? (item.currency == 'CNY' ? item.price : null),
        currency: 'CNY',
      )
    : (amount: item.price, currency: item.currency);
