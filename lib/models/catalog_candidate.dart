class CatalogCandidate {
  const CatalogCandidate({
    required this.title,
    required this.source,
    required this.imageUrl,
    this.previewUrl,
    this.description = '',
    this.officialTitle = false,
  });

  final String title;
  final String source;
  final String imageUrl;
  final String? previewUrl;
  final String description;
  final bool officialTitle;
}
