/// Movie detail and person (TMDB) routes.
library;

import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';
import 'package:yamtrack/src/screens/media/movies/movie_detail/movie_cast_list_page.dart';
import 'package:yamtrack/src/screens/media/movies/movie_detail/movie_crew_list_page.dart';
import 'package:yamtrack/src/screens/media/movies/movie_detail/movie_detail_page.dart';
import 'package:yamtrack/src/screens/person/person_detail_page.dart';

import '../navigator_keys.dart';
import '../page_transitions.dart';

/// [GoRoute] entries for `/movies/...`, `/people/...`.
List<GoRoute> buildMovieAndPersonRoutes() {
  return [
    GoRoute(
      path: '/movies/:mediaId',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: MovieDetailPage(mediaId: mediaId),
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
              child: MovieCastListPage(mediaId: mediaId),
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
              child: MovieCrewListPage(mediaId: mediaId),
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/people/:personId',
      pageBuilder: (context, state) {
        final personId = personIdFromRouteParam(
          state.pathParameters['personId'] ?? '',
        );
        return buildAppRouteTransitionPage(
          state: state,
          child: PersonDetailPage(personId: personId),
        );
      },
    ),
  ];
}
