class CatalogLink {
  const CatalogLink({required this.label, required this.url});

  factory CatalogLink.fromJson(Map<String, dynamic> json) {
    return CatalogLink(
      label: json['label']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }

  final String label;
  final String url;
}
