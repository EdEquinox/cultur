library;

import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/media/boardgames/boardgame_detail/boardgame_detail_page.dart';

import '../page_transitions.dart';

List<GoRoute> buildBoardgameRoutes() {
  return [
    GoRoute(
      path: '/boardgames/:mediaId',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: BoardgameDetailPage(mediaId: mediaId),
        );
      },
    ),
  ];
}
