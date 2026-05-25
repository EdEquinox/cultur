import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_metric.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// IGDB / Critics / Users scores below the action row (not in the hero).
class GameRatingsRow extends StatelessWidget {
  const GameRatingsRow({super.key, required this.ratings});

  final List<CatalogDetailMetric> ratings;

  @override
  Widget build(BuildContext context) {
    if (ratings.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        for (var i = 0; i < ratings.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${ratings[i].label}: ${ratings[i].value}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: CulturCatalogTypography.gridTitle(theme),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
