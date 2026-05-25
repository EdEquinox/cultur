import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/widgets/movie_quick_action_button.dart';

class MovieQuickActionsBar extends StatelessWidget {
  const MovieQuickActionsBar({super.key, 
    required this.tracking,
    required this.isSaving,
    this.compact = false,
    this.iconOnly = false,
    this.vertical = false,
    this.onWatchlistTap,
    this.onWatchedTap,
  });

  final TrackingItem? tracking;
  final bool isSaving;
  final bool compact;
  final bool iconOnly;
  final bool vertical;
  final VoidCallback? onWatchlistTap;
  final VoidCallback? onWatchedTap;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      MovieQuickActionButton(
        label: 'Watchlist',
        icon: trackingIsInWatchlist(tracking)
            ? Icons.bookmark
            : Icons.bookmark_border_outlined,
        active: trackingIsInWatchlist(tracking),
        compact: compact,
        iconOnly: iconOnly,
        isLoading: isSaving,
        onPressed: isSaving ? null : onWatchlistTap,
      ),
      MovieQuickActionButton(
        label: 'Watched',
        icon: trackingIsWatched(tracking)
            ? Icons.remove_red_eye
            : Icons.remove_red_eye_outlined,
        active: trackingIsWatched(tracking),
        compact: compact,
        iconOnly: iconOnly,
        isLoading: isSaving,
        onPressed: isSaving ? null : onWatchedTap,
      ),
    ];

    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < buttons.length; index++) ...[
            buttons[index],
            if (index != buttons.length - 1) const SizedBox(height: 8),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: buttons,
    );
  }
}
