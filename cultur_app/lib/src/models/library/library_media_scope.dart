import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'library_enums.dart';

/// Which medium the library bottom bar and collection routes refer to.
enum LibraryMediaScope {
  movie,
  tv,
  game,
  boardgame,
  book,
  music,
}

/// Collection tabs exposed per medium (movies omit TV-only queues).
extension LibraryMediaScopeCollections on LibraryMediaScope {
  List<LibraryCollectionKind> get collectionKinds => switch (this) {
        LibraryMediaScope.movie => const [
          LibraryCollectionKind.later,
          LibraryCollectionKind.buy,
          LibraryCollectionKind.finished,
          LibraryCollectionKind.owned,
        ],
        LibraryMediaScope.music => const [
          LibraryCollectionKind.later,
          LibraryCollectionKind.buy,
          LibraryCollectionKind.finished,
          LibraryCollectionKind.owned,
        ],
        LibraryMediaScope.game => const [
          LibraryCollectionKind.later,
          LibraryCollectionKind.doing,
          LibraryCollectionKind.buy,
          LibraryCollectionKind.finished,
          LibraryCollectionKind.owned,
          LibraryCollectionKind.left,
        ],
        LibraryMediaScope.boardgame => const [
          LibraryCollectionKind.later,
          LibraryCollectionKind.buy,
          LibraryCollectionKind.owned,
        ],
        LibraryMediaScope.book => const [
          LibraryCollectionKind.later,
          LibraryCollectionKind.buy,
          LibraryCollectionKind.finished,
          LibraryCollectionKind.owned,
          LibraryCollectionKind.doing,
          LibraryCollectionKind.left,
        ],
        LibraryMediaScope.tv => LibraryCollectionKind.values,
      };
}

/// Infers the active medium from the current route (library, detail, browse, or home).
LibraryMediaScope libraryMediaScopeFromRoute(Uri uri) {
  final path = uri.path;
  if (path.startsWith('/shelves/')) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return switch (parts[1]) {
        'tv' => LibraryMediaScope.tv,
        'games' => LibraryMediaScope.game,
        'board-games' => LibraryMediaScope.boardgame,
        'books' => LibraryMediaScope.book,
        'albums' => LibraryMediaScope.music,
        'movies' => LibraryMediaScope.movie,
        _ => LibraryMediaScope.movie,
      };
    }
  }
  if (path.startsWith('/library/tv')) {
    return LibraryMediaScope.tv;
  }
  if (path.startsWith('/library/games')) {
    return LibraryMediaScope.game;
  }
  if (path.startsWith('/library/boardgames')) {
    return LibraryMediaScope.boardgame;
  }
  if (path.startsWith('/library/books')) {
    return LibraryMediaScope.book;
  }
  if (path.startsWith('/library/albums')) {
    return LibraryMediaScope.music;
  }
  if (path.startsWith('/library/movies')) {
    return LibraryMediaScope.movie;
  }
  if (path.startsWith('/category/series')) {
    return LibraryMediaScope.tv;
  }
  if (path.startsWith('/category/games')) {
    return LibraryMediaScope.game;
  }
  if (path.startsWith('/category/board-games')) {
    return LibraryMediaScope.boardgame;
  }
  if (path.startsWith('/category/books')) {
    return LibraryMediaScope.book;
  }
  if (path.startsWith('/category/albums')) {
    return LibraryMediaScope.music;
  }
  if (path.startsWith('/category/movies')) {
    return LibraryMediaScope.movie;
  }
  if (path.startsWith('/tv/')) {
    return LibraryMediaScope.tv;
  }
  if (path.startsWith('/games/')) {
    return LibraryMediaScope.game;
  }
  if (path.startsWith('/boardgames/')) {
    return LibraryMediaScope.boardgame;
  }
  if (path.startsWith('/books/')) {
    return LibraryMediaScope.book;
  }
  if (path.startsWith('/albums/')) {
    return LibraryMediaScope.music;
  }
  if (path.startsWith('/movies/')) {
    return LibraryMediaScope.movie;
  }
  if (path == '/' || path.isEmpty) {
    return switch (uri.queryParameters['category']) {
      'series' => LibraryMediaScope.tv,
      'games' => LibraryMediaScope.game,
      'board-games' => LibraryMediaScope.boardgame,
      'books' => LibraryMediaScope.book,
      'albums' => LibraryMediaScope.music,
      _ => LibraryMediaScope.movie,
    };
  }
  return LibraryMediaScope.movie;
}

bool libraryIsOnCatalogHome(GoRouterState state, LibraryMediaScope scope) {
  if (state.uri.path != '/') {
    return false;
  }
  final category = state.uri.queryParameters['category'];
  return switch (scope) {
    LibraryMediaScope.movie => category == null || category == 'movies',
    LibraryMediaScope.tv => category == 'series',
    LibraryMediaScope.game => category == 'games',
    LibraryMediaScope.boardgame => category == 'board-games',
    LibraryMediaScope.book => category == 'books',
    LibraryMediaScope.music => category == 'albums',
  };
}

extension LibraryMediaScopePaths on LibraryMediaScope {
  String get trackingApiMediaType => switch (this) {
        LibraryMediaScope.movie => 'movie',
        LibraryMediaScope.tv => 'tv',
        LibraryMediaScope.game => 'game',
        LibraryMediaScope.boardgame => 'boardgame',
        LibraryMediaScope.book => 'book',
        LibraryMediaScope.music => 'music',
      };

