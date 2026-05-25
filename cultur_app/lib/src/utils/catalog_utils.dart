import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/models/games/stash_game_event.dart';
import 'package:yamtrack/src/utils/book_progress_utils.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

/// Parse `S01E02` from shelf subtitle (e.g. `S5E14 · Ozymandias`).
({int season, int episode})? parseTvShelfEpisodeSubtitle(String? subtitle) {
  if (subtitle == null || subtitle.trim().isEmpty) {
    return null;
  }
  final m = RegExp(r'S(\d+)E(\d+)', caseSensitive: false).firstMatch(subtitle);
  if (m == null) {
    return null;
  }
  final s = int.tryParse(m.group(1)!);
  final e = int.tryParse(m.group(2)!);
  if (s == null || e == null) {
    return null;
  }
  return (season: s, episode: e);
}

String releaseFriendlyLabel(CatalogItem item) {
  final date = catalogItemReleaseDate(item);
  if (date == null) {
    return '';
  }
  final today = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final t = DateTime(today.year, today.month, today.day);
  final long = releaseLongLabel(item);
  if (long.isEmpty) {
    return '';
  }
  if (d == t) {
    return 'Today, $long';
  }
  if (d == t.subtract(const Duration(days: 1))) {
    return 'Yesterday, $long';
  }
  return long;
}

bool catalogItemIsUpcomingRelease(CatalogItem item) {
  final date = catalogItemReleaseDate(item);
  if (date == null) {
    return false;
  }
  final today = DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  return date.isAfter(startOfToday);
}

/// TMDB `upcoming` browse pages: keep undated rows; drop only past release dates.
bool catalogItemIsUpcomingCatalogSlice(CatalogItem item) {
  final date = catalogItemReleaseDate(item);
  if (date == null) {
    return true;
  }
  return catalogItemIsUpcomingRelease(item);
}

DateTime? catalogItemReleaseDate(CatalogItem item) {
  final value = item.metadata['releaseDate']?.toString().trim();
  if (value != null && value.isNotEmpty) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  final year = item.metadata['firstReleaseDate']?.toString().trim();
  if (year != null && RegExp(r'^\d{4}$').hasMatch(year)) {
    return DateTime(int.parse(year));
  }
  return null;
}

bool catalogItemIsContinueWatchingShelf(CatalogItem item) {
  return (item.metadata['shelfEpisodeKind']?.toString() ?? '') ==
      'continueWatching';
}

/// TV home shelves (next up / upcoming) attach episode context in [CatalogItem.subtitle].
bool catalogItemIsTvShelfEpisodeKind(CatalogItem item) {
  final kind = item.metadata['shelfEpisodeKind']?.toString() ?? '';
  return kind == 'nextAiring' ||
      kind == 'continueWatching' ||
      kind == 'lastAired';
}

/// Media ids still active on TV home (continue / new drop / upcoming) — not fully caught up.
Set<String> tvActiveWatchingMediaIdsFromShelves({
  required CatalogListData nextUp,
  required CatalogListData upcomingEpisodes,
}) {
  final ids = <String>{};
  for (final item in nextUp.items) {
    if (catalogItemIsTvShelfEpisodeKind(item)) {
      ids.add(item.id);
    }
  }
  for (final item in upcomingEpisodes.items) {
    if (catalogItemIsTvShelfEpisodeKind(item)) {
      ids.add(item.id);
    }
  }
  return ids;
}

/// Subtitle for cards: episode line on TV shelves; director/year elsewhere.
String catalogItemCardSubtitle(CatalogItem item) {
  if (catalogItemIsTvShelfEpisodeKind(item)) {
    final episodeLine = item.subtitle?.trim();
    if (episodeLine != null && episodeLine.isNotEmpty) {
      return episodeLine;
    }
    final release = releaseFriendlyLabel(item);
    if (release.isNotEmpty) {
      return release;
    }
    return '';
  }
  return catalogItemDirectorOrSubtitle(item);
}

