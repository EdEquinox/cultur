import 'package:flutter/material.dart';

import 'cultur_detail_action_row.dart';

/// Primary tracking actions on a game detail page (aligned with game library tabs).
class GameActionRow extends StatelessWidget {
  const GameActionRow({
    super.key,
    required this.isSaving,
    required this.isInLater,
    required this.isPlaying,
    required this.isPlayed,
    required this.isBuy,
    required this.isOwned,
    required this.isDropped,
    required this.rating,
    required this.onLaterTap,
    required this.onPlayingTap,
    required this.onBuyTap,
    required this.onOwnedTap,
    required this.onRateTap,
    required this.onListsTap,
    this.below,
  });

  final bool isSaving;
  final bool isInLater;
  final bool isPlaying;
  final bool isPlayed;
  final bool isBuy;
  final bool isOwned;
  final bool isDropped;
  final double? rating;
  final VoidCallback onLaterTap;
  final VoidCallback onPlayingTap;
  final VoidCallback onBuyTap;
  final VoidCallback onOwnedTap;
  final VoidCallback onRateTap;
  final VoidCallback onListsTap;
  final Widget? below;

  ({IconData icon, IconData outlined, String tooltip, bool selected, String subtitle}) _playingTile() {
    if (isPlayed) {
      return (
        icon: Icons.check_circle,
        outlined: Icons.check_circle_outline,
        tooltip: 'Played — tap to play again',
        selected: true,
        subtitle: 'Played',
      );
    }
    if (isDropped) {
      return (
        icon: Icons.flag,
        outlined: Icons.flag_outlined,
        tooltip: 'Dropped — tap to play again',
        selected: true,
        subtitle: 'Dropped',
      );
    }
    if (isPlaying) {
      return (
        icon: Icons.stop_circle,
        outlined: Icons.stop_circle_outlined,
        tooltip: 'Playing — finish, drop, or pause',
        selected: true,
        subtitle: 'Playing',
      );
    }
    return (
      icon: Icons.sports_esports,
      outlined: Icons.sports_esports_outlined,
      tooltip: 'Mark as playing',
      selected: false,
      subtitle: 'Playing',
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = rating;
    final hasRating = r != null && r.isFinite && r > 0;
    final playing = _playingTile();

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
          selectedIcon: playing.icon,
          outlinedIcon: playing.outlined,
          tooltip: playing.tooltip,
          selected: playing.selected,
          onTap: onPlayingTap,
          subtitle: playing.subtitle,
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
          tooltip: isOwned ? 'Remove from Owned' : 'Add to Owned',
          selected: isOwned,
          onTap: onOwnedTap,
          subtitle: 'Owned',
        ),
      ],
    );
  }
}
