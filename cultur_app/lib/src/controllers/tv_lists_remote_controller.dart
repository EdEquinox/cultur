import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/models/lists/tv_custom_lists_data.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/services/collections_api.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/utils/lists_tracking_sync.dart';

/// Remote-backed custom TV lists.
class TvListsRemoteController {
  TvListsRemoteController({
    required ApiClient api,
    required SessionStorage storage,
  })  : _api = CollectionsApi(api),
        _storage = storage;

  final CollectionsApi _api;
  final SessionStorage _storage;

  Future<TvCustomListsData> load(
    String username, {
    List<TrackingItem>? tvTracking,
  }) async {
    await _migrateLocalIfNeeded(username);

    var data = await _api.fetchTvLists(username: username);
    var changed = false;
    if (tvTracking != null) {
      final synced = syncTvPendingImportsFromTracking(
        data: data,
        tvTracking: tvTracking,
        pendingListId: BuiltInTvLists.pendingImportsListId,
      );
      data = synced.data;
      changed = synced.changed;
    }
    if (changed) {
      data = await _api.syncTvLists(
        username: username,
        lists: _orderLists(data.lists),
      );
    }
    return TvCustomListsData(lists: _orderLists(data.lists));
  }

  Future<TvCustomList> createList(String username, String name) async {
    return _api.createTvList(username: username, name: name.trim());
  }

  Future<void> deleteList(String username, String listId) async {
    if (BuiltInTvLists.isBuiltIn(listId)) {
      return;
    }
    await _api.deleteList(username: username, collectionId: listId);
  }

  Future<void> renameList(String username, String listId, String newName) async {
    if (BuiltInTvLists.isBuiltIn(listId)) {
      return;
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _api.renameTvList(
      username: username,
      collectionId: listId,
      name: trimmed,
    );
  }

  Future<void> toggleItem({
    required String username,
    required String listId,
    required TvCustomListItem item,
  }) async {
    if (!item.isValidListEntry) {
      return;
    }
    await _api.toggleTvItem(
      username: username,
      collectionId: listId,
      item: item,
    );
  }

  Future<void> mergeImportedTvLists(String username, List<dynamic> imported) async {
    if (imported.isEmpty) {
      return;
    }
    var data = await load(username);
    var lists = [...data.lists];
    for (final raw in imported) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final name = (raw['name']?.toString() ?? 'Imported list').trim();
      if (name.isEmpty) {
        continue;
      }
      final itemsRaw = raw['items'] as List<dynamic>? ?? [];
      final entries = <TvCustomListItem>[];
      for (final itemMap in itemsRaw.whereType<Map<String, dynamic>>()) {
        final show = CatalogItem.fromJson(itemMap);
        if (show.mediaType.toLowerCase() != 'tv') {
          continue;
        }
        entries.add(TvCustomListItem(show: show));
      }
      if (entries.isEmpty) {
        continue;
      }
      final lower = name.toLowerCase();
      final idx = lists.indexWhere((list) => list.name.toLowerCase() == lower);
      if (idx >= 0) {
        final existing = lists[idx];
        final seen = {for (final entry in existing.items) entry.show.id};
        final merged = [...existing.items];
        for (final entry in entries) {
          if (seen.add(entry.show.id)) {
            merged.add(entry);
          }
        }
        lists[idx] = existing.copyWith(items: merged);
      } else {
        lists = [
          ...lists,
          TvCustomList(
            id: 'imported-tv-${DateTime.now().microsecondsSinceEpoch}-${lists.length}',
            name: name,
            items: entries,
            createdAt: DateTime.now().toIso8601String(),
          ),
        ];
      }
    }
    await _api.syncTvLists(username: username, lists: _orderLists(lists));
  }

  Future<void> _migrateLocalIfNeeded(String username) async {
    final raw = await _storage.read(key: StorageKeys.customTvLists(username));
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    final local = TvCustomListsData.fromJsonString(raw);
    final hasContent = local.lists.any(
      (list) => !BuiltInTvLists.isBuiltIn(list.id) || list.items.isNotEmpty,
    );
    if (!hasContent) {
      await _storage.delete(key: StorageKeys.customTvLists(username));
      return;
    }
    await _api.syncTvLists(username: username, lists: _orderLists(local.lists));
    await _storage.delete(key: StorageKeys.customTvLists(username));
  }

  List<TvCustomList> _orderLists(List<TvCustomList> lists) {
    final byId = {for (final list in lists) list.id: list};
    final ordered = <TvCustomList>[];
    final pending = byId[BuiltInTvLists.pendingImportsListId];
    if (pending != null) {
      ordered.add(pending);
    }
    final rest = lists
        .where((list) => list.id != BuiltInTvLists.pendingImportsListId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    ordered.addAll(rest);
    return ordered;
  }
}
