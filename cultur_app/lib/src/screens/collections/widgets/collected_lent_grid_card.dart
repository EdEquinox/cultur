import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Grid card for titles currently lent out (Owned → Lent section).
class CollectedLentGridCard extends StatelessWidget {
  const CollectedLentGridCard({
    required this.media,
    required this.lent,
    super.key,
    this.onTap,
    this.onLongPress,
  });

  static const double gridChildAspectRatio = CulturCatalogGridCard.gridChildAspectRatio;

  final CatalogItem media;
  final CollectedLentInfo lent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateLabel = MaterialLocalizations.of(context).formatShortDate(lent.lentAt);

    return CulturCatalogGridCard(
      item: media,
      onTap: onTap,
      onLongPress: onLongPress,
      footerLines: [
        Text(
          lent.borrowerName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CulturCatalogTypography.gridSubtitle(theme, scheme).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      imageOverlay: Positioned(
        top: 4,
        right: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            dateLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: 10,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
