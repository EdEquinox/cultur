import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/models/lists/tv_custom_lists_data.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

import 'tv_lists_remote_controller.dart';

/// Custom TV lists backed by `/backend/collections`.
class TvCustomListsController {
  TvCustomListsController(ApiClient api, SessionStorage storage)
      : _remote = TvListsRemoteController(api: api, storage: storage);

  final TvListsRemoteController _remote;

  Future<TvCustomListsData> load(
    String username, {
    List<TrackingItem>? tvTracking,
  }) =>
      _remote.load(username, tvTracking: tvTracking);

  Future<TvCustomList> createList(String username, String name) =>
      _remote.createList(username, name);

  Future<void> deleteList(String username, String listId) =>
      _remote.deleteList(username, listId);

  Future<void> renameList(String username, String listId, String newName) =>
      _remote.renameList(username, listId, newName);

  Future<void> toggleItem({
    required String username,
    required String listId,
    required TvCustomListItem item,
  }) =>
      _remote.toggleItem(username: username, listId: listId, item: item);

  Future<void> mergeImportedTvLists(String username, List<dynamic> imported) =>
      _remote.mergeImportedTvLists(username, imported);
}
