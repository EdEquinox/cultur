import 'package:flutter/material.dart';

import 'cultur_detail_action_row.dart';

class MovieActionRow extends StatelessWidget {
  const MovieActionRow({
    super.key,
    required this.isSaving,
    required this.isCollected,
    required this.isInWatchlist,
    required this.isWatched,
    required this.isBuy,
    required this.rating,
    required this.onCollectedTap,
    required this.onWatchlistTap,
    required this.onWatchedTap,
    required this.onBuyTap,
    required this.onRateTap,
    required this.onListsTap,
    this.isTv = false,
    this.tvStartWatchingMode = false,
    this.below,
  });

  final bool isSaving;
  final bool isCollected;
  final bool isInWatchlist;
  final bool isWatched;
  final bool isBuy;
  final double? rating;
  final VoidCallback onCollectedTap;
  final VoidCallback onWatchlistTap;
  final VoidCallback onWatchedTap;
  final VoidCallback onBuyTap;
  final VoidCallback onRateTap;
  final VoidCallback onListsTap;
  final bool isTv;
  final bool tvStartWatchingMode;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final r = rating;
    final hasRating = r != null && r.isFinite && r > 0;
    final useStart = isTv && tvStartWatchingMode;

    CulturDetailActionTileSpec collected() => CulturDetailActionTileSpec(
          icon: isCollected ? Icons.library_add : Icons.library_add_outlined,
          tooltip: 'Collected',
          selected: isCollected,
          onTap: onCollectedTap,
          subtitle: 'Collection',
        );

    CulturDetailActionTileSpec watchlist() => CulturDetailActionTileSpec(
          icon: isInWatchlist ? Icons.watch_later : Icons.watch_later_outlined,
          tooltip: 'Watchlist',
          selected: isInWatchlist,
          onTap: onWatchlistTap,
          subtitle: 'Watchlist',
        );

    CulturDetailActionTileSpec watched() => CulturDetailActionTileSpec(
          icon: useStart
              ? Icons.play_circle_outline
              : (isWatched ? Icons.remove_red_eye : Icons.remove_red_eye_outlined),
          tooltip: useStart ? 'Start tracking this series' : 'Watched',
          selected: useStart ? false : isWatched,
          onTap: onWatchedTap,
          subtitle: useStart ? 'Start' : 'Watched',
        );

    CulturDetailActionTileSpec rate() => CulturDetailActionTileSpec(
          icon: hasRating ? Icons.star : Icons.star_border_outlined,
          tooltip: hasRating ? 'Rating ${r.toStringAsFixed(1)}/10' : 'Rate',
          selected: hasRating,
          onTap: onRateTap,
          subtitle: hasRating ? '${r.toStringAsFixed(1)} / 10' : 'Rate',
        );

    CulturDetailActionTileSpec buy() => CulturDetailActionTileSpec(
          icon: isBuy ? Icons.shopping_bag : Icons.shopping_bag_outlined,
          tooltip: isBuy ? 'Remove from Buy' : 'Add to Buy',
          selected: isBuy,
          onTap: onBuyTap,
          subtitle: 'To Buy',
        );

    CulturDetailActionTileSpec lists() => CulturDetailActionTileSpec(
          icon: Icons.playlist_add_outlined,
          tooltip: 'Lists',
          selected: false,
          onTap: onListsTap,
          subtitle: 'Lists',
        );

    final tiles = isTv
        ? [collected(), watchlist(), watched(), rate(), buy(), lists()]
        : [watchlist(), watched(), rate(), buy(), collected(), lists()];

    return CulturDetailActionRow(
      enabled: !isSaving,
      tiles: tiles,
      below: below,
    );
  }
}