List<CatalogItem> catalogContinueWatchingSortedNewestFirst(CatalogListData data) {
  final list = data.items.where(catalogItemIsContinueWatchingShelf).toList();
  int ts(CatalogItem i) =>
      catalogItemReleaseDate(i)?.millisecondsSinceEpoch ?? 0;
  list.sort((a, b) => ts(b).compareTo(ts(a)));
  return list;
}

String releaseLongLabel(CatalogItem item) {
  final date = catalogItemReleaseDate(item);
  if (date == null) {
    return '';
  }
  return releaseDayLabel(date);
}

String releaseDayLabel(DateTime date) {
  return '${monthLongLabel(date.month)} ${date.day}, ${date.year}';
}

/// Groups catalog items by calendar release day, sorted soonest first.
/// Groups Stash industry events by calendar day, newest days first.
List<({DateTime day, List<StashGameEvent> items})> groupStashEventsByDay(
  Iterable<StashGameEvent> events,
) {
  final byDay = <DateTime, List<StashGameEvent>>{};
  for (final event in events) {
    final local = event.startsAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    byDay.putIfAbsent(day, () => []).add(event);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days) (day: day, items: byDay[day]!),
  ];
}

List<({DateTime day, List<CatalogItem> items})> groupCatalogItemsByReleaseDay(
  Iterable<CatalogItem> items,
) {
  final byDay = <DateTime, List<CatalogItem>>{};
  for (final item in items) {
    final date = catalogItemReleaseDate(item);
    if (date == null) {
      continue;
    }
    final day = DateTime(date.year, date.month, date.day);
    byDay.putIfAbsent(day, () => []).add(item);
  }
  final days = byDay.keys.toList()..sort();
  return [
    for (final day in days) (day: day, items: byDay[day]!),
  ];
}

String monthLongLabel(int month) {
  switch (month) {
    case 1:
      return 'January';
    case 2:
      return 'February';
    case 3:
      return 'March';
    case 4:
      return 'April';
    case 5:
      return 'May';
    case 6:
      return 'June';
    case 7:
      return 'July';
    case 8:
      return 'August';
    case 9:
      return 'September';
    case 10:
      return 'October';
    case 11:
      return 'November';
    default:
      return 'December';
  }
}

String monthShortLabel(int month) {
  switch (month) {
    case 1:
      return 'JAN';
    case 2:
      return 'FEB';
    case 3:
      return 'MAR';
    case 4:
      return 'APR';
    case 5:
      return 'MAY';
    case 6:
      return 'JUN';
    case 7:
      return 'JUL';
    case 8:
      return 'AUG';
    case 9:
      return 'SEP';
    case 10:
      return 'OCT';
    case 11:
      return 'NOV';
    default:
      return 'DEC';
  }
}

String daySuffix(int day) {
  if (day >= 11 && day <= 13) {
    return 'th';
  }
  switch (day % 10) {
    case 1:
      return 'st';
    case 2:
      return 'nd';
    case 3:
      return 'rd';
    default:
      return 'th';
  }
}

String gamesByCompanyBrowsePath({
  required String companyId,
  required String role,
  required String name,
}) {
  final params = <String, String>{
    'companyId': companyId,
    'companyRole': role,
    if (name.trim().isNotEmpty) 'companyName': name.trim(),
  };
  return Uri(path: '/category/games', queryParameters: params).toString();
}

String gameCompanyDetailPath({
  required String companyId,
  required String role,
  String? name,
}) {
  final params = <String, String>{
    'role': role,
    if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
  };
  return Uri(
    path: '/games/companies/$companyId',
    queryParameters: params,
  ).toString();
}

