import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/utils/tmdb_links.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/movie/movie_detail_models.dart';
import 'package:yamtrack/src/providers/movie_detail_providers.dart';
import 'package:yamtrack/src/screens/widgets/detail_director_card.dart';
import 'package:yamtrack/src/screens/widgets/tv_detail_hero_nav_pill.dart';
import 'package:yamtrack/src/models/tv/series_detail.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';
import 'tv_show_nested_detail_sections.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class SeriesEpisodeDetailPage extends ConsumerStatefulWidget {
  const SeriesEpisodeDetailPage({
    required this.mediaId,
    required this.seasonNumber,
    required this.episodeNumber,
    super.key,
  });

  final String mediaId;
  final int seasonNumber;
  final int episodeNumber;

  @override
  ConsumerState<SeriesEpisodeDetailPage> createState() => _SeriesEpisodeDetailPageState();
}

class _SeriesEpisodeDetailPageState extends ConsumerState<SeriesEpisodeDetailPage> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final showRequest = MovieDetailRequest(
      mediaId: widget.mediaId,
      username: username,
      isTv: true,
    );
    final showAsync = ref.watch(movieDetailProvider(showRequest));
    final seasonRequest = TvSeasonDetailCatalogRequest(
      mediaId: widget.mediaId,
      seasonNumber: widget.seasonNumber,
      username: username,
    );
    final seasonAsync = ref.watch(tvSeasonDetailCatalogProvider(seasonRequest));
    final epRequest = TvEpisodeDetailCatalogRequest(
      mediaId: widget.mediaId,
      seasonNumber: widget.seasonNumber,
      episodeNumber: widget.episodeNumber,
      username: username,
    );
    final epAsync = ref.watch(tvEpisodeDetailCatalogProvider(epRequest));
    final externalId = showAsync.asData?.value.media.externalId;

    return Scaffold(
      appBar: CulturAppBar(
        additionalActions: [
          IconButton(
            tooltip: 'Open on TMDB',
            onPressed: externalId == null
                ? null
                : () => TmdbLinks.launchWithSnackBarOnFailure(
                      context,
                      TmdbLinks.tvEpisode(externalId, widget.seasonNumber, widget.episodeNumber),
                    ),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      extendBody: true,
      body: seasonAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(tvSeasonDetailCatalogProvider(seasonRequest)),
        ),
        data: (season) {
          TvEpisodeCatalog? ep;
          for (final e in season.episodes) {
            if (e.episodeNumber == widget.episodeNumber) {
              ep = e;
              break;
            }
          }
          if (ep == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Episode S${widget.seasonNumber}E${widget.episodeNumber} was not found in this season.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final episode = ep;
          final showDetail = showAsync.asData?.value;
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final r = context.culturTokens.radiusTight;
          final meta = <String>[
            'S${widget.seasonNumber.toString().padLeft(2, '0')}E${episode.episodeNumber.toString().padLeft(2, '0')}',
            if (episode.airDate != null && episode.airDate!.trim().isNotEmpty) episode.airDate!.trim(),
            if (episode.runtimeMinutes != null) '${episode.runtimeMinutes} min',
            if (episode.voteAverage != null) 'TMDB ${episode.voteAverage!.toStringAsFixed(1)}',
          ];

          final epDirs = epAsync.maybeWhen(
            data: (d) => d.directors,
            orElse: () => <MovieDetailPerson>[],
          );
          final people = directorPeopleForEpisode(
            episodeDirectors: epDirs,
            showDetail: showDetail,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(r),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (episode.stillUrl != null && episode.stillUrl!.trim().isNotEmpty)
                        Image.network(
                          episode.stillUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _EpisodeHeroFallback(
                            posterUrl: season.posterUrl,
                          ),
                        )
                      else
                        _EpisodeHeroFallback(posterUrl: season.posterUrl),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                scheme.scrim.withValues(alpha: 0.08),
                                scheme.scrim.withValues(alpha: 0.75),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        top: 14,
                        child: TvDetailHeroNavPill(
                          label: season.name.trim().isNotEmpty
                              ? season.name.trim()
                              : 'Season ${widget.seasonNumber}',
                          targetLocation:
                              '/tv/${widget.mediaId}/seasons/${widget.seasonNumber}',
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              meta.join(' · '),
                              style: CulturCatalogTypography.listMeta(theme, scheme),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              episode.name.trim().isNotEmpty ? episode.name : 'Episode ${episode.episodeNumber}',
                              style: CulturCatalogTypography.listTitleBig(theme),
                            ),
                            if (people.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              DetailDirectorPeopleCard(people: people),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (showDetail != null) ...[
                TvShowTrackingActionBar(
                  mediaId: widget.mediaId,
                  detail: showDetail,
                  watchScopeEpisode: episode,
                  watchScopeSeasonDetail: season,
                  watchScopeSeasonNumber: widget.seasonNumber,
                  watchScopeEpisodeUserRating: epAsync.asData?.value.userRating ?? episode.userRating,
                  onAfterTrackingMutation: () {
                    ref.invalidate(tvSeasonDetailCatalogProvider(seasonRequest));
                    ref.invalidate(tvEpisodeDetailCatalogProvider(epRequest));
                  },
                ),
                const SizedBox(height: 16),
                if (episode.overview != null && episode.overview!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        episode.overview!.trim(),
                        style: CulturCatalogTypography.bodyText(theme, scheme),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                epAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (ed) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TvShowCastPreviewStrip(
                          detail: showDetail,
                          mediaId: widget.mediaId,
                          castBase: ed.cast,
                          additionalPeople: ed.guestStars,
                          viewAllCastPath:
                              '/tv/${widget.mediaId}/seasons/${widget.seasonNumber}/episodes/${widget.episodeNumber}/cast',
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.tv,
      ),
    );
  }
}

class _EpisodeHeroFallback extends StatelessWidget {
  const _EpisodeHeroFallback({this.posterUrl});

  final String? posterUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (posterUrl != null && posterUrl!.trim().isNotEmpty) {
      return Image.network(
        posterUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => ColoredBox(
          color: theme.colorScheme.surfaceContainerHigh,
          child: Icon(Icons.movie_outlined, size: 48, color: theme.colorScheme.outline),
        ),
      );
    }
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Icon(Icons.movie_outlined, size: 48, color: theme.colorScheme.outline),
    );
  }
}
