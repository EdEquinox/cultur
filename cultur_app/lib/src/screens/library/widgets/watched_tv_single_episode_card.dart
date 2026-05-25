import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/library/watched_tv_episode_library_row.dart';
import 'package:yamtrack/src/screens/library/widgets/watched_star_rating_badge.dart';
import 'package:yamtrack/src/utils/grouping.dart';
import 'package:yamtrack/src/screens/widgets/library_poster_thumb.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class WatchedTvSingleEpisodeCard extends StatelessWidget {
  const WatchedTvSingleEpisodeCard({super.key, 
    required this.row,
    required this.accentLabelColor,
    required this.isSaving,
    required this.onOpen,
    required this.onUnwatch,
    this.score,
  });

  final WatchedTvEpisodeLibraryRow row;
  final Color accentLabelColor;
  final bool isSaving;
  final VoidCallback onOpen;
  final VoidCallback onUnwatch;
  final double? score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final code = tvEpisodeCode(row);
    final rating = score;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              LibraryPosterThumb(imageUrl: row.media.imageUrl, width: 32, height: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.media.title,
                      style: CulturCatalogTypography.listTitle(theme),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: code,
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
                  ],
                ),
              ),
              if (rating != null) ...[
                WatchedStarRatingBadge(score: rating, iconSize: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
