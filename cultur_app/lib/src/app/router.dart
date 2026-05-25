/// Application routing: composes [GoRouter] from domain route modules under
/// `lib/src/app/router/`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router/navigator_keys.dart';
import 'router/router_redirects.dart';
import 'router/routes/library_profile_routes.dart';
import 'router/routes/album_routes.dart';
import 'router/routes/boardgame_routes.dart';
import 'router/routes/book_routes.dart';
import 'router/routes/game_routes.dart';
import 'router/routes/movie_person_routes.dart';
import 'router/routes/root_catalog_routes.dart';
import 'router/routes/tv_routes.dart';

/// Riverpod provider for the root [GoRouter].
///
/// [redirect] applies [libraryLegacyRedirects] for old library URLs.
/// [routes] are built from [buildRootAndCatalogRoutes], [buildTvRoutes],
/// [buildMovieAndPersonRoutes], and [buildLibraryAndProfileRoutes] — order
/// matches the previous monolithic router (specific paths before general ones).
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    redirect: libraryLegacyRedirects,
    routes: [
      ...buildRootAndCatalogRoutes(),
      ...buildMovieAndPersonRoutes(),
      ...buildTvRoutes(),
      ...buildGameRoutes(),
      ...buildBoardgameRoutes(),
      ...buildAlbumRoutes(),
      ...buildBookRoutes(),
      ...buildLibraryAndProfileRoutes(),
    ],
  );
});
