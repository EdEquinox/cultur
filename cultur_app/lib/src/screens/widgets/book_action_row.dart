import 'package:flutter/material.dart';

import 'cultur_detail_action_row.dart';

/// Book detail actions — same row pattern as games and movies.
class BookActionRow extends StatelessWidget {
  const BookActionRow({
    super.key,
    required this.isSaving,
    required this.isInLater,
    required this.isReading,
    required this.isRead,
    required this.isBuy,
    required this.isOwned,
    required this.isDropped,
    required this.rating,
    required this.onLaterTap,
    required this.onReadingTap,
    required this.onBuyTap,
    required this.onReadTap,
    required this.onOwnedTap,
    required this.onRateTap,
    required this.onListsTap,
    this.below,
  });

  final bool isSaving;
  final bool isInLater;
  final bool isReading;
  final bool isRead;
  final bool isBuy;
  final bool isOwned;
  final bool isDropped;
  final double? rating;
  final VoidCallback onLaterTap;
  final VoidCallback onReadingTap;
  final VoidCallback onBuyTap;
  final VoidCallback onReadTap;
  final VoidCallback onOwnedTap;
  final VoidCallback onRateTap;
  final VoidCallback onListsTap;
  final Widget? below;

  ({IconData icon, IconData outlined, String tooltip, bool selected, String subtitle}) _readingTile() {
    if (isRead) {
      return (
        icon: Icons.check_circle,
        outlined: Icons.check_circle_outline,
        tooltip: 'Read — tap to read again',
        selected: true,
        subtitle: 'Read',
      );
    }
    if (isDropped) {
      return (
        icon: Icons.flag,
        outlined: Icons.flag_outlined,
        tooltip: 'Left — tap to read again',
        selected: true,
        subtitle: 'Left',
      );
    }
    if (isReading) {
      return (
        icon: Icons.menu_book,
        outlined: Icons.menu_book_outlined,
        tooltip: 'Reading — finish, leave, or pause',
        selected: true,
        subtitle: 'Reading',
      );
    }
    return (
      icon: Icons.menu_book,
      outlined: Icons.menu_book_outlined,
      tooltip: 'Mark as reading',
      selected: false,
      subtitle: 'Reading',
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = rating;
    final hasRating = r != null && r.isFinite && r > 0;
    final reading = _readingTile();

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
          selectedIcon: reading.icon,
          outlinedIcon: reading.outlined,
          tooltip: reading.tooltip,
          selected: reading.selected,
          onTap: onReadingTap,
          subtitle: reading.subtitle,
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
