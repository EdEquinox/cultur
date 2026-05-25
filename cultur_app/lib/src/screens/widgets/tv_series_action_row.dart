import 'package:flutter/material.dart';

import 'cultur_detail_action_row.dart';

/// TV series detail actions — Watching tile covers start, finish, and left (like games).
class TvSeriesActionRow extends StatelessWidget {
  const TvSeriesActionRow({
    super.key,
    required this.isSaving,
    required this.isCollected,
    required this.isInWatchlist,
    required this.isWatching,
    required this.isSeriesFinished,
    required this.isDropped,
    required this.isBuy,
    required this.rating,
    required this.onCollectedTap,
    required this.onWatchlistTap,
    required this.onWatchingTap,
    required this.onBuyTap,
    required this.onRateTap,
    required this.onListsTap,
    this.watchingProgressLabel,
  });

  final bool isSaving;
  final bool isCollected;
  final bool isInWatchlist;
  final bool isWatching;
  final bool isSeriesFinished;
  final bool isDropped;
  final bool isBuy;
  final double? rating;
  final VoidCallback onCollectedTap;
  final VoidCallback onWatchlistTap;
  final VoidCallback onWatchingTap;
  final VoidCallback onBuyTap;
  final VoidCallback onRateTap;
  final VoidCallback onListsTap;
  final String? watchingProgressLabel;

  ({IconData icon, IconData outlined, String tooltip, bool selected, String subtitle})
      _watchingTile() {
    final progress = watchingProgressLabel?.trim();
    if (isWatching) {
      return (
        icon: Icons.visibility,
        outlined: Icons.visibility_outlined,
        tooltip: progress != null && progress.isNotEmpty
            ? 'Watching $progress episodes — finish, stop, or pause'
            : 'Watching — finish, stop, or pause',
        selected: true,
        subtitle: progress != null && progress.isNotEmpty ? '$progress eps' : 'Watching',
      );
    }
    if (isSeriesFinished) {
      return (
        icon: Icons.check_circle,
        outlined: Icons.check_circle_outline,
        tooltip: 'Finished — tap to watch again',
        selected: true,
        subtitle: 'Finished',
      );
    }
    if (isDropped) {
      return (
        icon: Icons.flag,
        outlined: Icons.flag_outlined,
        tooltip: 'Left — tap to watch again',
        selected: true,
        subtitle: 'Left',
      );
    }
    final notStarted = progress == null || progress.isEmpty;
    if (notStarted) {
      return (
        icon: Icons.play_circle,
        outlined: Icons.play_circle_outline,
        tooltip: 'Start watching this series',
        selected: false,
        subtitle: 'Start',
      );
    }
    return (
      icon: Icons.visibility_outlined,
      outlined: Icons.visibility_outlined,
      tooltip: 'Mark as watching',
      selected: false,
      subtitle: 'Watching',
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = rating;
    final hasRating = r != null && r.isFinite && r > 0;
    final watching = _watchingTile();

    return CulturDetailActionRow(
      enabled: !isSaving,
      tiles: [
        CulturDetailActionTileSpec(
          icon: isCollected ? Icons.library_add : Icons.library_add_outlined,
          tooltip: 'Collected',
          selected: isCollected,
          onTap: onCollectedTap,
          subtitle: 'Collection',
        ),
        CulturDetailActionTileSpec(
          icon: isInWatchlist ? Icons.watch_later : Icons.watch_later_outlined,
          tooltip: 'Watchlist',
          selected: isInWatchlist,
          onTap: onWatchlistTap,
          subtitle: 'Watchlist',
        ),
        CulturDetailActionTileSpec.toggle(
          selectedIcon: watching.icon,
          outlinedIcon: watching.outlined,
          tooltip: watching.tooltip,
          selected: watching.selected,
          onTap: onWatchingTap,
          subtitle: watching.subtitle,
        ),
        CulturDetailActionTileSpec(
          icon: hasRating ? Icons.star : Icons.star_border_outlined,
          tooltip: hasRating ? 'Rating ${r.toStringAsFixed(1)}/10' : 'Rate',
          selected: hasRating,
          onTap: onRateTap,
          subtitle: hasRating ? '${r.toStringAsFixed(1)} / 10' : 'Rate',
        ),
        CulturDetailActionTileSpec(
          icon: isBuy ? Icons.shopping_bag : Icons.shopping_bag_outlined,
          tooltip: isBuy ? 'Remove from Buy' : 'Add to Buy',
          selected: isBuy,
          onTap: onBuyTap,
          subtitle: 'To Buy',
        ),
        CulturDetailActionTileSpec(
          icon: Icons.playlist_add_outlined,
          tooltip: 'Lists',
          selected: false,
          onTap: onListsTap,
          subtitle: 'Lists',
        ),
      ],
    );
  }
}
