import 'package:yamtrack/src/models/catalog/catalog_item.dart';

/// One row from `GET /backend/tracking/tv/watched-episodes` (library TV Watched tab).
class WatchedTvEpisodeLibraryRow {
  const WatchedTvEpisodeLibraryRow({
    required this.media,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.watchedAt,
  });

  factory WatchedTvEpisodeLibraryRow.fromJson(Map<String, dynamic> json) {
    final sn = json['seasonNumber'];
    final en = json['episodeNumber'];
    return WatchedTvEpisodeLibraryRow(
      media: CatalogItem.fromJson(
        (json['media'] as Map<String, dynamic>?) ?? const {},
      ),
      seasonNumber: sn is int ? sn : int.tryParse(sn?.toString() ?? '') ?? 0,
      episodeNumber: en is int ? en : int.tryParse(en?.toString() ?? '') ?? 0,
      watchedAt: json['watchedAt']?.toString() ?? '',
    );
  }

  final CatalogItem media;
  final int seasonNumber;
  final int episodeNumber;
  final String watchedAt;

  String get seasonEpisodeLabel {
    final s = seasonNumber.toString().padLeft(2, '0');
    final e = episodeNumber.toString().padLeft(2, '0');
    return 'S$s · E$e';
  }
}

class TvWatchedEpisodesLibraryData {
  const TvWatchedEpisodesLibraryData({required this.items});

  factory TvWatchedEpisodesLibraryData.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? [];
    return TvWatchedEpisodesLibraryData(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(WatchedTvEpisodeLibraryRow.fromJson)
          .toList(),
    );
  }

  final List<WatchedTvEpisodeLibraryRow> items;
}

