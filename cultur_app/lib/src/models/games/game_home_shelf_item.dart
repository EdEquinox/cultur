import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

/// Row on games home shelves built from library tracking.
class GameHomeShelfItem {
  const GameHomeShelfItem({
    required this.tracking,
    required this.inPriority,
    required this.inWatchlist,
  });

  final TrackingItem tracking;
  final bool inPriority;
  final bool inWatchlist;

  CatalogItem get media => tracking.media;
}
