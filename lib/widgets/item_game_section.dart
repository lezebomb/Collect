import 'package:flutter/material.dart';

import '../core/collection_options.dart';
import '../core/app_ui.dart';

class ItemGameSection extends StatelessWidget {
  const ItemGameSection({
    super.key,
    required this.platform,
    required this.contentType,
    required this.edition,
    required this.playStatus,
    required this.busy,
    required this.onPlatform,
    required this.onContentType,
    required this.onEdition,
    required this.onPlayStatus,
  });

  final String? platform;
  final String? contentType;
  final String? edition;
  final String? playStatus;
  final bool busy;
  final ValueChanged<String?> onPlatform;
  final ValueChanged<String?> onContentType;
  final ValueChanged<String?> onEdition;
  final ValueChanged<String?> onPlayStatus;

  Widget _choice(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    isExpanded: true,
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: values
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: busy ? null : onChanged,
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _choice('平台', platform, gamePlatforms, onPlatform),
      const SizedBox(height: AppSpacing.md),
      _choice('内容类型', contentType, gameContentTypes, onContentType),
      const SizedBox(height: AppSpacing.md),
      _choice('版本类型', edition, gameEditions, onEdition),
      const SizedBox(height: AppSpacing.md),
      _choice('游玩状态', playStatus, gamePlayStatuses, onPlayStatus),
    ],
  );
}
