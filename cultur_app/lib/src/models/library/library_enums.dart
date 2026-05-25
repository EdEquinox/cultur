/// Canonical tracking tabs under each [LibraryMediaScope] (`/library/movies/...`, `/library/tv/...`).
///
/// Stored flags in `[cult.flags]` still use `watchlist`, `watched`, `collected`, `dropped`; `doing` and
/// `buy` are extra flags. [LibraryCollectionKind.left] maps to the existing `dropped` flag.
enum LibraryCollectionKind { later, buy, finished, owned, doing, left }

extension LibraryCollectionKindRoute on LibraryCollectionKind {
  /// Last URL segment for [LibraryMediaScope.path], e.g. `later` → `/library/movies/later`.
  String get collectionPathSegment => switch (this) {
        LibraryCollectionKind.later => 'later',
        LibraryCollectionKind.buy => 'buy',
        LibraryCollectionKind.doing => 'doing',
        LibraryCollectionKind.finished => 'finished',
        LibraryCollectionKind.owned => 'owned',
        LibraryCollectionKind.left => 'left',
      };
}

/// Drives which **restricted** filters are offered (watched date, metadata).
/// Universal filters (e.g. genres) apply on every surface.
enum LibraryFilterSurface {
  /// `/library/.../later|buy|doing|finished|owned|left`
  tracking,

  /// `/library/.../lists/:listId` (custom lists)
  personalList,
}

enum LibraryViewMode { detailed, compact, grid, posters }
