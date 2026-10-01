import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/app_ui.dart';
import '../core/price_display.dart';
import '../models/collection_item.dart';
import '../models/user_preferences.dart';
import '../core/collection_options.dart';
import '../services/cover_image_service.dart';
import 'private_cover.dart';
import 'adaptive_card_text.dart';

class CollectionCard extends StatelessWidget {
  const CollectionCard({
    super.key,
    required this.item,
    required this.images,
    required this.onTap,
    required this.preferences,
    this.priceDisplay = PriceDisplay.original,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  final CollectionItem item;
  final CoverImageService images;
  final VoidCallback onTap;
  final UserPreferences preferences;
  final PriceDisplay priceDisplay;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selectionMode ? selected : null,
    child: Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        boxShadow: AppCardStyle.shadows,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          splashColor: AppTheme.accent.withValues(alpha: .10),
          highlightColor: AppTheme.accent.withValues(alpha: .06),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: const Color(0xFFEFF1EC),
                          child: PrivateCover(
                            imageUrl: item.coverImage,
                            images: images,
                            fit: BoxFit.contain,
                          ),
                        ),
                        if (preferences.showOwnedDays)
                          Positioned(
                            right: 9,
                            top: 9,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .9),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                '${item.ownedDays} 天',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                          ),
                        if (selectionMode)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 26,
                                color: selected
                                    ? AppTheme.accent
                                    : AppTheme.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdaptiveCardText(
                          item.name,
                          style: const TextStyle(
                            color: AppTheme.ink,
                            fontSize: 14,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            item.category,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if ((preferences.showPrice ||
                                preferences.showDailyCost) &&
                            item.price != null) ...[
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              [
                                if (preferences.showPrice)
                                  displayedPrice(item, priceDisplay).amount ==
                                          null
                                      ? 'CNY 未折算'
                                      : money(
                                          displayedPrice(
                                            item,
                                            priceDisplay,
                                          ).amount!,
                                          displayedPrice(
                                            item,
                                            priceDisplay,
                                          ).currency,
                                        ),
                                if (preferences.showDailyCost)
                                  displayedPrice(item, priceDisplay).amount ==
                                          null
                                      ? '日均价格未折算'
                                      : '${money(displayedPrice(item, priceDisplay).amount! / (item.ownedDays == 0 ? 1 : item.ownedDays), displayedPrice(item, priceDisplay).currency)}/天',
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.25,
                                color: AppTheme.muted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (selectionMode && selected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.accent, width: 2),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
