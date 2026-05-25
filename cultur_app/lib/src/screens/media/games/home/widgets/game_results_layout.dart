import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/providers/game_search_view_provider.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_metrics.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';

/// Game catalog search results: shared grid/list cards with movies and TV.
class GameResultsLayout extends StatelessWidget {
  const GameResultsLayout({
    required this.viewMode,
    required this.items,
    required this.gridColumns,
    required this.onOpenGame,
    this.onOpenActions,
    this.gridChildAspectRatio = CulturCatalogGridCard.gridChildAspectRatio,
    super.key,
  });

  final GameSearchViewMode viewMode;
  final List<CatalogItem> items;
  final int gridColumns;
  final ValueChanged<CatalogItem> onOpenGame;
  final ValueChanged<CatalogItem>? onOpenActions;
  final double gridChildAspectRatio;

  @override
  Widget build(BuildContext context) {
    return switch (viewMode) {
      GameSearchViewMode.grid => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridColumns,
            crossAxisSpacing: CulturCatalogGridMetrics.crossAxisSpacing,
            mainAxisSpacing: CulturCatalogGridMetrics.mainAxisSpacing,
            childAspectRatio: gridChildAspectRatio,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return CulturCatalogGridCard(
              item: item,
              onTap: () => onOpenGame(item),
              onLongPress:
                  onOpenActions == null ? null : () => onOpenActions!(item),
            );
          },
        ),
      GameSearchViewMode.list => Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              CulturCatalogListRow(
                item: items[i],
                onTap: () => onOpenGame(items[i]),
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
