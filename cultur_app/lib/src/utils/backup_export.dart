import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/models/lists/custom_movie_lists_data.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/models/lists/tv_custom_lists_data.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/models/person/favorite_people.dart';
import 'package:yamtrack/src/utils/library_utils.dart';

/// Full Cultur backup document (JSON). Import accepts v3, v2, and legacy AVA roots.
const String culturBackupFormatV2 = 'cultur-backup-v2';
const String culturBackupFormatV3 = 'cultur-backup-v3';

/// Whether [root] is a Cultur full backup (v2 or v3), not a raw AVA/SeriesGuide file.
bool isCulturFullBackup(Map<String, dynamic> root) {
  final format = root['format']?.toString();
  return format == culturBackupFormatV2 || format == culturBackupFormatV3;
}

String defaultCulturBackupFileNameV3([DateTime? when]) {
  final now = when ?? DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return 'cultur-backup-v3-$y-$m-$d.json';
}

int? catalogTmdbId(CatalogItem item) {
  if (item.source.toLowerCase() != 'tmdb') {
    return null;
  }
  return int.tryParse(item.externalId.trim());
}

Map<String, dynamic> backupMovieStub(CatalogItem item) {
  final id = catalogTmdbId(item);
  if (id == null) {
    return {};
  }
  return {'tmdbId': id};
}

Map<String, dynamic> backupTvShowStub(CatalogItem show) {
  final id = catalogTmdbId(show);
  if (id == null) {
    return {};
  }
  return {'tmdbId': id};
}

Map<String, dynamic> backupTvEpisodeStub(TvCustomListItem item) {
  final id = catalogTmdbId(item.show);
  if (id == null) {
    return {};
  }
  return {
    'tmdbId': id,
    if (item.seasonNumber != null) 'seasonNumber': item.seasonNumber,
    if (item.episodeNumber != null) 'episodeNumber': item.episodeNumber,
  };
}

/// AVA `lists` entries for SeriesGuide-compatible import.
List<Map<String, dynamic>> buildAvaListsPayload({
  required List<CustomMovieList> movieLists,
  required List<TvCustomList> tvLists,
  bool includeBuiltInMovieLists = false,
}) {
  final out = <Map<String, dynamic>>[];

  for (final list in movieLists) {
    if (!includeBuiltInMovieLists && BuiltInMovieLists.isBuiltIn(list.id)) {
      continue;
    }
    if (list.items.isEmpty) {
      continue;
    }
    final movies = <Map<String, dynamic>>[];
    for (final item in list.items) {
      final stub = backupMovieStub(item);
      if (stub.isNotEmpty) {
        movies.add(stub);
      }
    }
    if (movies.isEmpty) {
      continue;
    }
    out.add({
      'name': list.name,
      'listMovieBackups': movies,
    });
  }

  for (final list in tvLists) {
    if (list.items.isEmpty) {
      continue;
    }
    final shows = <Map<String, dynamic>>[];
    final episodes = <Map<String, dynamic>>[];
    for (final item in list.items) {
      if (!item.isValidListEntry) {
        continue;
      }
      switch (item.entryKind) {
        case TvCustomListEntryKind.show:
          final stub = backupTvShowStub(item.show);
          if (stub.isNotEmpty) {
            shows.add(stub);
          }
        case TvCustomListEntryKind.season:
        case TvCustomListEntryKind.episode:
          final stub = backupTvEpisodeStub(item);
          if (stub.isNotEmpty) {
            episodes.add(stub);
          }
      }
    }
    if (shows.isEmpty && episodes.isEmpty) {
      continue;
    }
    final entry = <String, dynamic>{'name': list.name};
    if (shows.isNotEmpty) {
      entry['listTvShowBackups'] = shows;
    }
    if (episodes.isNotEmpty) {
      entry['listEpisodeBackups'] = episodes;
    }
    out.add(entry);
  }

  return out;
}

/// Builds the full JSON document written to `.json` on export.
Map<String, dynamic> buildCulturFullBackupV2({
  required String username,
  required String exportedAtIso,
  required Map<String, dynamic> serverAvaBackup,
  required Map<String, dynamic> trackingPayload,
  required Map<String, dynamic> tvWatchedEpisodesPayload,
  required CustomMovieListsData movieLists,
  required TvCustomListsData tvLists,
  required FavoritePeopleData favoritePeople,
}) {
  final ava = Map<String, dynamic>.from(serverAvaBackup);
  ava['lists'] = buildAvaListsPayload(
    movieLists: movieLists.lists,
    tvLists: tvLists.lists,
    includeBuiltInMovieLists: true,
  );

  return {
    'format': culturBackupFormatV2,
    'version': 2,
    'exportedAt': exportedAtIso,
    'username': username,
    'server': {
      'ava': ava,
      'tracking': trackingPayload,
      'tvWatchedEpisodes': tvWatchedEpisodesPayload,
    },
    'local': {
      'movieLists': {
        'lists': movieLists.lists.map((l) => l.toJson()).toList(),
      },
      'tvLists': {
        'lists': tvLists.lists.map((l) => l.toJson()).toList(),
      },
      'favoritePeople': {
        'people': favoritePeople.people.map((p) => p.toFavoriteJson()).toList(),
      },
    },
  };
}

