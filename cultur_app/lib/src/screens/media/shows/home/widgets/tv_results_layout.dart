import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/providers/tv_search_view_provider.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_metrics.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';

/// TV catalog search results: shared grid/list cards with movies and games.
class TvResultsLayout extends StatelessWidget {
  const TvResultsLayout({
    required this.viewMode,
    required this.items,
    required this.gridColumns,
    required this.onOpenShow,
    this.onOpenActions,
    super.key,
  });

  final TvSearchViewMode viewMode;
  final List<CatalogItem> items;
  final int gridColumns;
  final ValueChanged<CatalogItem> onOpenShow;
  final ValueChanged<CatalogItem>? onOpenActions;

  @override
  Widget build(BuildContext context) {
    return switch (viewMode) {
      TvSearchViewMode.grid => GridView.builder(
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
              onTap: () => onOpenShow(item),
              onLongPress:
                  onOpenActions == null ? null : () => onOpenActions!(item),
            );
          },
        ),
      TvSearchViewMode.list => Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              CulturCatalogListRow(
                item: items[i],
                onTap: () => onOpenShow(items[i]),
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
