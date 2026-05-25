import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/providers/book_search_view_provider.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_metrics.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';

/// Book catalog search results: grid (with synopsis) or list rows.
class BookResultsLayout extends StatelessWidget {
  const BookResultsLayout({
    required this.viewMode,
    required this.items,
    required this.gridColumns,
    required this.onOpenBook,
    this.onOpenActions,
    super.key,
  });

  /// Taller cells than games/movies to fit synopsis under the title.
  static const double bookGridChildAspectRatio = 0.36;

  final BookSearchViewMode viewMode;
  final List<CatalogItem> items;
  final int gridColumns;
  final ValueChanged<CatalogItem> onOpenBook;
  final ValueChanged<CatalogItem>? onOpenActions;

  @override
  Widget build(BuildContext context) {
    return switch (viewMode) {
      BookSearchViewMode.grid => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridColumns,
            crossAxisSpacing: CulturCatalogGridMetrics.crossAxisSpacing,
            mainAxisSpacing: CulturCatalogGridMetrics.mainAxisSpacing,
            childAspectRatio: bookGridChildAspectRatio,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return CulturCatalogGridCard(
              item: item,
              synopsisLine: catalogItemGridSynopsisLine(item),
              onTap: () => onOpenBook(item),
              onLongPress:
                  onOpenActions == null ? null : () => onOpenActions!(item),
            );
          },
        ),
      BookSearchViewMode.list => Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              CulturCatalogListRow(
                item: items[i],
                onTap: () => onOpenBook(items[i]),
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
