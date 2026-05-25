import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/games/game_home_shelf_item.dart';
import 'package:yamtrack/src/models/games/stash_game_event.dart';
import 'package:yamtrack/src/models/games/stash_game_event_detail.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/pending_imports_providers.dart';

enum StashEventsWindow { upcoming, previous }

extension StashEventsWindowApi on StashEventsWindow {
  String get apiValue => name;
}

final gamesPlayingShelfProvider = FutureProvider.autoDispose
    .family<List<GameHomeShelfItem>, String>((ref, username) async {
  if (username.isEmpty) {
    return const [];
  }
  final data = await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.game).future);
  final items = <GameHomeShelfItem>[];
  for (final tracking in data.items) {
    if (trackingIsDropped(tracking)) {
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

final gamesNextToPlayShelfProvider = FutureProvider.autoDispose
    .family<List<GameHomeShelfItem>, String>((ref, username) async {
  if (username.isEmpty) {
    return const [];
  }
  final data = await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.game).future);
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

final stashGameEventsProvider = FutureProvider.autoDispose
    .family<StashGameEventsListData, StashEventsWindow>((ref, window) async {
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson(
    '/catalog/games/events',
    queryParameters: {
      'window': window.apiValue,
      'offset': '0',
      'limit': '60',
    },
  );
  return StashGameEventsListData.fromJson(payload);
});

final stashGameEventDetailProvider = FutureProvider.autoDispose
    .family<StashGameEventDetail, String>((ref, slug) async {
  if (slug.isEmpty) {
    throw StateError('Event slug is required.');
  }
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson(
    '/catalog/games/events/$slug',
    queryParameters: {
      'offset': '0',
      'limit': '60',
    },
  );
  return StashGameEventDetail.fromJson(payload);
});

void invalidateGamesHomeCaches(WidgetRef ref, {required String username}) {
  if (username.isNotEmpty) {
    ref.invalidate(gamesPlayingShelfProvider(username));
    ref.invalidate(gamesNextToPlayShelfProvider(username));
    ref.invalidate(
      pendingImportsShelfProvider((username: username, scope: LibraryMediaScope.game)),
    );
    ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.game));
  }
  ref.invalidate(stashGameEventsProvider(StashEventsWindow.previous));
}
