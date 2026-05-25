import 'package:flutter/material.dart';

import 'cultur_detail_action_row.dart';

class BoardgameActionRow extends StatelessWidget {
  const BoardgameActionRow({
    super.key,
    required this.isSaving,
    required this.isInLater,
    required this.isBuy,
    required this.isOwned,
    required this.rating,
    required this.onLaterTap,
    required this.onBuyTap,
    required this.onOwnedTap,
    required this.onRateTap,
    required this.onListsTap,
    this.below,
  });

  final bool isSaving;
  final bool isInLater;
  final bool isBuy;
  final bool isOwned;
  final double? rating;
  final VoidCallback onLaterTap;
  final VoidCallback onBuyTap;
  final VoidCallback onOwnedTap;
  final VoidCallback onRateTap;
  final VoidCallback onListsTap;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final r = rating;
    final hasRating = r != null && r.isFinite && r > 0;

    return CulturDetailActionRow(
      enabled: !isSaving,
      below: below,
      tiles: [
        CulturDetailActionTileSpec.toggle(
          selectedIcon: Icons.playlist_add,
          outlinedIcon: Icons.playlist_add_outlined,
          tooltip: 'Lists',
          selected: false,
          onTap: onListsTap,
          subtitle: 'Lists',
        ),
        CulturDetailActionTileSpec.toggle(
          selectedIcon: Icons.star,
          outlinedIcon: Icons.star_border_outlined,
          tooltip: hasRating ? 'Rating ${r.toStringAsFixed(1)}/10' : 'Rate',
          selected: hasRating,
          onTap: onRateTap,
          subtitle: hasRating ? '${r.toStringAsFixed(1)} / 10' : 'Rate',
        ),
        CulturDetailActionTileSpec.toggle(
          selectedIcon: Icons.bookmark,
          outlinedIcon: Icons.bookmark_border_outlined,
          tooltip: isInLater ? 'Remove from Later' : 'Add to Later',
          selected: isInLater,
          onTap: onLaterTap,
          subtitle: 'Later',
        ),
        CulturDetailActionTileSpec.toggle(
          selectedIcon: Icons.shopping_bag,
          outlinedIcon: Icons.shopping_bag_outlined,
          tooltip: isBuy ? 'Remove from Buy' : 'Add to Buy',
          selected: isBuy,
          onTap: onBuyTap,
          subtitle: 'Buy',
        ),
        CulturDetailActionTileSpec.toggle(
          selectedIcon: Icons.inventory_2,
          outlinedIcon: Icons.inventory_2_outlined,
          tooltip: isOwned ? 'Remove from Owned' : 'Mark as owned',
          selected: isOwned,
          onTap: onOwnedTap,
          subtitle: 'Owned',
        ),
      ],
    );
  }
}
