import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_card.dart';

class PosterWallCard extends StatelessWidget {
  const PosterWallCard({
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
    return CulturPosterCard(
      content: CulturMediaCardContent.fromCatalog(item),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
