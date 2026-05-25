import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

/// Normalized media fields for shared card widgets (catalog, tracking, shelves).
class CulturMediaCardContent {
  const CulturMediaCardContent({
    required this.title,
    this.subtitle,
    this.description,
    this.imageUrl,
    this.mediaType,
  });

  final String title;
  final String? subtitle;
  final String? description;
  final String? imageUrl;

  /// e.g. `movie`, `tv` — used for placeholder icons.
  final String? mediaType;

  factory CulturMediaCardContent.fromCatalog(CatalogItem item) {
    return CulturMediaCardContent(
      title: item.title,
      subtitle: item.subtitle,
      description: item.description,
      imageUrl: item.imageUrl,
      mediaType: item.mediaType,
    );
  }

  factory CulturMediaCardContent.fromTracking(TrackingItem item) {
    return CulturMediaCardContent.fromCatalog(item.media);
  }

  /// IGDB game browse / search rows (never treat as movie for placeholders).
  factory CulturMediaCardContent.fromGameCatalog(CatalogItem item) {
    return CulturMediaCardContent(
      title: item.title,
      subtitle: catalogItemDirectorOrSubtitle(item),
      imageUrl: item.imageUrl,
      mediaType: 'game',
    );
  }
}
