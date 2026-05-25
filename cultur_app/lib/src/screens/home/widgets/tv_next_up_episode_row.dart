import 'package:flutter/material.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/providers/movie_detail_providers.dart';
import 'package:yamtrack/src/screens/widgets/episode_watched_when_sheet.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class TvNextUpEpisodeRow extends ConsumerStatefulWidget {
  const TvNextUpEpisodeRow({
    super.key,
    required this.item,
    required this.username,
  });

  final CatalogItem item;
  final String username;

  @override
  ConsumerState<TvNextUpEpisodeRow> createState() => TvNextUpEpisodeRowState();
}

class TvNextUpEpisodeRowState extends ConsumerState<TvNextUpEpisodeRow> {
  bool _busy = false;

  ({int season, int episode})? _parseEpisode() {
    return parseTvShelfEpisodeSubtitle(widget.item.subtitle);
  }

  Future<void> _toggleWatched() async {
    final ep = _parseEpisode();
    if (ep == null) {
      return;
    }
    final username = widget.username.trim();
    if (username.isEmpty) {
      return;
    }

    DateTime? watchedAtUtc;
    final when = await showEpisodeWatchedAtSheet(
      context,
      title: 'Mark as watched',
      subtitle: (widget.item.subtitle ?? '').trim().isEmpty
          ? 'S${ep.season}E${ep.episode}'
          : widget.item.subtitle!.trim(),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    );
    if (!mounted || when == null) {
      return;
    }
    watchedAtUtc = when.watchedAtUtc;

    setState(() => _busy = true);
    try {
      await ref.read(episodeWatchMutationControllerProvider).putEpisodeWatched(
            username: username,
            mediaId: widget.item.id,
            seasonNumber: ep.season,
            episodeNumber: ep.episode,
            watched: true,
            watchedAtUtc: watchedAtUtc,
          );
      final u = ref.read(authControllerProvider).asData?.value.session?.username;
      ref.invalidate(
        movieDetailProvider(
          MovieDetailRequest(mediaId: widget.item.id, username: u, isTv: true),
        ),
      );
      ref.invalidate(tvSeasonListCatalogProvider(widget.item.id));
      if (username.isNotEmpty) {
        invalidateTvEpisodeWatchCaches(ref, username: username);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openEpisode() {
    final ep = _parseEpisode();
    if (ep == null) {
      context.push(catalogItemDetailPath(widget.item));
      return;
    }
    context.push(
      '/tv/${widget.item.id}/seasons/${ep.season}/episodes/${ep.episode}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;
    final ep = _parseEpisode();
    final dateLine = releaseFriendlyLabel(item);
    final canMark = ep != null && widget.username.trim().isNotEmpty;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 340,
        height: 80,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkWell(
                onTap: _openEpisode,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 54,
                          child: item.imageUrl != null && item.imageUrl!.trim().isNotEmpty
                              ? Image.network(
                                  item.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                                    color: theme.colorScheme.surfaceContainerLow,
                                    child: Icon(
                                      Icons.live_tv_outlined,
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                )
                              : ColoredBox(
                                  color: theme.colorScheme.surfaceContainerLow,
                                  child: Icon(
                                    Icons.live_tv_outlined,
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (dateLine.isNotEmpty)
                              Text(
                                dateLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CulturCatalogTypography.listMeta(theme, scheme),
                              ),
                            if (dateLine.isNotEmpty) const SizedBox(height: 2),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CulturCatalogTypography.listTitle(theme),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (item.subtitle != null && item.subtitle!.trim().isNotEmpty)
                                  ? item.subtitle!.trim()
                                  : (ep != null ? 'S${ep.season}E${ep.episode}' : ''),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: CulturCatalogTypography.listMeta(theme, scheme),
                            ),
                            const Spacer(),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 4,
                                value: 0.2,
                                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: SizedBox(
                width: 52,
                child: _busy
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton.filledTonal(
                        tooltip: 'Mark watched',
                        onPressed: canMark ? _toggleWatched : null,
                        icon: const Icon(Icons.remove_red_eye_outlined),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(22, 22),
                          padding: EdgeInsets.all(8),
                          backgroundColor: Colors.transparent,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

