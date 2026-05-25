import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/models/lists/custom_movie_lists_data.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/models/lists/tv_custom_lists_data.dart';

/// HTTP client for `/backend/collections` and related endpoints.
class CollectionsApi {
  const CollectionsApi(this._client);

  final ApiClient _client;

  Future<CustomMovieListsData> fetchCatalogLists({
    required String username,
    required String mediaType,
  }) async {
    final payload = await _client.getJson(
      '/backend/collections',
      queryParameters: {
        'username': username,
        'mediaType': mediaType,
      },
    );
    final listsRaw = payload['lists'];
    if (listsRaw is! List) {
      return const CustomMovieListsData(lists: []);
    }
    final lists = <CustomMovieList>[];
    for (final row in listsRaw) {
      if (row is Map<String, dynamic>) {
        lists.add(_catalogListFromJson(row));
      } else if (row is Map) {
        lists.add(_catalogListFromJson(Map<String, dynamic>.from(row)));
      }
    }
    return CustomMovieListsData(lists: lists);
  }

  Future<TvCustomListsData> fetchTvLists({
    required String username,
  }) async {
    final payload = await _client.getJson(
      '/backend/collections',
      queryParameters: {
        'username': username,
        'mediaType': 'tv',
      },
    );
    final listsRaw = payload['lists'];
    if (listsRaw is! List) {
      return const TvCustomListsData(lists: []);
    }
    final lists = <TvCustomList>[];
    for (final row in listsRaw) {
      if (row is Map<String, dynamic>) {
        lists.add(_tvListFromJson(row));
      } else if (row is Map) {
        lists.add(_tvListFromJson(Map<String, dynamic>.from(row)));
      }
    }
    return TvCustomListsData(lists: lists);
  }

  Future<CustomMovieList> createList({
    required String username,
    required String mediaType,
    required String name,
  }) async {
    final payload = await _client.postJson(
      '/backend/collections',
      data: {
        'username': username,
        'mediaType': mediaType,
        'name': name,
      },
    );
    return _catalogListFromJson(payload);
  }

  Future<TvCustomList> createTvList({
    required String username,
    required String name,
  }) async {
    final payload = await _client.postJson(
      '/backend/collections',
      data: {
        'username': username,
        'mediaType': 'tv',
        'name': name,
      },
    );
    return _tvListFromJson(payload);
  }

  Future<CustomMovieList> renameList({
    required String username,
    required String collectionId,
    required String name,
  }) async {
    final payload = await _client.patchJson(
      '/backend/collections/$collectionId',
      data: {
        'username': username,
        'name': name,
      },
    );
    return _catalogListFromJson(payload);
  }

  Future<TvCustomList> renameTvList({
    required String username,
    required String collectionId,
    required String name,
  }) async {
    final payload = await _client.patchJson(
      '/backend/collections/$collectionId',
      data: {
        'username': username,
        'name': name,
      },
    );
    return _tvListFromJson(payload);
  }

  Future<void> deleteList({
    required String username,
    required String collectionId,
  }) async {
    await _client.delete(
      '/backend/collections/$collectionId',
      queryParameters: {'username': username},
    );
  }

  Future<CustomMovieList> toggleCatalogItem({
    required String username,
    required String collectionId,
    required CatalogItem item,
  }) async {
    final payload = await _client.postJson(
      '/backend/collections/$collectionId/items/toggle',
      data: {
        'username': username,
        'mediaId': item.id,
      },
    );
    return _catalogListFromJson(payload);
  }

  Future<TvCustomList> toggleTvItem({
    required String username,
    required String collectionId,
    required TvCustomListItem item,
  }) async {
    final data = <String, dynamic>{
      'username': username,
      'mediaId': item.show.id,
    };
    if (item.seasonNumber != null) {
      data['seasonNumber'] = item.seasonNumber;
    }
    if (item.episodeNumber != null) {
      data['episodeNumber'] = item.episodeNumber;
    }
    final payload = await _client.postJson(
      '/backend/collections/$collectionId/items/toggle',
      data: data,
    );
    return _tvListFromJson(payload);
  }

  Future<CustomMovieListsData> syncCatalogLists({
    required String username,
    required String mediaType,
    required List<CustomMovieList> lists,
  }) async {
    final payload = await _client.putJson(
      '/backend/collections/sync',
      data: {
        'username': username,
        'mediaType': mediaType,
        'lists': lists
            .map(
              (list) => {
                'id': list.id,
                'name': list.name,
                'createdAt': list.createdAt,
                'items': list.items.map((item) => item.toJson()).toList(),
              },
            )
            .toList(),
      },
    );
    final listsRaw = payload['lists'];
    if (listsRaw is! List) {
      return CustomMovieListsData(lists: lists);
    }
    final parsed = <CustomMovieList>[];
    for (final row in listsRaw) {
      if (row is Map<String, dynamic>) {
        parsed.add(_catalogListFromJson(row));
      } else if (row is Map) {
        parsed.add(_catalogListFromJson(Map<String, dynamic>.from(row)));
      }
    }
    return CustomMovieListsData(lists: parsed);
  }

  Future<TvCustomListsData> syncTvLists({
    required String username,
    required List<TvCustomList> lists,
  }) async {
    final payload = await _client.putJson(
      '/backend/collections/sync',
      data: {
        'username': username,
        'mediaType': 'tv',
        'lists': lists
            .map(
              (list) => {
                'id': list.id,
                'name': list.name,
                'createdAt': list.createdAt,
                'items': list.items.map((item) => item.toJson()).toList(),
              },
            )
            .toList(),
      },
    );
    final listsRaw = payload['lists'];
    if (listsRaw is! List) {
      return TvCustomListsData(lists: lists);
    }
    final parsed = <TvCustomList>[];
    for (final row in listsRaw) {
      if (row is Map<String, dynamic>) {
        parsed.add(_tvListFromJson(row));
      } else if (row is Map) {
        parsed.add(_tvListFromJson(Map<String, dynamic>.from(row)));
      }
    }
    return TvCustomListsData(lists: parsed);
  }

  static CustomMovieList _catalogListFromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final items = <CatalogItem>[];
    if (itemsRaw is List) {
      for (final row in itemsRaw) {
        if (row is Map<String, dynamic>) {
          items.add(CatalogItem.fromJson(row));
        } else if (row is Map) {
          items.add(CatalogItem.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    return CustomMovieList(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled list',
      items: items,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  static TvCustomList _tvListFromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final items = <TvCustomListItem>[];
    if (itemsRaw is List) {
      for (final row in itemsRaw) {
        if (row is Map<String, dynamic>) {
          items.add(TvCustomListItem.fromJson(row));
        } else if (row is Map) {
          items.add(TvCustomListItem.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    return TvCustomList(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled list',
      items: items,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}
