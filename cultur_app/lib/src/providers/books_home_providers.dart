import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/models/games/game_home_shelf_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/pending_imports_providers.dart';

final booksPopularProvider = FutureProvider.autoDispose<CatalogListData>((ref) async {
  return ref.watch(
    booksProvider(
      const CatalogBrowseRequest(section: 'popular', query: ''),
    ).future,
  );
});

final booksReadingShelfProvider = FutureProvider.autoDispose
    .family<List<GameHomeShelfItem>, String>((ref, username) async {
  if (username.isEmpty) {
    return const [];
  }
  final data = await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.book).future);
  final items = <GameHomeShelfItem>[];
  for (final tracking in data.items) {
    if (tracking.media.mediaType != 'book') {
      continue;
    }
    if (trackingIsDropped(tracking) || trackingIsWatched(tracking)) {
      continue;
    }
    if (!trackingIsInWatchingCollection(tracking)) {
      continue;
    }
    items.add(
      GameHomeShelfItem(
        tracking: tracking,
        inPriority: trackingIsPriority(tracking),
        inWatchlist: trackingIsInWatchlist(tracking),
      ),
    );
  }
  items.sort((a, b) {
    final ap = a.tracking.progress ?? 0;
    final bp = b.tracking.progress ?? 0;
    if (ap != bp) {
      return bp.compareTo(ap);
    }
    final au = a.tracking.updatedAt ?? a.tracking.createdAt;
    final bu = b.tracking.updatedAt ?? b.tracking.createdAt;
    if (au == null && bu == null) {
      return a.media.title.compareTo(b.media.title);
    }
    if (au == null) {
      return 1;
    }
    if (bu == null) {
      return -1;
    }
    return bu.compareTo(au);
  });
  return items.take(12).toList();
});

final booksNextToReadShelfProvider = FutureProvider.autoDispose
    .family<List<GameHomeShelfItem>, String>((ref, username) async {
  if (username.isEmpty) {
    return const [];
  }
  final data = await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.book).future);
  final priority = <GameHomeShelfItem>[];
  final watchlist = <GameHomeShelfItem>[];
  final seen = <String>{};

  for (final tracking in data.items) {
    if (tracking.media.mediaType != 'book') {
      continue;
    }
    if (trackingIsDropped(tracking) || trackingIsWatched(tracking)) {
      continue;
    }
    if (trackingIsInWatchingCollection(tracking)) {
      continue;
    }
    final isPriority = trackingIsPriority(tracking);
    final isWatchlist = trackingIsInWatchlist(tracking);
    if (!isPriority && !isWatchlist) {
      continue;
    }
    if (!seen.add(tracking.media.id)) {
      continue;
    }
    final row = GameHomeShelfItem(
      tracking: tracking,
      inPriority: isPriority,
      inWatchlist: isWatchlist,
    );
    if (isPriority) {
      priority.add(row);
    } else {
      watchlist.add(row);
    }
  }

  return [...priority, ...watchlist].take(12).toList();
});

void invalidateBooksHomeCaches(WidgetRef ref, {required String username}) {
  if (username.isNotEmpty) {
    ref.invalidate(booksReadingShelfProvider(username));
    ref.invalidate(booksNextToReadShelfProvider(username));
    ref.invalidate(
      pendingImportsShelfProvider((username: username, scope: LibraryMediaScope.book)),
    );
    ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.book));
  }
  ref.invalidate(booksPopularProvider);
}
