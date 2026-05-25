import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class MovieRecommendationShelf extends StatelessWidget {
  const MovieRecommendationShelf({
    super.key,
    required this.items,
    required this.onOpenRecommendation,
  });

  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onOpenRecommendation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You may also like',
              style: CulturCatalogTypography.sectionHeading(theme),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 228,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final r = context.culturTokens.radiusTight;
                  final shelfBg = context.culturTokens.shelfRowBackground;
                  return InkWell(
                    borderRadius: BorderRadius.circular(r),
                    onTap: () => onOpenRecommendation(item),
                    child: SizedBox(
                      width: 144,
                      height: 228,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(r),
                            child: SizedBox(
                              width: 144,
                              height: 168,
                              child: item.imageUrl == null || item.imageUrl!.isEmpty
                                  ? ColoredBox(
                                      color: shelfBg,
                                      child: const Icon(Icons.movie_outlined),
                                    )
                                  : Image.network(
                                      item.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return ColoredBox(
                                          color: shelfBg,
                                          child: const Icon(Icons.movie_outlined),
                                        );
                                      },
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: CulturCatalogTypography.gridTitle(theme),
                                ),
                                if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: CulturCatalogTypography.gridSubtitle(theme, scheme),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
