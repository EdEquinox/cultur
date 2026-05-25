library;

import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/media/albums/album_detail/album_detail_page.dart';
import 'package:yamtrack/src/screens/media/albums/album_edit/album_edit_page.dart';

import '../page_transitions.dart';

List<GoRoute> buildAlbumRoutes() {
  return [
    GoRoute(
      path: '/albums/:mediaId',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: AlbumDetailPage(mediaId: mediaId),
        );
      },
    ),
    GoRoute(
      path: '/albums/:mediaId/edit',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: AlbumEditPage(mediaId: mediaId),
        );
      },
    ),
  ];
}
