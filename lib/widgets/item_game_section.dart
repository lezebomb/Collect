import 'package:flutter/material.dart';

import '../core/collection_options.dart';

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
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: values
        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
        .toList(),
    onChanged: busy ? null : onChanged,
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 14),
      _choice('平台', platform, gamePlatforms, onPlatform),
      const SizedBox(height: 14),
      _choice('内容类型', contentType, gameContentTypes, onContentType),
      const SizedBox(height: 14),
      _choice('版本类型', edition, gameEditions, onEdition),
      const SizedBox(height: 14),
      _choice('游玩状态', playStatus, gamePlayStatuses, onPlayStatus),
    ],
  );
}
