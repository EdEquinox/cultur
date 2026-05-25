/// Label/value pair on catalog detail screens (movies, TV, games, …).
class CatalogDetailMetric {
  const CatalogDetailMetric({required this.label, required this.value});

  factory CatalogDetailMetric.fromJson(Map<String, dynamic> json) {
    return CatalogDetailMetric(
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
    );
  }

  final String label;
  final String value;
}
