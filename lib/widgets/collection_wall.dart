import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/price_display.dart';
import '../models/collection_item.dart';
import '../models/user_preferences.dart';
import '../services/cover_image_service.dart';
import 'category_chip.dart';
import 'collection_card.dart';

class CollectionWall extends StatelessWidget {
  const CollectionWall({
    super.key,
    required this.items,
    required this.total,
    required this.categories,
    required this.category,
    required this.preferences,
    required this.images,
    required this.search,
    required this.searchExpanded,
    required this.onSearch,
    required this.onCloseSearch,
    required this.onCategory,
    required this.onOpen,
    required this.onRefresh,
    this.priceDisplay = PriceDisplay.original,
    this.onLongPress,
    this.onManage,
    this.selectionMode = false,
    this.selectedIds = const {},
  });
  final List<CollectionItem> items;
  final int total;
  final List<String> categories;
  final String? category;
  final UserPreferences preferences;
  final PriceDisplay priceDisplay;
  final CoverImageService images;
  final TextEditingController search;
  final bool searchExpanded;
  final VoidCallback onSearch;
  final VoidCallback onCloseSearch;
  final ValueChanged<String?> onCategory;
  final ValueChanged<CollectionItem> onOpen;
  final Future<void> Function() onRefresh;
  final ValueChanged<CollectionItem>? onLongPress;
  final VoidCallback? onManage;
  final bool selectionMode;
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 800
          ? 4
          : constraints.maxWidth >= 600
          ? 3
          : 2;
      final width = (constraints.maxWidth - 32 - (columns - 1) * 8) / columns;
      final scale = math.max(
        1.0,
        MediaQuery.textScalerOf(context).scale(14) / 14,
      );
      final price =
          (preferences.showPrice || preferences.showDailyCost) &&
          items.any((i) => i.price != null);
      final textHeight = (price ? 82.0 : 66.0) * scale;
      final headerHeight = selectionMode ? 40 : 86 + (searchExpanded ? 64 : 0);
      // Fit three rows when practical; large accessibility text keeps enough cover space.
      final desired = (constraints.maxHeight - headerHeight - 16 - 16) / 3;
      final cardHeight = math.max(
        width * .52 + textHeight,
        math.min(width * .83 + textHeight, desired),
      );
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          key: const PageStorageKey('collection-wall'),
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (searchExpanded && !selectionMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: search,
                    autofocus: true,
                    onChanged: (_) => onSearch(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索我的收藏',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: '收起搜索',
                        onPressed: onCloseSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ),
                ),
              ),
            if (!selectionMode)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48 + (scale - 1) * 13,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    itemCount: categories.length + 1,
                    separatorBuilder: (_, index) => const SizedBox(width: 8),
                    itemBuilder: (_, index) => CategoryChip(
                      label: index == 0 ? '全部' : categories[index - 1],
                      selected: index == 0
                          ? category == null
                          : category == categories[index - 1],
                      onTap: () =>
                          onCategory(index == 0 ? null : categories[index - 1]),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectionMode
                            ? '当前列表 ${items.length} 件 · 点选藏品'
                            : '${items.length} / $total 件收藏',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                    if (!selectionMode && onManage != null && items.isNotEmpty)
                      TextButton.icon(
                        onPressed: onManage,
                        icon: const Icon(Icons.checklist_rounded, size: 16),
                        label: const Text('批量管理'),
                        style: TextButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 12),
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      total == 0 ? '收藏柜还是空的，点击 + 添加第一件收藏' : '没有符合条件的物品',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverGrid.builder(
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: cardHeight,
                  ),
                  itemBuilder: (_, index) => CollectionCard(
                    key: ValueKey(items[index].id),
                    item: items[index],
                    images: images,
                    preferences: preferences,
                    priceDisplay: priceDisplay,
                    onTap: () => onOpen(items[index]),
                    onLongPress: onLongPress == null
                        ? null
                        : () => onLongPress!(items[index]),
                    selectionMode: selectionMode,
                    selected: selectedIds.contains(items[index].id),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
