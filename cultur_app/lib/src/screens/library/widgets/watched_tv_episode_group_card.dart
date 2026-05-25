import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/library/watched_tv_episode_library_row.dart';
import 'package:yamtrack/src/utils/grouping.dart';
import 'package:yamtrack/src/screens/widgets/library_poster_thumb.dart';
import 'package:yamtrack/src/screens/library/widgets/watched_star_rating_badge.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class WatchedTvEpisodeGroupCard extends StatelessWidget {
  const WatchedTvEpisodeGroupCard({super.key, 
    required this.rows,
    required this.accentLabelColor,
    required this.expanded,
    required this.onExpansionChanged,
    required this.onOpenEpisode,
    required this.onRemoveWatched,
    required this.busyKeys,
    required this.busyKeyFor,
    this.score,
  });

  final List<WatchedTvEpisodeLibraryRow> rows;
  final Color accentLabelColor;
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final void Function(WatchedTvEpisodeLibraryRow row) onOpenEpisode;
  final void Function(WatchedTvEpisodeLibraryRow row) onRemoveWatched;
  final Set<String> busyKeys;
  final String Function(WatchedTvEpisodeLibraryRow row) busyKeyFor;
  final double? score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final show = rows.first.media;
    final range = tvEpisodeRangeLabel(rows);
    final rangeText = range.$1 == range.$2 ? range.$1 : '${range.$1} - ${range.$2}';
    final rating = score;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => onExpansionChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  LibraryPosterThumb(imageUrl: show.imageUrl, width: 32, height: 50),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          show.title,
                          style: CulturCatalogTypography.listTitle(theme),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: rangeText,
                                style: CulturCatalogTypography.listMeta(theme, scheme),
                              ),
                              TextSpan(
                                text: ' · ',
                                style: CulturCatalogTypography.listMeta(theme, scheme),
                              ),
                              TextSpan(
                                text: '${rows.length} episodes',
                                style: CulturCatalogTypography.listMeta(
                                  theme,
                                  scheme,
                                  color: accentLabelColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (rating != null) ...[
                    const SizedBox(width: 8),
                    WatchedStarRatingBadge(score: rating, iconSize: 18),
                  ],
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    InkWell(
                      onTap: () => onOpenEpisode(rows[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LibraryPosterThumb(
                              imageUrl: rows[i].media.imageUrl,
                              width: 32,
                              height: 50,
                              radius: 4,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: tvEpisodeCode(rows[i]),
                                      style: CulturCatalogTypography.listMeta(theme, scheme),
                                    ),
                                    TextSpan(
                                      text: ' · ',
                                      style: CulturCatalogTypography.listMeta(theme, scheme),
                                    ),
                                    TextSpan(
                                      text: 'Episode',
                                      style: CulturCatalogTypography.listMeta(
                                        theme,
                                        scheme,
                                        color: accentLabelColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Mark as not watched',
                              onPressed: busyKeys.contains(busyKeyFor(rows[i]))
                                  ? null
                                  : () => onRemoveWatched(rows[i]),
                              icon: busyKeys.contains(busyKeyFor(rows[i]))
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(
                                      Icons.remove_red_eye_outlined,
                                      size: 22,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
