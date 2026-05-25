import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/widgets/library_quick_actions_column.dart';
import 'package:yamtrack/src/widgets/cards/cultur_list_row_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';

class LibraryCompactCard extends StatelessWidget {
  const LibraryCompactCard({
    required this.item,
    required this.isSaving,
    super.key,
    this.onTap,
    this.onCollectedTap,
    this.onWatchlistTap,
    this.onWatchedTap,
  });

  final TrackingItem item;
  final bool isSaving;
  final VoidCallback? onTap;
  final VoidCallback? onCollectedTap;
  final VoidCallback? onWatchlistTap;
  final VoidCallback? onWatchedTap;

  @override
  Widget build(BuildContext context) {
    return CulturListRowCard(
      content: CulturMediaCardContent.fromTracking(item),
      density: CulturListRowDensity.compact,
      onTap: onTap,
      metaLine: subtitleFor(item),
      actions: LibraryQuickActionsColumn(
        item: item,
        isSaving: isSaving,
        compact: true,
        onCollectedTap: onCollectedTap,
        onWatchlistTap: onWatchlistTap,
        onWatchedTap: onWatchedTap,
      ),
    );
  }
}
