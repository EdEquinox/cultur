import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/library/widgets/library_watched_style_catalog_row.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

class WatchedMovieHistoryCard extends StatelessWidget {
  const WatchedMovieHistoryCard({super.key, 
    required this.item,
    required this.isSaving,
    required this.accentLabelColor,
    required this.onOpen,
    required this.onUnwatch,
  });

  final TrackingItem item;
  final bool isSaving;
  final Color accentLabelColor;
  final VoidCallback onOpen;
  final VoidCallback onUnwatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metaParts = catalogRowMetaPartsForTrackingMedia(item.media);
    final rating = item.score;

    return LibraryWatchedStyleCatalogRow(
      title: item.media.title,
      imageUrl: item.media.imageUrl,
      metaParts: metaParts,
      accentColor: accentLabelColor,
      score: rating,
      onTap: onOpen,
      trailing: IconButton(
        tooltip: 'Mark as not watched',
        onPressed: isSaving ? null : onUnwatch,
        iconSize: 18,
        icon: isSaving
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.remove_red_eye_outlined, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
