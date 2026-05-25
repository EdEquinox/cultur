import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/tv/tv_next_episode_card_data.dart';

import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';
import 'episode_watched_when_sheet.dart';
import '../../providers/movie_detail_providers.dart';
import '../../controllers/auth_controller.dart';

/// Suggested next aired episode (from API) with quick watch toggle.
class TvNextEpisodeCard extends ConsumerStatefulWidget {
  const TvNextEpisodeCard({
    required this.mediaId,
    required this.data,
    required this.isWatched,
    super.key,
  });

  final String mediaId;
  final TvNextEpisodeCardData data;
  final bool isWatched;

  @override
  ConsumerState<TvNextEpisodeCard> createState() => _TvNextEpisodeCardState();
}

class _TvNextEpisodeCardState extends ConsumerState<TvNextEpisodeCard> {
  bool _busy = false;

  Future<void> _toggle(String? username) async {
    if (username == null || username.isEmpty) {
      return;
    }
    DateTime? watchedAtUtc;
    if (!widget.isWatched) {
      final when = await showEpisodeWatchedAtSheet(
        context,
        title: 'Mark as watched',
        subtitle:
            'S${widget.data.seasonNumber}E${widget.data.episodeNumber} · '
            '${(widget.data.name?.trim().isNotEmpty ?? false) ? widget.data.name!.trim() : 'Episode ${widget.data.episodeNumber}'}',
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      );
      if (!mounted || when == null) {
        return;
      }
      watchedAtUtc = when.watchedAtUtc;
    }
    setState(() => _busy = true);
    try {
      await ref.read(episodeWatchMutationControllerProvider).putEpisodeWatched(
            username: username,
            mediaId: widget.mediaId,
            seasonNumber: widget.data.seasonNumber,
            episodeNumber: widget.data.episodeNumber,
            watched: !widget.isWatched,
            watchedAtUtc: watchedAtUtc,
          );
      final user = ref.read(authControllerProvider).asData?.value;
      final u = user?.session?.username;
      ref.invalidate(
        movieDetailProvider(
          MovieDetailRequest(mediaId: widget.mediaId, username: u, isTv: true),
        ),
      );
      ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider).asData?.value;
    final username = auth?.session?.username;
    final d = widget.data;
    final meta = <String>[
      'S${d.seasonNumber.toString().padLeft(2, '0')}E${d.episodeNumber.toString().padLeft(2, '0')}',
      if (d.runtimeMinutes != null) '${d.runtimeMinutes} min',
    ].join(' · ');
    final air = d.airDate?.trim();
    final title = (d.name?.trim().isNotEmpty ?? false) ? d.name!.trim() : 'Episode ${d.episodeNumber}';

    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 96,
                height: 54,
                child: d.stillUrl != null && d.stillUrl!.isNotEmpty
                    ? Image.network(
                        d.stillUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerLow,
                          child: const Icon(Icons.movie),
                        ),
                      )
                    : ColoredBox(
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Icon(Icons.movie_outlined, color: theme.colorScheme.outline),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (air != null && air.isNotEmpty)
                    Text(
                      air,
                      style: CulturCatalogTypography.listMeta(
                        theme,
                        theme.colorScheme,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CulturCatalogTypography.listTitle(theme),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: CulturCatalogTypography.listMeta(theme, theme.colorScheme),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              height: 48,
              child: _busy
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton.filledTonal(
                      tooltip: widget.isWatched ? 'Mark unwatched' : 'Mark watched',
                      onPressed: username == null || username.isEmpty ? null : () => _toggle(username),
                      icon: Icon(
                        widget.isWatched ? Icons.visibility : Icons.visibility_outlined,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
