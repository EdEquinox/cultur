import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/widgets/cards/cultur_grid_tile.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';

class LibraryGridCard extends StatelessWidget {
  const LibraryGridCard({
    required this.item,
    super.key,
    this.onTap,
    this.onLongPress,
  });

  final TrackingItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return CulturGridTile(
      content: CulturMediaCardContent.fromTracking(item),
      style: CulturGridTileStyle.flat,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
