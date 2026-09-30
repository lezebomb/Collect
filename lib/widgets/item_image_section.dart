import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/cover_image_service.dart';
import 'private_cover.dart';

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

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 1.7,
          child: preview != null
              ? Image.memory(preview!, fit: BoxFit.contain)
              : imageUrl != null
              ? PrivateCover(imageUrl: imageUrl, images: images)
              : const ColoredBox(
                  color: Color(0xFFE5EAE4),
                  child: Icon(Icons.add_photo_alternate_outlined, size: 54),
                ),
        ),
      ),
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
