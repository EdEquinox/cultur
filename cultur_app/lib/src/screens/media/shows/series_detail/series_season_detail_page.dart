import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';

import '../../../navbar/bar.dart';
import '../../../../utils/tmdb_links.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/movie/movie_detail_models.dart';
import 'package:yamtrack/src/providers/movie_detail_providers.dart';
import '../../../widgets/movie_tab_bar.dart';
import '../../../widgets/detail_director_card.dart';
import '../../../widgets/tv_detail_hero_nav_pill.dart';
import 'package:yamtrack/src/models/tv/series_detail.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';
import 'series_season_episodes_list.dart';
import 'tv_show_nested_detail_sections.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Season overview + episodes, following the same tab pattern as [SeriesDetailPage].
class SeriesSeasonDetailPage extends ConsumerStatefulWidget {
  const SeriesSeasonDetailPage({
    required this.mediaId,
    required this.seasonNumber,
    super.key,
  });

  final String mediaId;
  final int seasonNumber;

  @override
  ConsumerState<SeriesSeasonDetailPage> createState() => _SeriesSeasonDetailPageState();
}

class _SeriesSeasonDetailPageState extends ConsumerState<SeriesSeasonDetailPage> {
  int _tabIndex = 0;

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

    final showTitle = showAsync.asData?.value.media.title;

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
                      TmdbLinks.tvSeason(externalId, widget.seasonNumber),
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
        data: (detail) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MovieTabBar(
                  selectedIndex: _tabIndex,
                  tabs: const ['Details', 'Episodes'],
                  onSelected: (i) => setState(() => _tabIndex = i),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previousChildren,
                          ...switch (currentChild) {
                            final Widget child => [child],
                            null => const <Widget>[],
                          },
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_tabIndex),
                      child: _tabIndex == 0
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 120),
                              child: _SeasonDetailsBody(
                                detail: detail,
                                showTitle: showTitle ?? '',
                                showDetail: showAsync.asData?.value,
                                mediaId: widget.mediaId,
                                onAfterTrackingMutation: () {
                                  ref.invalidate(tvSeasonDetailCatalogProvider(seasonRequest));
                                },
                              ),
                            )
                          : SeriesSeasonEpisodesList(
                              mediaId: widget.mediaId,
                              seasonNumber: widget.seasonNumber,
                              onEpisodeTap: (ep) => context.push(
                                '/tv/${widget.mediaId}/seasons/${widget.seasonNumber}/episodes/${ep.episodeNumber}',
                              ),
                              padding: const EdgeInsets.only(bottom: 120),
                            ),
                    ),
                  ),
                ),
              ],
            ),
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

class _SeasonDetailsBody extends StatelessWidget {
  const _SeasonDetailsBody({
    required this.detail,
    required this.mediaId,
    required this.showTitle,
    this.showDetail,
    this.onAfterTrackingMutation,
  });

  final TvSeasonDetailData detail;
  final String mediaId;
  final String showTitle;
  final MovieCatalogDetail? showDetail;
  final VoidCallback? onAfterTrackingMutation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = context.culturTokens.radiusTight;
    final overview = detail.overview?.trim() ?? '';
    final meta = <String>[
      if (detail.airDate != null && detail.airDate!.trim().isNotEmpty) detail.airDate!.trim(),
      '${detail.episodes.length} episode${detail.episodes.length == 1 ? '' : 's'}',
      if (detail.ratings.isNotEmpty) 'TMDB ${double.tryParse(detail.ratings.first.value.replaceAll('TMDB ', ''))?.toStringAsFixed(1)}',
    ];

    final directorPeople = directorPeopleForSeason(
      seasonDirectors: detail.directors,
      showDetail: showDetail,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (detail.posterUrl != null && detail.posterUrl!.trim().isNotEmpty)
                  Image.network(
                    detail.posterUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: theme.colorScheme.surfaceContainerHigh,
                      child: Icon(Icons.tv_outlined, size: 48, color: theme.colorScheme.outline),
                    ),
                  )
                else
                  ColoredBox(
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: Icon(Icons.tv_outlined, size: 48, color: theme.colorScheme.outline),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.scrim.withValues(alpha: 0.1),
                          scheme.scrim.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: TvDetailHeroNavPill(
                    label: showTitle.trim().isNotEmpty ? showTitle.trim() : 'Series',
                    targetLocation: '/tv/$mediaId',
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
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            meta.join(' · '),
                            style: CulturCatalogTypography.listMeta(theme, scheme),
                          ),
                        ),
                      Text(
                        detail.name.trim().isNotEmpty ? detail.name : 'Season ${detail.seasonNumber}',
                        style: CulturCatalogTypography.listTitleBig(theme),
                      ),
                      if (directorPeople.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        DetailDirectorPeopleCard(people: directorPeople),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showDetail case final sd?) ...[
          const SizedBox(height: 16),
          TvShowTrackingActionBar(
            mediaId: mediaId,
            detail: sd,
            watchScopeSeasonDetail: detail,
            watchScopeSeasonNumber: detail.seasonNumber,
            onAfterTrackingMutation: onAfterTrackingMutation,
          ),
          const SizedBox(height: 16),
          TvShowCastPreviewStrip(
            detail: sd,
            mediaId: mediaId,
            castBase: detail.cast,
            additionalPeople: detail.distinctGuestStarsAcrossEpisodes(),
            viewAllCastPath: '/tv/$mediaId/seasons/${detail.seasonNumber}/cast',
          ),
        ],
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                overview,
                style: CulturCatalogTypography.bodyText(theme, scheme),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
