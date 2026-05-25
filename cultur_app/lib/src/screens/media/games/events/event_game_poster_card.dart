import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/games/stash_game_event_detail.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// Poster card for games shown at a Stash event (collected-tab visual language).
class EventGamePosterCard extends StatelessWidget {
  const EventGamePosterCard({
    required this.item,
    required this.onTap,
    super.key,
  });

  static const double posterAspectRatio = 2 / 3;
  static const double gridChildAspectRatio = 0.56;

  final StashEventGameItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.culturTokens;
    final scheme = theme.colorScheme;
    final subtitle = item.releaseLabel?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: posterAspectRatio,
          child: ClipRRect(
            borderRadius: tokens.borderRadiusTight,
            child: InkWell(
              onTap: onTap,
              child: CulturPosterImage(
                imageUrl: item.imageUrl,
                width: double.infinity,
                height: double.infinity,
                borderRadius: tokens.borderRadiusTight,
                mediaType: 'game',
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: tokens.borderRadiusTight,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CulturCatalogTypography.gridTitle(theme),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CulturCatalogTypography.gridSubtitle(theme, scheme),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
