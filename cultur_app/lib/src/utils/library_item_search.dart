import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/books/book_publisher_link.dart';
import 'package:yamtrack/src/models/games/game_company_link.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/models/library/watched_tv_episode_library_row.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

String normalizeLibrarySearchQuery(String raw) => raw.trim().toLowerCase();

bool matchesLibrarySearchText(String haystack, String query) {
  final q = normalizeLibrarySearchQuery(query);
  if (q.isEmpty) {
    return true;
  }
  return haystack.trim().toLowerCase().contains(q);
}

bool catalogItemMatchesLibrarySearch(CatalogItem item, String query) =>
    matchesLibrarySearchText(item.title, query);

bool castPersonMatchesLibrarySearch(CatalogDetailPerson person, String query) {
  if (matchesLibrarySearchText(person.name, query)) {
    return true;
  }
  final role = person.role?.trim() ?? '';
  if (role.isNotEmpty && matchesLibrarySearchText(role, query)) {
    return true;
  }
  return false;
}

bool trackingItemMatchesLibrarySearch(TrackingItem item, String query) =>
    catalogItemMatchesLibrarySearch(item.media, query);

bool tvCustomListItemMatchesLibrarySearch(TvCustomListItem item, String query) {
  if (catalogItemMatchesLibrarySearch(item.show, query)) {
    return true;
  }
  final q = normalizeLibrarySearchQuery(query);
  if (q.isEmpty) {
    return true;
  }
  final compact = q.replaceAll(RegExp(r'[\s·]+'), '');
  if (item.seasonNumber != null && item.episodeNumber != null) {
    final code = 's${item.seasonNumber}e${item.episodeNumber}';
    if (code.contains(compact) || compact.contains(code)) {
      return true;
    }
    if (matchesLibrarySearchText(
      'Season ${item.seasonNumber} Episode ${item.episodeNumber}',
      query,
    )) {
      return true;
    }
  } else if (item.seasonNumber != null) {
    if (matchesLibrarySearchText('Season ${item.seasonNumber}', query)) {
      return true;
    }
  }
  return false;
}

bool tvWatchedEpisodeRowMatchesLibrarySearch(
  WatchedTvEpisodeLibraryRow row,
  String query,
) {
  if (catalogItemMatchesLibrarySearch(row.media, query)) {
    return true;
  }
  return matchesLibrarySearchText(row.seasonEpisodeLabel, query);
}

bool listNameMatchesLibrarySearch(String name, String query) =>
    matchesLibrarySearchText(name, query);

bool personNameMatchesLibrarySearch(String name, String query) =>
    matchesLibrarySearchText(name, query);

bool companyMatchesLibrarySearch(GameCompanyLink company, String query) {
  if (matchesLibrarySearchText(company.name, query)) {
    return true;
  }
  return matchesLibrarySearchText(company.role, query);
}

bool publisherMatchesLibrarySearch(BookPublisherLink publisher, String query) =>
    matchesLibrarySearchText(publisher.name, query);

String formatCompanyRoleLabel(String role) {
  final normalized = role.trim().toLowerCase();
  return switch (normalized) {
    'developer' => 'Developer',
    'publisher' => 'Publisher',
    'distributor' => 'Distributor',
    '' => 'Company',
    _ => '${role.trim()[0].toUpperCase()}${role.trim().substring(1)}',
  };
}
