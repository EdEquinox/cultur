import 'package:flutter/material.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';

import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/providers/movie_detail_providers.dart';
import 'package:yamtrack/src/screens/widgets/episode_watched_when_sheet.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/models/tv/series_detail.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';

/// Episode rows with watch toggles; optional tap opens episode detail.
class SeriesSeasonEpisodesList extends ConsumerStatefulWidget {
  const SeriesSeasonEpisodesList({
    super.key,
    required this.mediaId,
    required this.seasonNumber,
    this.onEpisodeTap,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 120),
  });

  final String mediaId;
  final int seasonNumber;
  final void Function(TvEpisodeCatalog episode)? onEpisodeTap;
  final EdgeInsets padding;

  @override
  ConsumerState<SeriesSeasonEpisodesList> createState() => _SeriesSeasonEpisodesListState();
}

class _SeriesSeasonEpisodesListState extends ConsumerState<SeriesSeasonEpisodesList> {
  String? _busyKey;

  Future<void> _toggleEpisode({
    required String username,
    required int episodeNumber,
    required bool toWatched,
    required String episodeTitle,
  }) async {
    final key = '$episodeNumber';
    DateTime? watchedAtUtc;
    if (toWatched) {
      final when = await showEpisodeWatchedAtSheet(
        context,
        title: 'Mark as watched',
        subtitle: 'S${widget.seasonNumber}E$episodeNumber · $episodeTitle',
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      );
      if (!mounted || when == null) {
        return;
      }
      watchedAtUtc = when.watchedAtUtc;
    }
    setState(() => _busyKey = key);
    try {
      await ref.read(episodeWatchMutationControllerProvider).putEpisodeWatched(
            username: username,
            mediaId: widget.mediaId,
            seasonNumber: widget.seasonNumber,
            episodeNumber: episodeNumber,
            watched: toWatched,
            watchedAtUtc: watchedAtUtc,
          );
      final req = TvSeasonDetailCatalogRequest(
        mediaId: widget.mediaId,
        seasonNumber: widget.seasonNumber,
        username: username,
      );
      ref.invalidate(tvSeasonDetailCatalogProvider(req));
      ref.invalidate(
        movieDetailProvider(
          MovieDetailRequest(mediaId: widget.mediaId, username: username, isTv: true),
        ),
      );
      ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
      invalidateTvEpisodeWatchCaches(ref, username: username);
    } catch (e) {
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _busyKey = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final request = TvSeasonDetailCatalogRequest(
      mediaId: widget.mediaId,
      seasonNumber: widget.seasonNumber,
      username: username,
    );
    final async = ref.watch(tvSeasonDetailCatalogProvider(request));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(tvSeasonDetailCatalogProvider(request)),
      ),
      data: (detail) {
        if (detail.episodes.isEmpty) {
          return const Center(child: Text('No episodes in this season.'));
        }
        return ListView.separated(
          padding: widget.padding,
          itemCount: detail.episodes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final ep = detail.episodes[index];
            final watched = detail.episodeIsWatched(ep.episodeNumber);
            final busy = _busyKey == '${ep.episodeNumber}';
            final meta = <String>[
              if (ep.airDate != null && ep.airDate!.trim().isNotEmpty) ep.airDate!,
              if (ep.runtimeMinutes != null) '${ep.runtimeMinutes} min',
            ];
            final onRowTap = widget.onEpisodeTap == null
                ? null
                : () => widget.onEpisodeTap!(ep);
            return ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
              onTap: onRowTap,
              leading: SeriesEpisodeStill(url: ep.stillUrl),
              title: Text('E${ep.episodeNumber} · ${ep.name}'),
              subtitle: meta.isEmpty
                  ? null
                  : Text(
                      meta.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: username == null || username.isEmpty
                  ? Icon(
                      watched ? Icons.visibility : Icons.visibility_outlined,
                      color: Theme.of(context).colorScheme.outline,
                    )
                  : busy
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: watched ? 'Mark unwatched' : 'Mark watched',
                      icon: Icon(
                        watched ? Icons.visibility : Icons.visibility_outlined,
                        color: watched
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      onPressed: () => _toggleEpisode(
                        username: username,
                        episodeNumber: ep.episodeNumber,
                        toWatched: !watched,
                        episodeTitle: ep.name,
                      ),
                    ),
            );
          },
        );
      },
    );
  }
}

/// Still thumbnail used in episode lists and detail hero.
class SeriesEpisodeStill extends StatelessWidget {
  const SeriesEpisodeStill({super.key, this.url, this.width = 88, this.height = 50});

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _placeholder(context),
        ),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.movie_outlined, color: Theme.of(context).colorScheme.outline),
    );
  }
}
