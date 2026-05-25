/// Profile, library import, personal lists, and tracking collection tabs.
library;

import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/screens/collections/tracking_collection_page.dart';
import 'package:yamtrack/src/screens/library/library_backup_page.dart';
import 'package:yamtrack/src/screens/library/library_external_import_page.dart';
import 'package:yamtrack/src/models/library/library_enums.dart';
import 'package:yamtrack/src/screens/lists/personal_list_detail_page.dart';
import 'package:yamtrack/src/screens/lists/personal_lists_page.dart';
import 'package:yamtrack/src/screens/profile/profile_page.dart';

import '../page_transitions.dart';

List<GoRoute> _scopeCollectionRoutes(LibraryMediaScope scope) {
  return [
    for (final kind in scope.collectionKinds)
      GoRoute(
        path: scope.path(kind.collectionPathSegment),
        pageBuilder: (context, state) => buildAppRouteTransitionPage(
          state: state,
          child: TrackingCollectionPage(
            kind: kind,
            mediaScope: scope,
          ),
        ),
      ),
  ];
}

/// [GoRoute] entries for `/profile` and `/library/...` (movies and TV scopes).
List<GoRoute> buildLibraryAndProfileRoutes() {
  return [
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const ProfilePage(),
      ),
    ),
    GoRoute(
      path: '/library/import',
      redirect: (context, state) => '/library/backup',
    ),
    GoRoute(
      path: '/library/backup',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const LibraryBackupPage(),
      ),
    ),
    GoRoute(
      path: '/library/external-import',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const LibraryExternalImportPage(),
      ),
    ),
    GoRoute(
      path: '/library/movies/lists',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const PersonalListsPage(mediaScope: LibraryMediaScope.movie),
      ),
    ),
    GoRoute(
      path: '/library/movies/lists/:listId',
      pageBuilder: (context, state) {
        final listId = state.pathParameters['listId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: PersonalListDetailPage(
            listId: listId,
            mediaScope: LibraryMediaScope.movie,
          ),
        );
      },
    ),
    ..._scopeCollectionRoutes(LibraryMediaScope.movie),
    GoRoute(
      path: '/library/tv/lists',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const PersonalListsPage(mediaScope: LibraryMediaScope.tv),
      ),
    ),
    GoRoute(
      path: '/library/tv/lists/:listId',
      pageBuilder: (context, state) {
        final listId = state.pathParameters['listId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: PersonalListDetailPage(
            listId: listId,
            mediaScope: LibraryMediaScope.tv,
          ),
        );
      },
    ),
    ..._scopeCollectionRoutes(LibraryMediaScope.tv),
    GoRoute(
      path: '/library/games/lists',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const PersonalListsPage(mediaScope: LibraryMediaScope.game),
      ),
    ),
    GoRoute(
      path: '/library/games/lists/:listId',
      pageBuilder: (context, state) {
        final listId = state.pathParameters['listId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: PersonalListDetailPage(
            listId: listId,
            mediaScope: LibraryMediaScope.game,
          ),
        );
      },
    ),
    ..._scopeCollectionRoutes(LibraryMediaScope.game),
    GoRoute(
      path: '/library/boardgames/lists',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const PersonalListsPage(mediaScope: LibraryMediaScope.boardgame),
      ),
    ),
    GoRoute(
      path: '/library/boardgames/lists/:listId',
      pageBuilder: (context, state) {
        final listId = state.pathParameters['listId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: PersonalListDetailPage(
            listId: listId,
            mediaScope: LibraryMediaScope.boardgame,
          ),
        );
      },
    ),
    ..._scopeCollectionRoutes(LibraryMediaScope.boardgame),
    GoRoute(
      path: '/library/books/lists',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const PersonalListsPage(mediaScope: LibraryMediaScope.book),
      ),
    ),
    GoRoute(
      path: '/library/books/lists/:listId',
      pageBuilder: (context, state) {
        final listId = state.pathParameters['listId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: PersonalListDetailPage(
            listId: listId,
            mediaScope: LibraryMediaScope.book,
          ),
        );
      },
    ),
    ..._scopeCollectionRoutes(LibraryMediaScope.book),
    GoRoute(
      path: '/library/albums/lists',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const PersonalListsPage(mediaScope: LibraryMediaScope.music),
      ),
    ),
    GoRoute(
      path: '/library/albums/lists/:listId',
      pageBuilder: (context, state) {
        final listId = state.pathParameters['listId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: PersonalListDetailPage(
            listId: listId,
            mediaScope: LibraryMediaScope.music,
          ),
        );
      },
    ),
    ..._scopeCollectionRoutes(LibraryMediaScope.music),
  ];
}
