import '../core/collection_options.dart';

class CollectionItem {
  const CollectionItem({
    required this.id,
    required this.userId,
    required this.name,
    required this.category,
    required this.createdAt,
    this.coverImage,
    this.description = '',
    this.purchaseDate,
    this.price,
    this.currency = 'CNY',
    this.priceCny,
    this.gamePlatform,
    this.gameContentType,
    this.gameEdition,
    this.gamePlayStatus,
  });

  final String id;
  final String userId;
  final String name;
  final String category;
  final String? coverImage;
  final String description;
  final DateTime? purchaseDate;
  final double? price;
  final String currency;
  final double? priceCny;
  final String? gamePlatform;
  final String? gameContentType;
  final String? gameEdition;
  final String? gamePlayStatus;
  final DateTime createdAt;

  bool get isGame => category == '游戏';
  int get ownedDays {
    final start = purchaseDate ?? createdAt;
    final today = DateTime.now();
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(today.year, today.month, today.day);
    return b.difference(a).inDays < 0 ? 0 : b.difference(a).inDays;
  }

  factory CollectionItem.fromJson(Map<String, dynamic> json) => CollectionItem(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    name: json['name'] as String,
    category: json['category'] as String,
    coverImage: json['cover_image'] as String?,
    description: (json['description'] as String?) ?? '',
    purchaseDate: json['purchase_date'] == null
        ? null
        : DateTime.parse(json['purchase_date'] as String),
    price: (json['price'] as num?)?.toDouble(),
    currency: (json['currency'] as String?) ?? 'CNY',
    priceCny:
        (json['price_cny'] as num?)?.toDouble() ??
        ((json['currency'] == null || json['currency'] == 'CNY')
            ? (json['price'] as num?)?.toDouble()
            : null),
    gamePlatform: json['game_platform'] as String?,
    gameContentType: json['game_content_type'] as String?,
    gameEdition: json['game_edition'] as String?,
    gamePlayStatus: json['game_play_status'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toCreateJson() => {
    'id': id,
    'user_id': userId,
    'created_at': createdAt.toUtc().toIso8601String(),
    ...toUpdateJson(),
  };

  Map<String, dynamic> toUpdateJson() => {
    'name': name.trim(),
    'category': category,
    'cover_image': coverImage,
    'description': description.trim(),
    'purchase_date': purchaseDate == null ? null : dateOnly(purchaseDate!),
    'price': price,
    'currency': currency,
    'price_cny': price == null ? null : (currency == 'CNY' ? price : priceCny),
    'game_platform': isGame ? gamePlatform : null,
    'game_content_type': isGame ? gameContentType : null,
    'game_edition': isGame ? gameEdition : null,
    'game_play_status': isGame ? gamePlayStatus : null,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };
}
