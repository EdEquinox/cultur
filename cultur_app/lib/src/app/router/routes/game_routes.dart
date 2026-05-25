/// Video game catalog detail routes (IGDB).
library;

import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/company/company_detail_page.dart';
import 'package:yamtrack/src/screens/media/games/events/game_event_detail_page.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/game_detail_page.dart';

import '../page_transitions.dart';

List<GoRoute> buildGameRoutes() {
  return [
    GoRoute(
      path: '/games/events/:slug',
      pageBuilder: (context, state) {
        final slug = state.pathParameters['slug'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: GameEventDetailPage(slug: slug),
        );
      },
    ),
    GoRoute(
      path: '/games/companies/:companyId',
      pageBuilder: (context, state) {
        final companyId = state.pathParameters['companyId'] ?? '';
        final role = state.uri.queryParameters['role'] ?? 'publisher';
        final name = state.uri.queryParameters['name'];
        return buildAppRouteTransitionPage(
          state: state,
          child: CompanyDetailPage(
            companyId: companyId,
            role: role,
            initialName: name,
          ),
        );
      },
    ),
    GoRoute(
      path: '/games/:mediaId',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: GameDetailPage(mediaId: mediaId),
        );
      },
    ),
  ];
}
