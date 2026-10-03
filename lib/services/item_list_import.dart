import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/collection_options.dart';
import '../models/collection_item.dart';

/// Plain JSON lists for entering collections in bulk, not archive backups.
class ItemListImport {
  static const maxItems = 500;
  static const maxFileBytes = 5 * 1024 * 1024;
  static const template = '''{
  "format": "dearshelf-item-list",
  "version": 1,
  "items": [
    {
      "name": "My favorite game",
      "category": "游戏",
      "description": "A little story about this favorite.",
      "purchase_date": "2026-10-03",
      "price": 68,
      "currency": "CNY",
      "game_platform": "PC",
      "game_content_type": "本体",
      "game_play_status": "游玩中"
    },
    {
      "name": "A special keepsake",
      "category": "纪念品",
      "description": "Where I found it."
    }
  ]
}''';

  static List<CollectionItem> parse(
    Map<String, String> files, {
    required String owner,
    DateTime? now,
  }) {
    if (owner.isEmpty) throw StateError('请先登录');
    final result = <CollectionItem>[];
    for (final file in files.entries) {
      try {
        final text = file.value.replaceFirst(RegExp(r'^\uFEFF'), '');
        final root = jsonDecode(text);
        if (root is! Map ||
            root['format'] != 'dearshelf-item-list' ||
            root['version'] != 1 ||
            root['items'] is! List) {
          throw const FormatException('请使用 Dearshelf 藏品清单模板');
        }
        final rows = root['items'] as List;
        if (rows.isEmpty) throw const FormatException('藏品清单为空');
        for (var i = 0; i < rows.length; i++) {
          if (result.length >= maxItems) {
            throw const FormatException('每次最多导入 500 件藏品');
          }
          try {
            result.add(
              _item(
                rows[i],
                owner,
                (now ?? DateTime.now()).toUtc().add(
                  Duration(microseconds: result.length),
                ),
              ),
            );
          } on FormatException catch (e) {
            throw FormatException('第 ${i + 1} 件：${e.message}');
          }
        }
      } on FormatException catch (e) {
        throw FormatException('${file.key}：${e.message}');
      }
    }
    return result;
  }

  static CollectionItem _item(dynamic raw, String owner, DateTime created) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('藏品应为 JSON 对象');
    }
    const fields = {
      'name',
      'category',
      'description',
      'purchase_date',
      'price',
      'currency',
      'price_cny',
      'game_platform',
      'game_content_type',
      'game_edition',
      'game_play_status',
    };
    if (raw.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('含不支持的字段，请检查拼写；封面请在导入后添加');
    }
    String? text(String key, {int? max}) {
      final value = raw[key];
      if (value == null) return null;
      if (value is! String || (max != null && value.trim().length > max)) {
        throw FormatException('$key 格式或长度无效');
      }
      return value.trim();
    }

    String requiredText(String key, int max) {
      final value = text(key, max: max);
      if (value == null || value.isEmpty) throw FormatException('请填写 $key');
      return value;
    }

    double? amount(String key) {
      final value = raw[key];
      if (value == null) return null;
      if (value is! num ||
          !value.isFinite ||
          value < 0 ||
          value > 9999999999.99) {
        throw FormatException('$key 应为有效的非负数字');
      }
      return value.toDouble();
    }

    String? option(String key, List<String> values) {
      final value = text(key);
      if (value != null && !values.contains(value)) {
        throw FormatException('$key 选项无效');
      }
      return value;
    }

    final category = requiredText('category', 60);
    final currency = text('currency') ?? 'CNY';
    if (!currencies.containsKey(currency)) {
      throw const FormatException('currency 币种不支持');
    }
    final price = amount('price');
    final cny = amount('price_cny');
    if (price != null && currency != 'CNY' && cny == null) {
      throw const FormatException('外币价格需同时填写 price_cny 人民币折算金额');
    }
    final dateText = text('purchase_date');
    final date = dateText == null ? null : DateTime.tryParse(dateText);
    if (dateText != null &&
        (date == null ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateText) ||
            dateOnly(date) != dateText ||
            date.year < 1950 ||
            date.year > DateTime.now().year + 1)) {
      throw const FormatException('purchase_date 应为有效的 YYYY-MM-DD 日期');
    }
    final platform = option('game_platform', gamePlatforms);
    final content = option('game_content_type', gameContentTypes);
    final edition = option('game_edition', gameEditions);
    final status = option('game_play_status', gamePlayStatuses);
    if (category != '游戏' &&
        [platform, content, edition, status].any((v) => v != null)) {
      throw const FormatException('游戏字段只用于“游戏”分类');
    }
    return CollectionItem(
      id: const Uuid().v4(),
      userId: owner,
      name: requiredText('name', 120),
      category: category,
      description: text('description', max: 10000) ?? '',
      purchaseDate: date,
      price: price,
      currency: currency,
      priceCny: currency == 'CNY' ? price : cny,
      gamePlatform: platform,
      gameContentType: content,
      gameEdition: platform == 'PC' ? '数字版' : edition,
      gamePlayStatus: status,
      createdAt: created,
    );
  }
}
