import 'package:yamtrack/src/models/catalog/catalog_item.dart';

class CustomMovieList {
  const CustomMovieList({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
  });

  factory CustomMovieList.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogItem.fromJson)
        .toList();
    return CustomMovieList(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled list',
      items: items,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  final String id;
  final String name;
  final List<CatalogItem> items;
  final String createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  CustomMovieList copyWith({
    String? id,
    String? name,
    List<CatalogItem>? items,
    String? createdAt,
  }) {
    return CustomMovieList(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
