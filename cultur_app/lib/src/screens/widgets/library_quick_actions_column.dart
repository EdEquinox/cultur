import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/widgets/library_quick_icon_button.dart';

class LibraryQuickActionsColumn extends StatelessWidget {
  const LibraryQuickActionsColumn({super.key, 
    required this.item,
    required this.isSaving,
    this.compact = false,
    this.onCollectedTap,
    this.onWatchlistTap,
    this.onWatchedTap,
  });

  final TrackingItem item;
  final bool isSaving;
  final bool compact;
  final VoidCallback? onCollectedTap;
  final VoidCallback? onWatchlistTap;
  final VoidCallback? onWatchedTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LibraryQuickIconButton(
          icon: hasTrackingFlag(item, kCollectedTrackingFlag)
              ? Icons.inventory_2
              : Icons.inventory_2_outlined,
          active: hasTrackingFlag(item, kCollectedTrackingFlag),
          compact: compact,
          isLoading: isSaving,
          onTap: onCollectedTap,
        ),
        const SizedBox(height: 8),
        LibraryQuickIconButton(
          icon: trackingIsInWatchlist(item)
              ? Icons.bookmark
              : Icons.bookmark_border_outlined,
          active: trackingIsInWatchlist(item),
          compact: compact,
          isLoading: isSaving,
          onTap: onWatchlistTap,
        ),
        const SizedBox(height: 8),
        LibraryQuickIconButton(
          icon: trackingIsWatched(item)
              ? Icons.remove_red_eye
              : Icons.remove_red_eye_outlined,
          active: trackingIsWatched(item),
          compact: compact,
          isLoading: isSaving,
          onTap: onWatchedTap,
        ),
      ],
    );
  }
}
