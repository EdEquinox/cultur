/// Global [GoRouter.redirect] helpers (URL compatibility, not feature logic).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/library/library_enums.dart';

/// Maps legacy library paths that omit `movies`/`tv` to the canonical routes.
///
/// Returns a **location string** to navigate to, or `null` to leave navigation
/// unchanged. Kept for bookmarks and older deep links.
///
/// See also: [LibraryMediaScope] paths under `/library/movies/...` and `/library/tv/...`.
String? libraryLegacyRedirects(BuildContext context, GoRouterState state) {
  final loc = state.matchedLocation;

  String? redirectScopeCollections(LibraryMediaScope scope, String legacy, String canonical) {
    if (loc == '/library/$legacy') {
      return scope.path(canonical);
    }
    final prefix = '/library/${scope == LibraryMediaScope.movie ? 'movies' : 'tv'}/';
    if (loc == '$prefix$legacy') {
      return scope.path(canonical);
    }
    return null;
  }

  for (final entry in <(String, String)>[
    ('watchlist', LibraryCollectionKind.later.collectionPathSegment),
    ('watched', LibraryCollectionKind.finished.collectionPathSegment),
    ('collected', LibraryCollectionKind.owned.collectionPathSegment),
    ('doing', LibraryCollectionKind.doing.collectionPathSegment),
    ('left', LibraryCollectionKind.left.collectionPathSegment),
  ]) {
    final hit = redirectScopeCollections(LibraryMediaScope.movie, entry.$1, entry.$2) ??
        redirectScopeCollections(LibraryMediaScope.tv, entry.$1, entry.$2);
    if (hit != null) {
      return hit;
    }
  }

  if (loc == '/library/movies/doing' || loc == '/library/movies/left') {
    return LibraryMediaScope.movie.path(LibraryCollectionKind.later.collectionPathSegment);
  }

  if (loc == '/library/lists') {
    return '/library/movies/lists';
  }
  if (loc.startsWith('/library/lists/')) {
    final tail = loc.substring('/library/lists/'.length);
    if (tail.isNotEmpty && !tail.contains('/')) {
      return '/library/movies/lists/$tail';
    }
  }
  return null;
}
