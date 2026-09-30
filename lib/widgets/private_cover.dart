import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/cover_image_service.dart';

class PrivateCover extends StatefulWidget {
  const PrivateCover({
    super.key,
    required this.imageUrl,
    required this.images,
    this.fit = BoxFit.cover,
  });

  final String? imageUrl;
  final CoverImageService images;
  final BoxFit fit;

  @override
  State<PrivateCover> createState() => _PrivateCoverState();
}

class _PrivateCoverState extends State<PrivateCover> {
  late Future<String?> _signedUrl = widget.images.signedUrl(widget.imageUrl);

  @override
  void didUpdateWidget(covariant PrivateCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _signedUrl = widget.images.signedUrl(widget.imageUrl);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _signedUrl,
    builder: (context, snapshot) {
      final url = snapshot.data;
      if (url == null) return const _CoverPlaceholder();
      return Image.network(
        url,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => const _CoverPlaceholder(),
      );
    },
  );
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFE5EAE4),
    alignment: Alignment.center,
    child: const Icon(
      Icons.auto_awesome_mosaic_rounded,
      color: AppTheme.muted,
      size: 42,
    ),
  );
}
