import '../models/collection_item.dart';
import '../models/user_preferences.dart';

/// A disposable local view, separate from the user's drafts and backup format.
class CollectionSnapshot {
  const CollectionSnapshot({
    required this.items,
    required this.preferences,
    required this.categories,
  });

  final List<CollectionItem> items;
  final UserPreferences preferences;
  final List<String> categories;

  Map<String, dynamic> toJson(String owner) => {
    'version': 1,
    'owner': owner,
    'items': items.map(itemJson).toList(),
    'preferences': preferences.toJson(),
    'categories': categories,
  };

  factory CollectionSnapshot.fromJson(Map<String, dynamic> json, String owner) {
    if (json['version'] != 1 || json['owner'] != owner) {
      throw const FormatException('收藏缓存版本或账号不匹配');
    }
    final items = (json['items'] as List)
        .map(
          (v) => CollectionItem.fromJson(Map<String, dynamic>.from(v as Map)),
        )
        .toList();
    if (items.any((item) => item.userId != owner)) {
      throw const FormatException('收藏缓存账号不匹配');
    }
    return CollectionSnapshot(
      items: List.unmodifiable(items),
      preferences: UserPreferences.fromJson(
        Map<String, dynamic>.from(json['preferences'] as Map),
      ),
      categories: List<String>.unmodifiable(json['categories'] as List),
    );
  }

  // Serialize the view without the write-model's trimming or game-field reset.
  static Map<String, dynamic> itemJson(CollectionItem item) => {
    'id': item.id,
    'user_id': item.userId,
    'name': item.name,
    'category': item.category,
    'created_at': item.createdAt.toIso8601String(),
    'cover_image': item.coverImage,
    'description': item.description,
    'purchase_date': item.purchaseDate?.toIso8601String(),
    'price': item.price,
    'currency': item.currency,
    'price_cny': item.priceCny,
    'game_platform': item.gamePlatform,
    'game_content_type': item.gameContentType,
    'game_edition': item.gameEdition,
    'game_play_status': item.gamePlayStatus,
  };

  static CollectionItem withCategory(CollectionItem item, String category) =>
      CollectionItem.fromJson({...itemJson(item), 'category': category});
}
