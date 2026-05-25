import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/models/games/game_home_shelf_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';

final boardgamesPopularProvider = FutureProvider.autoDispose<CatalogListData>((ref) async {
  return ref.watch(
    boardgamesProvider(
      const CatalogBrowseRequest(section: 'popular', query: ''),
    ).future,
  );
});

final boardgamesNextToTryShelfProvider = FutureProvider.autoDispose
    .family<List<GameHomeShelfItem>, String>((ref, username) async {
  if (username.isEmpty) {
    return const [];
  }
  final data =
      await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.boardgame).future);
  final priority = <GameHomeShelfItem>[];
  final watchlist = <GameHomeShelfItem>[];
  final seen = <String>{};

  for (final tracking in data.items) {
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

void invalidateBoardgamesHomeCaches(WidgetRef ref, {required String username}) {
  if (username.isNotEmpty) {
    ref.invalidate(boardgamesNextToTryShelfProvider(username));
    ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.boardgame));
  }
  ref.invalidate(boardgamesPopularProvider);
}
