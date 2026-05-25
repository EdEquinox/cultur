import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/models/tracking/tracking_models.dart' show trackingIsDropped, trackingIsPriority;
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/utils/library_utils.dart';

class NextToWatchShelfItem {
  const NextToWatchShelfItem({
    required this.media,
    required this.inPriority,
    required this.inCinema,
  });

  final CatalogItem media;
  final bool inPriority;
  final bool inCinema;
}

final nextToWatchShelfProvider = FutureProvider.autoDispose
    .family<List<NextToWatchShelfItem>, String>((ref, username) async {
      if (username.isEmpty) {
        return const [];
      }
      final data = await ref.watch(customMovieListsProvider.future);
      CustomMovieList? priority;
      CustomMovieList? cinema;
      for (final list in data.lists) {
        if (list.id == BuiltInMovieLists.priorityListId) {
          priority = list;
        } else if (list.id == BuiltInMovieLists.cinemaListId) {
          cinema = list;
        }
      }
      final cinemaIds = {
        for (final item in cinema?.items ?? const <CatalogItem>[]) item.id,
      };
      final seen = <String>{};
      final out = <NextToWatchShelfItem>[];
      for (final item in priority?.items ?? const <CatalogItem>[]) {
        if (seen.add(item.id)) {
          final inC = cinemaIds.contains(item.id);
          out.add(
            NextToWatchShelfItem(
              media: item,
              inPriority: true,
              inCinema: inC,
            ),
          );
        }
      }
      for (final item in cinema?.items ?? const <CatalogItem>[]) {
        if (seen.add(item.id)) {
          out.add(
            NextToWatchShelfItem(
              media: item,
              inPriority: false,
              inCinema: true,
            ),
          );
        }
      }
      return out.take(10).toList();
    });

final tvNextToWatchShelfProvider = FutureProvider.autoDispose
    .family<List<NextToWatchShelfItem>, String>((ref, username) async {
      if (username.isEmpty) {
        return const [];
      }
      final trackingById = await ref.watch(tvSearchTrackingProvider(username).future);
      final fromTracking = <NextToWatchShelfItem>[];
      final seen = <String>{};
      for (final item in trackingById.values) {
        if (item.media.mediaType != 'tv') {
          continue;
        }
        if (trackingIsDropped(item)) {
          continue;
        }
        if (!trackingIsPriority(item)) {
          continue;
        }
        if (seen.add(item.media.id)) {
          fromTracking.add(
            NextToWatchShelfItem(
              media: item.media,
              inPriority: true,
              inCinema: false,
            ),
          );
        }
      }

      final fromLists = await ref.watch(nextToWatchShelfProvider(username).future);
      final merged = <NextToWatchShelfItem>[...fromTracking];
      for (final shelf in fromLists) {
        if (shelf.media.mediaType != 'tv') {
          continue;
        }
        if (seen.add(shelf.media.id)) {
          merged.add(shelf);
        }
      }
      return merged.take(10).toList();
    });

/// Refreshes home shelves and tracking maps after a next-to-watch card action.
void invalidateNextToWatchCaches(
  WidgetRef ref, {
  required String username,
  required bool isTv,
}) {
  if (username.isEmpty) {
    return;
  }
  ref.invalidate(nextToWatchShelfProvider(username));
  ref.invalidate(tvNextToWatchShelfProvider(username));
  if (isTv) {
    ref.invalidate(tvSearchTrackingProvider(username));
    ref.invalidate(tvHomeShelvesProvider(username));
  } else {
    ref.invalidate(movieSearchTrackingProvider(username));
    ref.invalidate(customMovieListsProvider);
  }
}
