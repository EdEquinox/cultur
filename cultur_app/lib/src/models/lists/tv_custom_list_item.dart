import 'package:yamtrack/src/models/catalog/catalog_item.dart';

/// Shape of one saved row (whole show, one season, or one episode).
enum TvCustomListEntryKind {
  show,
  season,
  episode,
}


/// One row: always a [show]; [seasonNumber] / [episodeNumber] define the scope.
class TvCustomListItem {
  const TvCustomListItem({
    required this.show,
    this.seasonNumber,
    this.episodeNumber,
  });

  factory TvCustomListItem.fromJson(Map<String, dynamic> json) {
    final sn = json['seasonNumber'];
    final en = json['episodeNumber'];
    return TvCustomListItem(
      show: CatalogItem.fromJson(
        (json['show'] as Map<String, dynamic>?) ?? const {},
      ),
      seasonNumber: sn == null ? null : (sn is int ? sn : int.tryParse(sn.toString())),
      episodeNumber: en == null ? null : (en is int ? en : int.tryParse(en.toString())),
    );
  }

  final CatalogItem show;
  final int? seasonNumber;
  final int? episodeNumber;

  /// Whole series, a single season, or a single episode — rejects invalid pairs (e.g. episode without season).
  bool get isValidListEntry =>
      (seasonNumber == null && episodeNumber == null) ||
      (seasonNumber != null && episodeNumber == null) ||
      (seasonNumber != null && episodeNumber != null);

  TvCustomListEntryKind get entryKind {
    if (seasonNumber == null && episodeNumber == null) {
      return TvCustomListEntryKind.show;
    }
    if (episodeNumber == null) {
      return TvCustomListEntryKind.season;
    }
    return TvCustomListEntryKind.episode;
  }

  Map<String, dynamic> toJson() {
    return {
      'show': show.toJson(),
      if (seasonNumber != null) 'seasonNumber': seasonNumber,
      if (episodeNumber != null) 'episodeNumber': episodeNumber,
    };
  }

  bool matches(TvCustomListItem other) =>
      show.id == other.show.id &&
      seasonNumber == other.seasonNumber &&
      episodeNumber == other.episodeNumber;
}
