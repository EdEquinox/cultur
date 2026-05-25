import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/models/library/library_enums.dart';
import 'package:yamtrack/src/screens/library/widgets/library_compact_card.dart';
import 'package:yamtrack/src/screens/library/widgets/library_detailed_card.dart';
import 'package:yamtrack/src/screens/library/widgets/library_grid_card.dart';
import 'package:yamtrack/src/screens/library/widgets/library_poster_card.dart';

/// Renders library tracking items in the selected [LibraryViewMode].
class LibraryTrackingLayout extends StatelessWidget {
  const LibraryTrackingLayout({
    required this.viewMode,
    required this.items,
    required this.savingIds,
    required this.onOpenMovie,
    required this.onOpenActions,
    required this.onCollectedTap,
    required this.onWatchlistTap,
    required this.onWatchedTap,
    super.key,
  });

  final LibraryViewMode viewMode;
  final List<TrackingItem> items;
  final Set<String> savingIds;
  final ValueChanged<TrackingItem> onOpenMovie;
  final ValueChanged<TrackingItem> onOpenActions;
  final ValueChanged<TrackingItem> onCollectedTap;
  final ValueChanged<TrackingItem> onWatchlistTap;
  final ValueChanged<TrackingItem> onWatchedTap;

  @override
  Widget build(BuildContext context) {
    switch (viewMode) {
      case LibraryViewMode.detailed:
        return Column(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LibraryDetailedCard(
                  item: item,
                  isSaving: savingIds.contains(item.id),
                  onTap: () => onOpenMovie(item),
                  onCollectedTap: () => onCollectedTap(item),
                  onWatchlistTap: () => onWatchlistTap(item),
                  onWatchedTap: () => onWatchedTap(item),
                ),
              ),
          ],
        );
      case LibraryViewMode.compact:
        return Column(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LibraryCompactCard(
                  item: item,
                  isSaving: savingIds.contains(item.id),
                  onTap: () => onOpenMovie(item),
                  onCollectedTap: () => onCollectedTap(item),
                  onWatchlistTap: () => onWatchlistTap(item),
                  onWatchedTap: () => onWatchedTap(item),
                ),
              ),
          ],
        );
      case LibraryViewMode.grid:
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return LibraryGridCard(
              item: item,
              onTap: () => onOpenMovie(item),
              onLongPress: () => onOpenActions(item),
            );
          },
        );
      case LibraryViewMode.posters:
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: 0.56,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return LibraryPosterCard(
              item: item,
              onTap: () => onOpenMovie(item),
              onLongPress: () => onOpenActions(item),
            );
          },
        );
    }
  }
}
