import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/models/games/game_home_shelf_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/pending_imports_providers.dart';

final albumsNextToListenShelfProvider = FutureProvider.autoDispose
    .family<List<GameHomeShelfItem>, String>((ref, username) async {
  if (username.isEmpty) {
    return const [];
  }
  final data = await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.music).future);
  final priority = <GameHomeShelfItem>[];
  final watchlist = <GameHomeShelfItem>[];
  final seen = <String>{};

  for (final tracking in data.items) {
    if (trackingIsDropped(tracking) || trackingIsWatched(tracking)) {
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

final albumsMusicLatestProvider = FutureProvider.autoDispose
    .family<List<CatalogItem>, String>((ref, username) async {
  if (username.isEmpty) {
    return const [];
  }
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson(
    '/catalog/music/home/latest',
    queryParameters: {'username': username},
  );
  return CatalogListData.fromJson(payload).items;
});

void invalidateAlbumsHomeCaches(WidgetRef ref, {required String username}) {
  if (username.isNotEmpty) {
    ref.invalidate(albumsNextToListenShelfProvider(username));
    ref.invalidate(albumsMusicLatestProvider(username));
    ref.invalidate(
      pendingImportsShelfProvider((username: username, scope: LibraryMediaScope.music)),
    );
    ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.music));
    ref.invalidate(customMusicListsProvider);
  }
}
