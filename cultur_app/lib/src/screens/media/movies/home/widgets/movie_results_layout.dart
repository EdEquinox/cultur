import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/providers/search_provider.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_metrics.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';

/// Movie catalog search results: shared grid/list cards with TV and games.
class MovieResultsLayout extends StatelessWidget {
  const MovieResultsLayout({
    required this.viewMode,
    required this.items,
    required this.gridColumns,
    required this.onOpenMovie,
    this.onOpenActions,
    super.key,
  });

  final MovieSearchViewMode viewMode;
  final List<CatalogItem> items;
  final int gridColumns;
  final ValueChanged<CatalogItem> onOpenMovie;
  final ValueChanged<CatalogItem>? onOpenActions;

  @override
  Widget build(BuildContext context) {
    return switch (viewMode) {
      MovieSearchViewMode.grid => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridColumns,
            crossAxisSpacing: CulturCatalogGridMetrics.crossAxisSpacing,
            mainAxisSpacing: CulturCatalogGridMetrics.mainAxisSpacing,
            childAspectRatio: CulturCatalogGridCard.gridChildAspectRatio,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return CulturCatalogGridCard(
              item: item,
              onTap: () => onOpenMovie(item),
              onLongPress:
                  onOpenActions == null ? null : () => onOpenActions!(item),
            );
          },
        ),
      MovieSearchViewMode.list => Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              CulturCatalogListRow(
                item: items[i],
                onTap: () => onOpenMovie(items[i]),
                onLongPress: onOpenActions == null
                    ? null
                    : () => onOpenActions!(items[i]),
              ),
            ],
          ],
        ),
    };
  }
}
