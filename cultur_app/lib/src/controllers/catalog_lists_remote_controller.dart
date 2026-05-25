import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/models/lists/custom_movie_lists_data.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/services/collections_api.dart';
import 'package:yamtrack/src/utils/lists_tracking_sync.dart';

typedef CatalogListsTrackingSync = CatalogListsSyncResult Function(
  CustomMovieListsData data,
  List<TrackingItem> tracking,
);

/// Remote-backed custom lists for catalog-shaped items (movie, game, book, …).
class CatalogListsRemoteController {
  CatalogListsRemoteController({
    required ApiClient api,
    required SessionStorage storage,
    required CatalogListsRemoteConfig config,
  })  : _api = CollectionsApi(api),
        _storage = storage,
        _config = config;

  final CollectionsApi _api;
  final SessionStorage _storage;
  final CatalogListsRemoteConfig _config;

  Future<CustomMovieListsData> load(
    String username, {
    List<TrackingItem>? tracking,
  }) async {
    await _migrateLocalIfNeeded(username);

    var data = await _api.fetchCatalogLists(
      username: username,
      mediaType: _config.mediaType,
    );
    var changed = false;
    if (tracking != null) {
      for (final sync in _config.trackingSyncs) {
        final result = sync(data, tracking);
        data = result.data;
        changed = changed || result.changed;
      }
    }
    if (changed) {
      data = await _api.syncCatalogLists(
        username: username,
        mediaType: _config.mediaType,
        lists: _orderLists(data.lists),
      );
    }
    return CustomMovieListsData(lists: _orderLists(data.lists));
  }

  Future<CustomMovieList> createList(String username, String name) async {
    final created = await _api.createList(
      username: username,
      mediaType: _config.mediaType,
      name: name.trim(),
    );
    return created;
  }

  Future<void> deleteList(String username, String listId) async {
    if (_config.isBuiltIn(listId)) {
      return;
    }
    await _api.deleteList(username: username, collectionId: listId);
  }

  Future<void> renameList(String username, String listId, String newName) async {
    if (_config.isBuiltIn(listId)) {
      return;
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _api.renameList(
      username: username,
      collectionId: listId,
      name: trimmed,
    );
  }

  Future<void> toggleItem({
    required String username,
    required String listId,
    required CatalogItem item,
  }) async {
    await _api.toggleCatalogItem(
      username: username,
      collectionId: listId,
      item: item,
    );
  }

  Future<void> mergeImportedLists(String username, List<dynamic> imported) async {
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
      final items = itemsRaw.whereType<Map<String, dynamic>>().map(CatalogItem.fromJson).toList();
      if (items.isEmpty) {
        continue;
      }
      final lower = name.toLowerCase();
      final idx = lists.indexWhere(
        (list) => !_config.isBuiltIn(list.id) && list.name.toLowerCase() == lower,
      );
      if (idx >= 0) {
        final existing = lists[idx];
        final seen = {for (final item in existing.items) item.id};
        final merged = [...existing.items];
        for (final item in items) {
          if (seen.add(item.id)) {
            merged.add(item);
          }
        }
        lists[idx] = existing.copyWith(items: merged);
      } else {
        lists = [
          ...lists,
          CustomMovieList(
            id: 'imported-${DateTime.now().microsecondsSinceEpoch}-${lists.length}',
            name: name,
            items: items,
            createdAt: DateTime.now().toIso8601String(),
          ),
        ];
      }
    }
    await _api.syncCatalogLists(
      username: username,
      mediaType: _config.mediaType,
      lists: _orderLists(lists),
    );
  }

  Future<void> _migrateLocalIfNeeded(String username) async {
    final raw = await _storage.read(key: _config.storageKey(username));
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    final local = CustomMovieListsData.fromJsonString(raw);
    final hasContent = local.lists.any(
      (list) => !_config.isBuiltIn(list.id) || list.items.isNotEmpty,
    );
    if (!hasContent) {
      await _storage.delete(key: _config.storageKey(username));
      return;
    }
    await _api.syncCatalogLists(
      username: username,
      mediaType: _config.mediaType,
      lists: _orderLists(local.lists),
    );
    await _storage.delete(key: _config.storageKey(username));
  }

  List<CustomMovieList> _orderLists(List<CustomMovieList> lists) {
    final byId = {for (final list in lists) list.id: list};
    final ordered = <CustomMovieList>[];
    for (final id in _config.builtInOrderIds) {
      final list = byId[id];
      if (list != null) {
        ordered.add(list);
      }
    }
    final rest = lists
        .where((list) => !_config.builtInOrderIds.contains(list.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    ordered.addAll(rest);
    return ordered;
  }
}

class CatalogListsRemoteConfig {
  const CatalogListsRemoteConfig({
    required this.mediaType,
    required this.storageKey,
    required this.builtInOrderIds,
    required this.isBuiltIn,
    this.trackingSyncs = const [],
  });

  final String mediaType;
  final String Function(String username) storageKey;
  final List<String> builtInOrderIds;
  final bool Function(String listId) isBuiltIn;
  final List<CatalogListsTrackingSync> trackingSyncs;
}
