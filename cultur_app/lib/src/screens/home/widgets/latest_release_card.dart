import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/igdb_image_url.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class LatestReleaseCard extends StatelessWidget {
  const LatestReleaseCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 312,
    this.height = 164,
    this.showReleaseDate = true,
  });

  final CatalogItem item;
  final VoidCallback onTap;
  final double? width;
  final double height;

  /// When false, omits the date line (timeline shows the date in the group header).
  final bool showReleaseDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratingLabel = _userRatingMetaLine(item);
    final releaseLabel = ratingLabel ?? (showReleaseDate ? releaseLongLabel(item) : '');
    final placeholderIcon = switch (item.mediaType) {
      'tv' => Icons.live_tv_outlined,
      'game' => Icons.sports_esports_outlined,
      'music' => Icons.album_outlined,
      _ => Icons.movie_outlined,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (igdbDisplayImageUrl(item.imageUrl) != null && igdbDisplayImageUrl(item.imageUrl)!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Opacity(
                  opacity: 0.16,
                  child: Image.network(
                    igdbDisplayImageUrl(item.imageUrl)!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.scrim.withValues(alpha: 0.08),
                    theme.colorScheme.scrim.withValues(alpha: 0.32),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 88,
                    height: double.infinity,
                    child: igdbDisplayImageUrl(item.imageUrl) == null || igdbDisplayImageUrl(item.imageUrl)!.isEmpty
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            child: Icon(placeholderIcon),
                          )
                        : Image.network(
                            igdbDisplayImageUrl(item.imageUrl)!,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stackTrace) {
                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                ),
                                child: Icon(placeholderIcon),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showReleaseDate && releaseLabel.isNotEmpty) ...[
                        Text(
                          releaseLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CulturCatalogTypography.listMeta(
                            theme,
                            theme.colorScheme,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CulturCatalogTypography.listTitle(theme),
                      ),
                      if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          catalogItemCardSubtitle(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CulturCatalogTypography.listMeta(
                            theme,
                            theme.colorScheme,
                          ),
                        ),
                      ],
                      if (item.description != null && item.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          item.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: CulturCatalogTypography.bodyText(
                            theme,
                            theme.colorScheme,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String? _userRatingMetaLine(CatalogItem item) {
  final rawScore = item.metadata['userScore'];
  final score = switch (rawScore) {
    num value => value.toDouble(),
    String value => double.tryParse(value),
    _ => null,
  };
  if (score == null || score <= 0) {
    return null;
  }
  final parts = <String>['${score.toStringAsFixed(1)}/10'];
  final ratedRaw = item.metadata['userRatingRatedAt']?.toString();
  if (ratedRaw != null && ratedRaw.isNotEmpty) {
    final ratedAt = DateTime.tryParse(ratedRaw);
    if (ratedAt != null) {
      parts.add(releaseDayLabel(ratedAt.toLocal()));
    }
  }
  return parts.join(' · ');
}
