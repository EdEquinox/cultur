import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/games/game_home_shelf_item.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_metrics.dart';

/// Games home shelf poster — thin wrapper around [CulturCatalogGridCard].
class GameHomePosterCard extends StatelessWidget {
  const GameHomePosterCard({
    required this.onTap,
    super.key,
    this.item,
    this.catalogItem,
    this.badgeIcon,
    this.badgeTooltip,
    this.onLongPress,
  }) : assert(item != null || catalogItem != null);

  /// Fixed width for horizontal game shelves.
  static const double width = 132;

  /// Poster (2:3) + text block — keep in sync with [CulturCatalogGridMetrics].
  static double get cardHeight => CulturCatalogGridMetrics.totalHeightForWidth(width);

  final GameHomeShelfItem? item;
  final CatalogItem? catalogItem;
  final VoidCallback onTap;
  final IconData? badgeIcon;
  final String? badgeTooltip;
  final VoidCallback? onLongPress;

  CatalogItem get _media => catalogItem ?? item!.media;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget? imageOverlay;
    if (badgeIcon != null) {
      imageOverlay = Positioned(
        top: 6,
        right: 6,
        child: Tooltip(
          message: badgeTooltip ?? '',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                badgeIcon,
                size: 16,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: width,
      child: CulturCatalogGridCard(
        item: _media,
        onTap: onTap,
        onLongPress: onLongPress,
        imageOverlay: imageOverlay,
      ),
    );
  }
}
