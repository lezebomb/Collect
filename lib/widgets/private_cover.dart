import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
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
  Future<String?>? _signedUrl;
  bool _usingCachedFile = false;
  late Future<File?> _cachedFile = _lookupCachedFile();

  Future<File?> _lookupCachedFile() async {
    final url = widget.imageUrl;
    final images = widget.images;
    final file = await images.cachedCover(url);
    if (widget.imageUrl == url && identical(widget.images, images)) {
      _usingCachedFile = file != null;
    }
    return file;
  }

  @override
  void didUpdateWidget(covariant PrivateCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.images != widget.images ||
        (!_usingCachedFile &&
            !widget.images.hasFreshSignedUrl(widget.imageUrl))) {
      _usingCachedFile = false;
      _cachedFile = _lookupCachedFile();
      _signedUrl = null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    key: ValueKey(widget.imageUrl),
    future: _cachedFile,
    builder: (context, file) {
      if (file.data case final cached?) {
        return LayoutBuilder(
          builder: (context, constraints) => Image.file(
            cached,
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: constraints.maxWidth.isFinite
                ? (constraints.maxWidth *
                          MediaQuery.devicePixelRatioOf(context))
                      .round()
                      .clamp(1, 1600)
                : null,
            errorBuilder: (context, error, stack) => const _CoverPlaceholder(),
          ),
        );
      }
      if (file.connectionState != ConnectionState.done) {
        return const _CoverPlaceholder(loading: true);
      }
      return _network(context);
    },
  );

  Widget _network(BuildContext context) => FutureBuilder<String?>(
    future: _signedUrl ??= widget.images.signedUrl(widget.imageUrl),
    initialData: widget.images.cachedSignedUrl(widget.imageUrl),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done &&
          widget.imageUrl != null &&
          snapshot.data == null) {
        return const _CoverPlaceholder(loading: true);
      }
      final url = snapshot.data;
      if (url == null) return const _CoverPlaceholder();
      return LayoutBuilder(
        builder: (context, constraints) => CachedNetworkImage(
          imageUrl: url,
          cacheKey: widget.images.cacheKey(widget.imageUrl!),
          cacheManager: widget.images.imageCache,
          memCacheWidth: constraints.maxWidth.isFinite
              ? (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(1, 1600)
              : null,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => const _CoverPlaceholder(loading: true),
          errorWidget: (context, url, error) => const _CoverPlaceholder(),
        ),
      );
    },
  );
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({this.loading = false});
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFE5EAE4),
    alignment: Alignment.center,
    child: loading
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(
            Icons.auto_awesome_mosaic_rounded,
            color: AppTheme.muted,
            size: 42,
          ),
  );
}
