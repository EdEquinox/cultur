/// Root, shelf, and category catalog routes (`/`, `/shelves/...`, `/category/...`).
library;

import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/auth/auth_gate.dart';
import 'package:yamtrack/src/screens/home/category_page.dart';
import 'package:yamtrack/src/screens/home/home_shelf_list_page.dart';

import '../page_transitions.dart';

/// [GoRoute] entries for auth gate and catalog browsing.
///
/// Order: `/` first, then more specific paths before broader ones where relevant.
List<GoRoute> buildRootAndCatalogRoutes() {
  return [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => buildAppRouteTransitionPage(
        state: state,
        child: const AuthGatePage(),
      ),
    ),
    GoRoute(
      path: '/shelves/:scope/:shelf',
      pageBuilder: (context, state) {
        final scope = state.pathParameters['scope'] ?? '';
        final shelf = state.pathParameters['shelf'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: HomeShelfListPage(scope: scope, shelf: shelf),
        );
      },
    ),
    GoRoute(
      path: '/category/:categoryId',
      pageBuilder: (context, state) {
        final categoryId = state.pathParameters['categoryId'] ?? '';
        final initialQuery = state.uri.queryParameters['q'] ?? '';
        final initialGenre = state.uri.queryParameters['genre'] ?? '';
        final initialKeyword = state.uri.queryParameters['keyword'] ?? '';
        final initialSection = state.uri.queryParameters['section'] ?? '';
        final initialCompanyId = state.uri.queryParameters['companyId'] ?? '';
        final initialCompanyRole = state.uri.queryParameters['companyRole'] ?? '';
        final initialCompanyName = state.uri.queryParameters['companyName'] ?? '';
        final initialFranchiseId = state.uri.queryParameters['franchiseId'] ?? '';
        final initialCollectionId = state.uri.queryParameters['collectionId'] ?? '';
        final initialBrowseName = state.uri.queryParameters['browseName'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: CategoryPage(
            categoryId: categoryId,
            initialQuery: initialQuery,
            initialGenre: initialGenre,
            initialKeyword: initialKeyword,
            initialSection: initialSection,
            initialCompanyId: initialCompanyId,
            initialCompanyRole: initialCompanyRole,
            initialCompanyName: initialCompanyName,
            initialFranchiseId: initialFranchiseId,
            initialCollectionId: initialCollectionId,
            initialBrowseName: initialBrowseName,
          ),
        );
      },
    ),
  ];
}
