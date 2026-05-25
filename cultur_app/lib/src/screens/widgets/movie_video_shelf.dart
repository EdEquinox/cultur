import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/models/movie/movie_detail_video.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class MovieVideoShelf extends StatelessWidget {
  const MovieVideoShelf({
    super.key,
    required this.videos,
    required this.onOpenVideo,
  });

  final List<MovieDetailVideo> videos;
  final ValueChanged<String> onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: SizedBox(
          height: 194,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: videos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
                  final video = videos[index];
                  final scheme = Theme.of(context).colorScheme;
                  final shelfBg = context.culturTokens.shelfRowBackground;
                  final r = context.culturTokens.radiusTight;
                  return InkWell(
                    borderRadius: BorderRadius.circular(r),
                    onTap: video.url == null ? null : () => onOpenVideo(video.url!),
                    child: SizedBox(
                      width: 232,
                      height: 194,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(r),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 232,
                                  height: 124,
                                  child: video.imageUrl == null || video.imageUrl!.isEmpty
                                      ? ColoredBox(
                                          color: shelfBg,
                                          child: const Icon(Icons.play_circle_outline),
                                        )
                                      : Image.network(
                                          video.imageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return ColoredBox(
                                              color: shelfBg,
                                              child: const Icon(
                                                Icons.play_circle_outline,
                                              ),
                                            );
                                          },
                                        ),
                                ),
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: scheme.scrim.withValues(alpha: 0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: scheme.onSurface,
                                    size: 28,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  video.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: CulturCatalogTypography.listTitle(theme),
                                ),
                                if (video.subtitle != null && video.subtitle!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    video.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: CulturCatalogTypography.listMeta(theme, scheme),
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
      ),
    );
  }
}
