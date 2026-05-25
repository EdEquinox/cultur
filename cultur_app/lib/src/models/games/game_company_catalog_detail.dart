import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/catalog/catalog_link.dart';

class GameCompanyCatalogItem {
  const GameCompanyCatalogItem({
    required this.media,
    this.roles = const [],
  });

  factory GameCompanyCatalogItem.fromJson(Map<String, dynamic> json) {
    final roles = (json['roles'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    return GameCompanyCatalogItem(
      media: CatalogItem.fromJson(
        (json['media'] as Map<String, dynamic>?) ?? const {},
      ),
      roles: roles,
    );
  }

  final CatalogItem media;
  final List<String> roles;
}

class GameCompanyCatalogDetail {
  const GameCompanyCatalogDetail({
    required this.companyId,
    required this.name,
    this.description,
    this.primaryRole,
    this.imageUrl,
    required this.catalog,
    required this.popularCatalog,
    required this.links,
  });

  factory GameCompanyCatalogDetail.fromJson(Map<String, dynamic> json) {
    List<GameCompanyCatalogItem> parseItems(String key) {
      return (json[key] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(GameCompanyCatalogItem.fromJson)
          .toList();
    }

    final links = (json['links'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogLink.fromJson)
        .toList();

    return GameCompanyCatalogDetail(
      companyId: json['companyId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      primaryRole: json['primaryRole']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      catalog: parseItems('catalog'),
      popularCatalog: parseItems('popularCatalog'),
      links: links,
    );
  }

  final String companyId;
  final String name;
  final String? description;
  final String? primaryRole;
  final String? imageUrl;
  final List<GameCompanyCatalogItem> catalog;
  final List<GameCompanyCatalogItem> popularCatalog;
  final List<CatalogLink> links;
}
