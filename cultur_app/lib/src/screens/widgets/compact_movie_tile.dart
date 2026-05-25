import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/widgets/movie_quick_actions_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_list_row_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_media_card_content.dart';

class CompactMovieTile extends StatelessWidget {
  const CompactMovieTile({
    required this.item,
    required this.tracking,
    required this.isSaving,
    super.key,
    this.onTap,
    this.onWatchlistTap,
    this.onWatchedTap,
  });

  final CatalogItem item;
  final TrackingItem? tracking;
  final bool isSaving;
  final VoidCallback? onTap;
  final VoidCallback? onWatchlistTap;
  final VoidCallback? onWatchedTap;

  @override
  Widget build(BuildContext context) {
    return CulturListRowCard(
      content: CulturMediaCardContent.fromCatalog(item),
      density: CulturListRowDensity.compact,
      onTap: onTap,
      actions: MovieQuickActionsBar(
        tracking: tracking,
        isSaving: isSaving,
        compact: true,
        iconOnly: true,
        vertical: true,
        onWatchlistTap: onWatchlistTap,
        onWatchedTap: onWatchedTap,
      ),
    );
  }
}
