import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/models/lists/custom_movie_lists_data.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/models/lists/tv_custom_lists_data.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

typedef CatalogListsSyncResult = ({CustomMovieListsData data, bool changed});

CatalogListsSyncResult syncBuiltinListFromTracking({
  required CustomMovieListsData data,
  required List<TrackingItem> tracking,
  required String mediaType,
  required String listId,
  required bool Function(TrackingItem item) include,
}) {
  final items = <CatalogItem>[];
  final seen = <String>{};
  for (final row in tracking) {
    if (row.media.mediaType.toLowerCase() != mediaType) {
      continue;
    }
    if (!include(row)) {
      continue;
    }
    if (!seen.add(row.media.id)) {
      continue;
    }
    items.add(row.media);
  }
  items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  var changed = false;
  final next = data.lists.map((list) {
    if (list.id != listId) {
      return list;
    }
    final sameLength = list.items.length == items.length;
    final sameIds =
        sameLength && list.items.every((item) => items.any((p) => p.id == item.id));
    if (sameIds) {
      return list;
    }
    changed = true;
    return list.copyWith(items: items);
  }).toList();
  return (data: CustomMovieListsData(lists: next), changed: changed);
}

CatalogListsSyncResult syncPendingImportsFromTracking({
  required CustomMovieListsData data,
  required List<TrackingItem> tracking,
  required String mediaType,
  required String pendingListId,
}) {
  return syncBuiltinListFromTracking(
    data: data,
    tracking: tracking,
    mediaType: mediaType,
    listId: pendingListId,
    include: (row) => row.media.isCatalogPending,
  );
}

CatalogListsSyncResult syncPriorityFromTracking({
  required CustomMovieListsData data,
  required List<TrackingItem> tracking,
  required String mediaType,
  required String priorityListId,
}) {
  return syncBuiltinListFromTracking(
    data: data,
    tracking: tracking,
    mediaType: mediaType,
    listId: priorityListId,
    include: trackingIsPriority,
  );
}

({TvCustomListsData data, bool changed}) syncTvPendingImportsFromTracking({
  required TvCustomListsData data,
  required List<TrackingItem> tvTracking,
  required String pendingListId,
}) {
  final pendingItems = <TvCustomListItem>[];
  final seen = <String>{};
  for (final tracking in tvTracking) {
    if (tracking.media.mediaType.toLowerCase() != 'tv') {
      continue;
    }
    if (!tracking.media.isCatalogPending) {
      continue;
    }
    if (!seen.add(tracking.media.id)) {
      continue;
    }
    pendingItems.add(TvCustomListItem(show: tracking.media));
  }
  pendingItems.sort(
    (a, b) => a.show.title.toLowerCase().compareTo(b.show.title.toLowerCase()),
  );

  var changed = false;
  final next = data.lists.map((list) {
    if (list.id != pendingListId) {
      return list;
    }
    final sameLength = list.items.length == pendingItems.length;
    final sameIds = sameLength &&
        list.items.every((item) => pendingItems.any((p) => p.show.id == item.show.id));
    if (sameIds) {
      return list;
    }
    changed = true;
    return list.copyWith(items: pendingItems);
  }).toList();
  return (data: TvCustomListsData(lists: next), changed: changed);
}
