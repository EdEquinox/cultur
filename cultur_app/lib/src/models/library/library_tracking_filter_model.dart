import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/models/library/watched_tv_episode_library_row.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/library/library_enums.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';


/// Mutable filter state for library tracking and personal list pages.
class LibraryTrackingFilterModel {
  LibraryTrackingFilterModel({
    this.watchedDatePreset = WatchedDatePreset.none,
    this.tvRatingFilterEnabled = false,
    this.tvRatingMin = 7,
    this.tvRatingMax = 10,
    this.tvTmdbRatingFilterEnabled = false,
    this.tvTmdbRatingMin = 7,
    this.tvTmdbRatingMax = 10,
    this.tvShowStatusFilterActive = false,
    Set<String>? tvShowStatusKeys,
    this.tvShowTypeFilterActive = false,
    Set<String>? tvShowTypeKeys,
    this.metadataFilterActive = false,
    Set<String>? metadataMediumKeys,
    Set<String>? genreSlugs,
  })  : tvShowStatusKeys = tvShowStatusKeys ?? {},
        tvShowTypeKeys = tvShowTypeKeys ?? {},
        metadataMediumKeys = metadataMediumKeys ?? {},
        genreSlugs = genreSlugs ?? {};

  WatchedDatePreset watchedDatePreset;
  bool tvRatingFilterEnabled;
  int tvRatingMin;
  int tvRatingMax;
  bool tvTmdbRatingFilterEnabled;
  int tvTmdbRatingMin;
  int tvTmdbRatingMax;
  bool tvShowStatusFilterActive;
  Set<String> tvShowStatusKeys;
  bool tvShowTypeFilterActive;
  Set<String> tvShowTypeKeys;
  bool metadataFilterActive;
  Set<String> metadataMediumKeys;
  Set<String> genreSlugs;

  void clearAll() {
    watchedDatePreset = WatchedDatePreset.none;
    tvRatingFilterEnabled = false;
    tvRatingMin = 7;
    tvRatingMax = 10;
    tvTmdbRatingFilterEnabled = false;
    tvTmdbRatingMin = 7;
    tvTmdbRatingMax = 10;
    tvShowStatusFilterActive = false;
    tvShowStatusKeys.clear();
    tvShowTypeFilterActive = false;
    tvShowTypeKeys.clear();
    metadataFilterActive = false;
    metadataMediumKeys.clear();
    genreSlugs.clear();
  }

  /// Filters that apply on custom list pages (no tracking-only rules).
  bool passesCatalogForUniversalFilters(CatalogItem media) {
    return catalogMatchesGenreSlugs(media, genreSlugs);
  }

  bool passesTvCustomListRow(TvCustomListItem row) {
    return catalogMatchesGenreSlugs(row.show, genreSlugs);
  }

  bool passesTrackingItem(
    TrackingItem item, {
    required LibraryCollectionKind collectionKind,
    required LibraryMediaScope mediaScope,
  }) {
    if (collectionKind == LibraryCollectionKind.finished &&
        watchedDatePreset != WatchedDatePreset.none) {
      if (!completedAtMatchesWatchedPreset(item.completedAt, watchedDatePreset)) {
        return false;
      }
    }
    if (mediaScope == LibraryMediaScope.tv) {
      if (!tvMyRatingMatches(item, tvRatingFilterEnabled, tvRatingMin, tvRatingMax)) {
        return false;
      }
      if (!tvTmdbRatingMatchesCatalog(item.media, tvTmdbRatingFilterEnabled, tvTmdbRatingMin, tvTmdbRatingMax)) {
        return false;
      }
      if (!tvShowStatusMatches(item.media, tvShowStatusFilterActive, tvShowStatusKeys)) {
        return false;
      }
      if (!tvShowTypeMatches(item.media, tvShowTypeFilterActive, tvShowTypeKeys)) {
        return false;
      }
    }
    if (collectionKind == LibraryCollectionKind.owned && metadataFilterActive) {
      if (!collectedMetadataMatches(item.media, metadataFilterActive, metadataMediumKeys)) {
        return false;
      }
    }
    if (!catalogMatchesGenreSlugs(item.media, genreSlugs)) {
      return false;
    }
    return true;
  }

  bool passesTvEpisodeRow(
    WatchedTvEpisodeLibraryRow row, {
    required LibraryCollectionKind collectionKind,
    required LibraryMediaScope mediaScope,
    required Map<String, double> scoresByMediaId,
  }) {
    if (collectionKind == LibraryCollectionKind.finished &&
        watchedDatePreset != WatchedDatePreset.none) {
      if (!watchedEpisodeRowMatchesPreset(row, watchedDatePreset)) {
        return false;
      }
    }
    if (mediaScope == LibraryMediaScope.tv) {
      if (!tvEpisodeMyRatingMatches(row, scoresByMediaId, tvRatingFilterEnabled, tvRatingMin, tvRatingMax)) {
        return false;
      }
      if (!tvTmdbRatingMatchesCatalog(row.media, tvTmdbRatingFilterEnabled, tvTmdbRatingMin, tvTmdbRatingMax)) {
        return false;
      }
      if (!tvShowStatusMatches(row.media, tvShowStatusFilterActive, tvShowStatusKeys)) {
        return false;
      }
      if (!tvShowTypeMatches(row.media, tvShowTypeFilterActive, tvShowTypeKeys)) {
        return false;
      }
    }
    if (!catalogMatchesGenreSlugs(row.media, genreSlugs)) {
      return false;
    }
    return true;
  }
}
