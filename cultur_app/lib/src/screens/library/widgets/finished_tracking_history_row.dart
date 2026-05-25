import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/library/widgets/library_watched_style_catalog_row.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

/// Single finished/done row — same card style as Doing shelves.
class FinishedTrackingHistoryRow extends StatelessWidget {
  const FinishedTrackingHistoryRow({
    super.key,
    required this.item,
    required this.isSaving,
    required this.accentLabelColor,
    required this.onOpen,
    required this.onRemove,
    required this.removeTooltip,
    required this.removeIcon,
    this.metaPartsForItem,
  });

  final TrackingItem item;
  final bool isSaving;
  final Color accentLabelColor;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final String removeTooltip;
  final IconData removeIcon;
  final List<String> Function(TrackingItem item)? metaPartsForItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metaParts = metaPartsForItem?.call(item) ??
        catalogRowMetaPartsForTrackingMedia(item.media);

    return LibraryWatchedStyleCatalogRow(
      title: item.media.title,
      imageUrl: item.media.imageUrl,
      metaParts: metaParts,
      accentColor: accentLabelColor,
      score: item.score,
      onTap: onOpen,
      trailing: IconButton(
        tooltip: removeTooltip,
        onPressed: isSaving ? null : onRemove,
        iconSize: 18,
        icon: isSaving
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(removeIcon, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
