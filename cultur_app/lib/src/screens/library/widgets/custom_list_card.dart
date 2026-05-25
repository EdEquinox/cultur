import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/screens/widgets/library_poster_thumb.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class CustomListCard extends StatelessWidget {
  const CustomListCard({super.key, required this.list, this.onTap});

  final CustomMovieList list;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.list_alt_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      list.name,
                      style: CulturCatalogTypography.listTitle(theme),
                    ),
                  ),
                  Text(
                    '${list.items.length}',
                    style: CulturCatalogTypography.listMeta(theme, scheme),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (list.items.isEmpty)
                Text(
                  'No movies yet',
                  style: CulturCatalogTypography.listMeta(theme, scheme),
                )
              else
                SizedBox(
                  height: 82,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.items.take(5).length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = list.items[index];
                      return LibraryPosterThumb(
                        imageUrl: item.imageUrl,
                        width: 54,
                        height: 82,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
