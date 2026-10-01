import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_ui.dart';

import '../services/cover_image_service.dart';
import 'private_cover.dart';
import 'selection_sheet.dart';

class ItemImageSection extends StatelessWidget {
  const ItemImageSection({
    super.key,
    required this.preview,
    required this.imageUrl,
    required this.images,
    required this.busy,
    required this.onGallery,
    required this.onCamera,
    required this.onRemove,
  });

  final Uint8List? preview;
  final String? imageUrl;
  final CoverImageService images;
  final bool busy;
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final VoidCallback onRemove;

  Future<void> _chooseCover(BuildContext context) async {
    final camera = await showSelectionSheet<bool>(
      context: context,
      title: '选择封面',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册选择'),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('拍照识别'),
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (camera != null) (camera ? onCamera : onGallery)();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Semantics(
        button: true,
        label: '选择封面',
        child: Material(
          borderRadius: BorderRadius.circular(AppRadius.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : () => _chooseCover(context),
            child: AspectRatio(
              aspectRatio: 1.7,
              child: preview != null
                  ? ColoredBox(
                      color: const Color(0xFFEFF1EC),
                      child: Image.memory(preview!, fit: BoxFit.contain),
                    )
                  : imageUrl != null
                  ? PrivateCover(imageUrl: imageUrl, images: images)
                  : const ColoredBox(
                      color: Color(0xFFE5EAE4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 40),
                          SizedBox(height: AppSpacing.sm),
                          Text('为收藏选一张封面'),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: busy ? null : onGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('选择图片'),
          ),
          TextButton.icon(
            onPressed: busy ? null : onCamera,
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('拍照识别'),
          ),
          if (preview != null || imageUrl != null)
            TextButton(
              onPressed: busy ? null : onRemove,
              child: const Text('移除图片'),
            ),
        ],
      ),
    ],
  );
}
