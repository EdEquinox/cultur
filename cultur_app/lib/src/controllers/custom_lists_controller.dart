import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/models/lists/custom_movie_lists_data.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/utils/lists_tracking_sync.dart';

import 'catalog_lists_remote_controller.dart';

/// Custom movie lists backed by `/backend/collections`.
class CustomListsController {
  CustomListsController(ApiClient api, SessionStorage storage)
      : _remote = CatalogListsRemoteController(
          api: api,
          storage: storage,
          config: CatalogListsRemoteConfig(
            mediaType: 'movie',
            storageKey: StorageKeys.customMovieLists,
            builtInOrderIds: const [
              BuiltInMovieLists.priorityListId,
              BuiltInMovieLists.cinemaListId,
              BuiltInMovieLists.pendingImportsListId,
            ],
            isBuiltIn: BuiltInMovieLists.isBuiltIn,
            trackingSyncs: [
              (data, tracking) => syncPendingImportsFromTracking(
                    data: data,
                    tracking: tracking,
                    mediaType: 'movie',
                    pendingListId: BuiltInMovieLists.pendingImportsListId,
                  ),
            ],
          ),
        );

  final CatalogListsRemoteController _remote;

  Future<CustomMovieListsData> load(
    String username, {
    List<TrackingItem>? movieTracking,
  }) =>
      _remote.load(username, tracking: movieTracking);

  Future<CustomMovieList> createList(String username, String name) =>
      _remote.createList(username, name);

  Future<void> deleteList(String username, String listId) =>
      _remote.deleteList(username, listId);

  Future<void> renameList(String username, String listId, String newName) =>
      _remote.renameList(username, listId, newName);

  Future<void> toggleItem({
    required String username,
    required String listId,
    required CatalogItem item,
  }) =>
      _remote.toggleItem(username: username, listId: listId, item: item);

  Future<void> mergeImportedLists(String username, List<dynamic> imported) =>
      _remote.mergeImportedLists(username, imported);
}