  /// Base path without trailing slash, e.g. `/library/movies`.
  String get libraryBasePath => switch (this) {
        LibraryMediaScope.movie => '/library/movies',
        LibraryMediaScope.tv => '/library/tv',
        LibraryMediaScope.game => '/library/games',
        LibraryMediaScope.boardgame => '/library/boardgames',
        LibraryMediaScope.book => '/library/books',
        LibraryMediaScope.music => '/library/albums',
      };

  String path(String segment) {
    final s = segment.startsWith('/') ? segment.substring(1) : segment;
    return '$libraryBasePath/$s';
  }

  /// Route for the catalog home when tapping Home in the bottom bar.
  String get catalogHomePath => switch (this) {
        LibraryMediaScope.movie => '/',
        LibraryMediaScope.tv => '/?category=series',
        LibraryMediaScope.game => '/?category=games',
        LibraryMediaScope.boardgame => '/?category=board-games',
        LibraryMediaScope.book => '/?category=books',
        LibraryMediaScope.music => '/?category=albums',
      };

  /// Full catalog browse / search screen for this medium.
  String get catalogBrowsePath => switch (this) {
        LibraryMediaScope.movie => '/category/movies',
        LibraryMediaScope.tv => '/category/series',
        LibraryMediaScope.game => '/category/games',
        LibraryMediaScope.boardgame => '/category/board-games',
        LibraryMediaScope.book => '/category/books',
        LibraryMediaScope.music => '/category/albums',
      };
}

/// Bottom-bar icon + short label per collection tab ([FloatingLibraryNav]).
extension LibraryMediaScopeNav on LibraryMediaScope {
  (IconData icon, String label) collectionNavLabel(LibraryCollectionKind kind) {
    return switch (this) {
      LibraryMediaScope.music => switch (kind) {
          LibraryCollectionKind.later => (Icons.bookmark_border_outlined, 'Later'),
          LibraryCollectionKind.buy => (Icons.shopping_bag_outlined, 'Buy'),
          LibraryCollectionKind.finished => (Icons.headphones_outlined, 'Listened'),
          LibraryCollectionKind.owned => (Icons.inventory_2_outlined, 'Owned'),
          LibraryCollectionKind.doing => (Icons.album_outlined, 'Listening'),
          LibraryCollectionKind.left => (Icons.flag_outlined, 'Dropped'),
        },
      LibraryMediaScope.game => switch (kind) {
          LibraryCollectionKind.later => (Icons.bookmark_border_outlined, 'Later'),
          LibraryCollectionKind.doing => (Icons.sports_esports_outlined, 'Playing'),
          LibraryCollectionKind.buy => (Icons.shopping_bag_outlined, 'Buy'),
          LibraryCollectionKind.finished => (Icons.check_circle_outline, 'Played'),
          LibraryCollectionKind.owned => (Icons.inventory_2_outlined, 'Owned'),
          LibraryCollectionKind.left => (Icons.flag_outlined, 'Dropped'),
        },
      LibraryMediaScope.boardgame => switch (kind) {
          LibraryCollectionKind.later => (Icons.bookmark_border_outlined, 'Later'),
          LibraryCollectionKind.buy => (Icons.shopping_bag_outlined, 'Buy'),
          LibraryCollectionKind.owned => (Icons.inventory_2_outlined, 'Owned'),
          LibraryCollectionKind.doing => (Icons.sports_esports_outlined, 'Playing'),
          LibraryCollectionKind.finished => (Icons.check_circle_outline, 'Played'),
          LibraryCollectionKind.left => (Icons.flag_outlined, 'Dropped'),
        },
      LibraryMediaScope.book => switch (kind) {
          LibraryCollectionKind.later => (Icons.bookmark_border_outlined, 'Later'),
          LibraryCollectionKind.buy => (Icons.shopping_bag_outlined, 'Buy'),
          LibraryCollectionKind.finished => (Icons.check_circle_outline, 'Read'),
          LibraryCollectionKind.owned => (Icons.inventory_2_outlined, 'Owned'),
          LibraryCollectionKind.doing => (Icons.menu_book_outlined, 'Reading'),
          LibraryCollectionKind.left => (Icons.flag_outlined, 'Dropped'),
        },
      LibraryMediaScope.tv => switch (kind) {
          LibraryCollectionKind.later => (Icons.bookmark_border_outlined, 'Later'),
          LibraryCollectionKind.doing => (Icons.play_circle_outline, 'Watching'),
          LibraryCollectionKind.buy => (Icons.shopping_bag_outlined, 'Buy'),
          LibraryCollectionKind.finished => (Icons.check_circle_outline, 'Watched'),
          LibraryCollectionKind.owned => (Icons.inventory_2_outlined, 'Collected'),
          LibraryCollectionKind.left => (Icons.flag_outlined, 'Dropped'),
        },
      LibraryMediaScope.movie => switch (kind) {
          LibraryCollectionKind.later => (Icons.bookmark_border_outlined, 'Later'),
          LibraryCollectionKind.buy => (Icons.shopping_bag_outlined, 'Buy'),
          LibraryCollectionKind.finished => (Icons.check_circle_outline, 'Watched'),
          LibraryCollectionKind.owned => (Icons.inventory_2_outlined, 'Collected'),
          LibraryCollectionKind.doing => (Icons.play_circle_outline, 'Watching'),
          LibraryCollectionKind.left => (Icons.flag_outlined, 'Dropped'),
        },
    };
  }

  /// Page title for a library collection ([TrackingCollectionPage] app bar).
  String collectionPageTitle(LibraryCollectionKind kind) =>
      collectionNavLabel(kind).$2;
}
