import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/widgets/library_poster_thumb.dart';

class LibraryActionsSheetContent extends StatelessWidget {
  const LibraryActionsSheetContent({
    required this.item,
    required this.onCollectedTap,
    required this.onWatchlistTap,
    required this.onWatchedTap,
    required this.onDoingTap,
    required this.onBuyTap,
    required this.onLeftTap,
    required this.onOpenMovie,
    this.onPriorityTap,
    super.key,
  });

  final TrackingItem item;
  final VoidCallback onCollectedTap;
  final VoidCallback onWatchlistTap;
  final VoidCallback onWatchedTap;
  final VoidCallback onDoingTap;
  final VoidCallback onBuyTap;
  final VoidCallback onLeftTap;
  final VoidCallback onOpenMovie;
  final VoidCallback? onPriorityTap;

  Widget _action({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: active ? null : null),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LibraryPosterThumb(imageUrl: item.media.imageUrl, width: 42, height: 60),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(subtitleFor(item), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _action(
                  icon: hasTrackingFlag(item, kCollectedTrackingFlag)
                      ? Icons.inventory_2
                      : Icons.inventory_2_outlined,
                  label: 'Collected',
                  active: hasTrackingFlag(item, kCollectedTrackingFlag),
                  onTap: onCollectedTap,
                ),
              ),
              Expanded(
                child: _action(
                  icon: trackingIsInWatchlist(item)
                      ? Icons.bookmark
                      : Icons.bookmark_border_outlined,
                  label: 'Later',
                  active: trackingIsInWatchlist(item),
                  onTap: onWatchlistTap,
                ),
              ),
              Expanded(
                child: _action(
                  icon: trackingIsWatched(item) ? Icons.check_circle : Icons.check_circle_outline,
                  label: 'Finished',
                  active: trackingIsWatched(item),
                  onTap: onWatchedTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _action(
                  icon: trackingIsInWatchingCollection(item)
                      ? Icons.play_circle
                      : Icons.play_circle_outline,
                  label: 'Doing',
                  active: trackingIsInWatchingCollection(item),
                  onTap: onDoingTap,
                ),
              ),
              Expanded(
                child: _action(
                  icon: trackingIsBuy(item) ? Icons.shopping_bag : Icons.shopping_bag_outlined,
                  label: 'Buy',
                  active: trackingIsBuy(item),
                  onTap: onBuyTap,
                ),
              ),
              Expanded(
                child: _action(
                  icon: trackingIsDropped(item) ? Icons.flag : Icons.flag_outlined,
                  label: 'Left',
                  active: trackingIsDropped(item),
                  onTap: onLeftTap,
                ),
              ),
            ],
          ),
          if (onPriorityTap != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _action(
                    icon: trackingIsPriority(item)
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    label: 'Priority',
                    active: trackingIsPriority(item),
                    onTap: onPriorityTap!,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenMovie,
              icon: const Icon(Icons.open_in_new),
              label: const Text('View details'),
            ),
          ),
        ],
      ),
    );
  }
}
