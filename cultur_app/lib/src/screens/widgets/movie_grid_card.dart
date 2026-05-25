import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/widgets/cards/cultur_grid_tile.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';

class MovieGridCard extends StatelessWidget {
  const MovieGridCard({
    required this.item,
    required this.tracking,
    required this.isSaving,
    super.key,
    this.onTap,
    this.onLongPress,
  });

  final CatalogItem item;
  final TrackingItem? tracking;
  final bool isSaving;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return CulturGridTile(
      content: CulturMediaCardContent.fromCatalog(item),
      style: CulturGridTileStyle.elevated,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
