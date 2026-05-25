import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/models/games/stash_game_event.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/igdb_image_url.dart';

/// Selected event detail card (matches [LatestReleaseCard] layout).
class StashEventReleaseCard extends StatelessWidget {
  const StashEventReleaseCard({
    super.key,
    required this.event,
    required this.onTap,
    this.width = 312,
    this.height = 164,
  });

  final StashGameEvent event;
  final VoidCallback onTap;
  final double? width;
  final double height;

  static String _subtitle(StashGameEvent event) {
    final description = event.displayDescription;
    if (description != null && description.isNotEmpty) {
      return description;
    }
    return releaseDayLabel(event.startsAt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = igdbDisplayImageUrl(event.imageUrl);

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Opacity(
                  opacity: 0.16,
                  child: Image.network(
                    imageUrl,
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
                    child: imageUrl == null || imageUrl.isEmpty
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            child: const Icon(Icons.event_outlined),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stackTrace) {
                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                ),
                                child: const Icon(Icons.event_outlined),
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
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CulturCatalogTypography.listTitle(theme),
                      ),
                      if (_subtitle(event).isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _subtitle(event),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: CulturCatalogTypography.listMeta(
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
