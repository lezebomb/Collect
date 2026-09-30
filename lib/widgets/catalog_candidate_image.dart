import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/catalog_candidate.dart';
import '../services/image_search_service.dart';

// Preview and selection use the same downloaded bytes. A visible candidate can
// be selected without a second request to a slow or restricted image host.
class CatalogCandidateImage extends StatefulWidget {
  const CatalogCandidateImage({
    super.key,
    required this.candidate,
    required this.images,
  });

  final CatalogCandidate candidate;
  final ImageSearchService images;

  @override
  State<CatalogCandidateImage> createState() => _CatalogCandidateImageState();
}

class _CatalogCandidateImageState extends State<CatalogCandidateImage> {
  late Future<Uint8List> _bytes = widget.images.previewBytes(widget.candidate);

  @override
  void didUpdateWidget(CatalogCandidateImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.candidate.imageUrl != widget.candidate.imageUrl ||
        oldWidget.candidate.previewUrl != widget.candidate.previewUrl) {
      _bytes = widget.images.previewBytes(widget.candidate);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Icon(Icons.broken_image_outlined));
      }
      final bytes = snapshot.data;
      if (bytes == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    },
  );
}
