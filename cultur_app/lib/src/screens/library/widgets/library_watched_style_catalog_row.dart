import 'package:flutter/material.dart';
import 'package:yamtrack/src/screens/widgets/library_poster_thumb.dart';
import 'package:yamtrack/src/screens/library/widgets/watched_star_rating_badge.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Same row layout as the Library Watched tab: tight poster, title, dotted meta, optional stars, trailing.
class LibraryWatchedStyleCatalogRow extends StatelessWidget {
  const LibraryWatchedStyleCatalogRow({super.key, 
    required this.title,
    required this.imageUrl,
    required this.metaParts,
    required this.accentColor,
    this.score,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final String title;
  final String? imageUrl;
  final List<String> metaParts;
  final Color accentColor;
  final double? score;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              LibraryPosterThumb(imageUrl: imageUrl, width: 32, height: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CulturCatalogTypography.listTitle(theme),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (metaParts.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text.rich(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        TextSpan(
                          children: [
                            for (var i = 0; i < metaParts.length; i++) ...[
                              if (i > 0)
                                TextSpan(
                                  text: ' · ',
                                  style: CulturCatalogTypography.listMeta(theme, scheme),
                                ),
                              TextSpan(
                                text: metaParts[i],
                                style: CulturCatalogTypography.listMeta(
                                  theme,
                                  scheme,
                                  color: isAccentCatalogMetaPart(metaParts[i])
                                      ? accentColor
                                      : scheme.onSurfaceVariant,
                                  fontWeight: isAccentCatalogMetaPart(metaParts[i])
                                      ? FontWeight.w600
                                      : null,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (score case final s?) ...[
                const SizedBox(width: 8),
                WatchedStarRatingBadge(score: s, iconSize: 18),
              ],
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
