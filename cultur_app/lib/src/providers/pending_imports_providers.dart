import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/models/games/game_home_shelf_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';

final pendingImportsShelfProvider = FutureProvider.autoDispose
    .family<List<GameHomeShelfItem>, ({String username, LibraryMediaScope scope})>(
  (ref, args) async {
    if (args.username.isEmpty) {
      return const [];
    }
    final expectedType = args.scope.trackingApiMediaType;
    final data = await ref.watch(libraryTrackingForScopeProvider(args.scope).future);
    final items = <GameHomeShelfItem>[];
    for (final tracking in data.items) {
      if (tracking.media.mediaType.toLowerCase() != expectedType) {
        continue;
      }
      if (!tracking.media.isCatalogPending) {
        continue;
      }
      items.add(
        GameHomeShelfItem(
          tracking: tracking,
          inPriority: false,
          inWatchlist: false,
        ),
      );
    }
    items.sort(
      (a, b) => a.media.title.toLowerCase().compareTo(b.media.title.toLowerCase()),
    );
    return items.take(12).toList();
  },
);