/// Optional device-only section appended on export (lists/favorites not yet on server).
Map<String, dynamic> buildLocalBackupAppendix({
  required CustomMovieListsData movieLists,
  required TvCustomListsData tvLists,
  required FavoritePeopleData favoritePeople,
}) {
  return {
    'movieLists': {
      'lists': movieLists.lists.map((l) => l.toJson()).toList(),
    },
    'tvLists': {
      'lists': tvLists.lists.map((l) => l.toJson()).toList(),
    },
    'favoritePeople': {
      'people': favoritePeople.people.map((p) => p.toFavoriteJson()).toList(),
    },
  };
}

/// Resolves the object sent to `POST /backend/import/ava-backup-v1`.
Map<String, dynamic> extractAvaImportPayload(Map<String, dynamic> root) {
  final format = root['format']?.toString();
  if (format == culturBackupFormatV2 || format == culturBackupFormatV3) {
    final server = root['server'];
    if (server is Map<String, dynamic>) {
      final ava = server['ava'];
      if (ava is Map<String, dynamic>) {
        return Map<String, dynamic>.from(ava);
      }
    }
    throw const FormatException('Cultur backup is missing server.ava.');
  }
  if (format == culturBackupFormatV3) {
    final legacy = root['legacy'];
    if (legacy is Map<String, dynamic>) {
      final ava = legacy['ava'];
      if (ava is Map<String, dynamic>) {
        return Map<String, dynamic>.from(ava);
      }
    }
    throw const FormatException('Cultur backup v3 has no legacy.ava for AVA-only import.');
  }
  return Map<String, dynamic>.from(root);
}

/// Local device section from a v2 backup, if present.
Map<String, dynamic>? extractLocalBackupSection(Map<String, dynamic> root) {
  final format = root['format']?.toString();
  if (format != culturBackupFormatV2 && format != culturBackupFormatV3) {
    return null;
  }
  final local = root['local'];
  if (local is Map<String, dynamic>) {
    return local;
  }
  return null;
}

CustomMovieListsData? parseLocalMovieLists(Map<String, dynamic> local) {
  final raw = local['movieLists'];
  if (raw is! Map<String, dynamic>) {
    return null;
  }
  final listsRaw = raw['lists'];
  if (listsRaw is! List) {
    return null;
  }
  final lists = listsRaw
      .whereType<Map<String, dynamic>>()
      .map(CustomMovieList.fromJson)
      .toList();
  return CustomMovieListsData(lists: lists);
}

TvCustomListsData? parseLocalTvLists(Map<String, dynamic> local) {
  final raw = local['tvLists'];
  if (raw is! Map<String, dynamic>) {
    return null;
  }
  final listsRaw = raw['lists'];
  if (listsRaw is! List) {
    return null;
  }
  final lists = listsRaw
      .whereType<Map<String, dynamic>>()
      .map(TvCustomList.fromJson)
      .where((l) => l.name.isNotEmpty)
      .toList();
  return TvCustomListsData(lists: lists);
}

FavoritePeopleData? parseLocalFavoritePeople(Map<String, dynamic> local) {
  final raw = local['favoritePeople'];
  if (raw is! Map<String, dynamic>) {
    return null;
  }
  final peopleRaw = raw['people'];
  if (peopleRaw is! List) {
    return null;
  }
  final people = peopleRaw
      .whereType<Map<String, dynamic>>()
      .map(MovieDetailPerson.fromJson)
      .where((p) => (p.personId ?? '').isNotEmpty)
      .toList();
  return FavoritePeopleData(people: people);
}

String defaultCulturBackupFileName([DateTime? when]) {
  final now = when ?? DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return 'cultur-backup-$y-$m-$d.json';
}

typedef BackupGetJson = Future<Map<String, dynamic>> Function(
  String path, {
  Map<String, String>? queryParameters,
});

Future<Map<String, dynamic>> fetchAllTrackingPayload(
  BackupGetJson getJson,
  String username,
) async {
  return getJson(
    '/backend/tracking',
    queryParameters: {
      'username': username,
      'limit': '2000',
    },
  );
}

Future<Map<String, dynamic>> fetchAllTvWatchedEpisodesPayload(
  BackupGetJson getJson,
  String username,
) async {
  final all = <Map<String, dynamic>>[];
  var offset = 0;
  const pageSize = 500;
  while (true) {
    final payload = await getJson(
      '/backend/tracking/tv/watched-episodes',
      queryParameters: {
        'username': username,
        'limit': '$pageSize',
        'offset': '$offset',
      },
    );
    final items = (payload['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    all.addAll(items);
    if (items.length < pageSize) {
      break;
    }
    offset += pageSize;
  }
  return {'items': all};
}