String bookSeriesDetailPath({
  required String seriesId,
  String? name,
}) {
  final params = <String, String>{
    if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
  };
  return Uri(
    path: '/books/series/${Uri.encodeComponent(seriesId)}',
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

String bookPublisherDetailPath({
  required String publisherId,
  String? name,
}) {
  final params = <String, String>{
    if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
  };
  return Uri(
    path: '/books/publishers/${Uri.encodeComponent(publisherId)}',
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

String gamesByFranchiseBrowsePath({
  required String franchiseId,
  required String name,
}) {
  final params = <String, String>{
    'franchiseId': franchiseId,
    if (name.trim().isNotEmpty) 'browseName': name.trim(),
  };
  return Uri(path: '/category/games', queryParameters: params).toString();
}

String gamesByCollectionBrowsePath({
  required String collectionId,
  required String name,
}) {
  final params = <String, String>{
    'collectionId': collectionId,
    if (name.trim().isNotEmpty) 'browseName': name.trim(),
  };
  return Uri(path: '/category/games', queryParameters: params).toString();
}

bool catalogItemIsMusicReleaseGroup(CatalogItem item) {
  final mbKind = item.metadata['musicbrainzKind']?.toString().trim().toLowerCase();
  if (mbKind == 'release-group') {
    return true;
  }
  if (item.externalId.startsWith('mb-rg:')) {
    return true;
  }
  final legacyKind = item.metadata['discogsKind']?.toString().trim().toLowerCase();
  if (legacyKind == 'master') {
    return true;
  }
  return item.externalId.startsWith('master-');
}

@Deprecated('Use catalogItemIsMusicReleaseGroup')
bool catalogItemIsDiscogsMaster(CatalogItem item) => catalogItemIsMusicReleaseGroup(item);

String catalogItemDetailPath(CatalogItem item) {
  return switch (item.mediaType) {
    'tv' => '/tv/${item.id}',
    'game' => '/games/${item.id}',
    'boardgame' => '/boardgames/${item.id}',
    'book' => '/books/${item.id}',
    'music' => '/albums/${item.id}',
    _ => '/movies/${item.id}',
  };
}

/// TMDB `metadata.director` when present; otherwise [CatalogItem.subtitle].
String catalogItemDirectorOrSubtitle(CatalogItem media) {
  for (final key in ['director', 'Director']) {
    final v = media.metadata[key]?.toString().trim();
    if (v != null && v.isNotEmpty) {
      return v;
    }
  }
  return (media.subtitle ?? '').trim();
}

/// Truncated synopsis for book browse grid cards (description / first sentence).
String? catalogItemGridSynopsisLine(CatalogItem item) {
  if (item.mediaType.trim().toLowerCase() != 'book') {
    return null;
  }
  final raw = item.description?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  const maxLen = 120;
  if (raw.length <= maxLen) {
    return raw;
  }
  return '${raw.substring(0, maxLen).trimRight()}…';
}

/// Second line under the title on poster grid cards (Collected / Owned, browse grids).
String catalogItemGridSecondaryLine(CatalogItem item) {
  final type = item.mediaType.trim().toLowerCase();
  if (type == 'book') {
    final parts = <String>[];
    final authors = bookAuthorsLabel(item);
    if (authors != null && authors.isNotEmpty) {
      parts.add(authors);
    }
    final year = catalogReleaseYear(item);
    if (year != null && year.isNotEmpty) {
      parts.add(year);
    }
    if (parts.isNotEmpty) {
      return parts.join(' · ');
    }
  }
  if (type == 'game') {
    return catalogItemDirectorOrSubtitle(item);
  }
  if (type == 'music') {
    final parts = <String>[];
    final sub = item.subtitle?.trim();
    if (sub != null && sub.isNotEmpty) {
      parts.add(sub);
    }
    if (item.source == 'lastfm') {
      parts.add('Last.fm');
    }
    if (parts.isNotEmpty) {
      return parts.join(' · ');
    }
  }
  final sub = item.subtitle?.trim();
  if (sub != null && sub.isNotEmpty) {
    return sub;
  }
  return catalogItemDirectorOrSubtitle(item);
}



