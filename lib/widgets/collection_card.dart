import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/collection_item.dart';
import '../models/user_preferences.dart';
import '../core/collection_options.dart';
import '../services/cover_image_service.dart';
import 'private_cover.dart';

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
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
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
                    child: Chip(
                      label: Text('${item.ownedDays} 天'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.category,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
                if ((preferences.showPrice || preferences.showDailyCost) &&
                    item.price != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (preferences.showPrice)
                        Expanded(
                          child: Text(
                            money(item.price!, item.currency),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      if (preferences.showDailyCost)
                        Text(
                          '${money(item.price! / (item.ownedDays == 0 ? 1 : item.ownedDays), item.currency)}/天',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.muted,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
