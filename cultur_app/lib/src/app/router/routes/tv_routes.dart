/// TV show stack routes under `/tv/:mediaId/...`.
///
/// More specific paths (season/episode/cast) are registered before `/tv/:mediaId`
/// so [GoRouter] matches the longest pattern first.
library;

import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/media/movies/movie_detail/movie_cast_list_page.dart';
import 'package:yamtrack/src/screens/media/movies/movie_detail/movie_crew_list_page.dart';
import 'package:yamtrack/src/screens/media/shows/series_detail/series_episode_detail_page.dart';
import 'package:yamtrack/src/screens/media/shows/series_detail/series_season_detail_page.dart';
import 'package:yamtrack/src/screens/media/shows/series_detail/series_detail_page.dart';
import 'package:yamtrack/src/screens/media/shows/series_detail/series_seasons_list_page.dart';
import 'package:yamtrack/src/screens/media/shows/series_detail/tv_context_cast_list_page.dart';

import '../navigator_keys.dart';
import '../page_transitions.dart';

/// [GoRoute] list for series detail, seasons, episodes, and TV-scoped cast lists.
List<GoRoute> buildTvRoutes() {
  return [
    GoRoute(
      path: '/tv/:mediaId/seasons/:seasonNumber/episodes/:episodeNumber/cast',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        final seasonRaw = state.pathParameters['seasonNumber'] ?? '';
        final epRaw = state.pathParameters['episodeNumber'] ?? '';
        final seasonNumber = int.tryParse(seasonRaw) ?? 0;
        final episodeNumber = int.tryParse(epRaw) ?? 0;
        return buildAppRouteTransitionPage(
          state: state,
          child: TvContextCastListPage(
            mediaId: mediaId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
          ),
        );
      },
    ),
    GoRoute(
      path: '/tv/:mediaId/seasons/:seasonNumber/cast',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        final raw = state.pathParameters['seasonNumber'] ?? '';
        final seasonNumber = int.tryParse(raw) ?? 0;
        return buildAppRouteTransitionPage(
          state: state,
          child: TvContextCastListPage(
            mediaId: mediaId,
            seasonNumber: seasonNumber,
          ),
        );
      },
    ),
    GoRoute(
      path: '/tv/:mediaId/seasons/:seasonNumber/episodes/:episodeNumber',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        final seasonRaw = state.pathParameters['seasonNumber'] ?? '';
        final epRaw = state.pathParameters['episodeNumber'] ?? '';
        final seasonNumber = int.tryParse(seasonRaw) ?? 0;
        final episodeNumber = int.tryParse(epRaw) ?? 0;
        return buildAppRouteTransitionPage(
          state: state,
          child: SeriesEpisodeDetailPage(
            mediaId: mediaId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
          ),
        );
      },
    ),
    GoRoute(
      path: '/tv/:mediaId/seasons/:seasonNumber',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        final raw = state.pathParameters['seasonNumber'] ?? '';
        final seasonNumber = int.tryParse(raw) ?? 0;
        return buildAppRouteTransitionPage(
          state: state,
          child: SeriesSeasonDetailPage(
            mediaId: mediaId,
            seasonNumber: seasonNumber,
          ),
        );
      },
    ),
    GoRoute(
      path: '/tv/:mediaId/seasons',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: SeriesSeasonsListPage(mediaId: mediaId),
        );
      },
    ),
    GoRoute(
      path: '/tv/:mediaId',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: SeriesDetailPage(mediaId: mediaId),
        );
      },
      routes: [
        GoRoute(
          path: 'cast',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) {
            final mediaId = state.pathParameters['mediaId'] ?? '';
            return buildAppRouteTransitionPage(
              state: state,
              child: MovieCastListPage(mediaId: mediaId, isTv: true),
            );
          },
        ),
        GoRoute(
          path: 'crew',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) {
            final mediaId = state.pathParameters['mediaId'] ?? '';
            return buildAppRouteTransitionPage(
              state: state,
              child: MovieCrewListPage(mediaId: mediaId, isTv: true),
            );
          },
        ),
      ],
    ),
  ];
}
