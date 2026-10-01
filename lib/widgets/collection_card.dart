import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/app_ui.dart';
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
  });

  final CollectionItem item;
  final CoverImageService images;
  final VoidCallback onTap;
  final UserPreferences preferences;

  @override
  Widget build(BuildContext context) => Container(
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
        splashColor: AppTheme.accent.withValues(alpha: .10),
        highlightColor: AppTheme.accent.withValues(alpha: .06),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PrivateCover(imageUrl: item.coverImage, images: images),
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
                          borderRadius: BorderRadius.circular(AppRadius.pill),
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
                  if ((preferences.showPrice || preferences.showDailyCost) &&
                      item.price != null) ...[
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        [
                          if (preferences.showPrice)
                            money(item.price!, item.currency),
                          if (preferences.showDailyCost)
                            '${money(item.price! / (item.ownedDays == 0 ? 1 : item.ownedDays), item.currency)}/天',
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
      ),
    ),
  );
}
