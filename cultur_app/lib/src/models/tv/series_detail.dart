import 'package:yamtrack/src/models/movie/movie_detail_metric.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/models/tv/episode_availability.dart';
import 'package:yamtrack/src/models/tv/user_episode_engagement.dart';

export 'package:yamtrack/src/models/tv/episode_availability.dart'
    show tvEpisodeAiredForWatch;

// Models for TV series detail (watch progress, seasons/episodes, etc.).

class WatchedEpisode {
  const WatchedEpisode({
    required this.seasonNumber,
    required this.episodeNumber,
    this.watchedAt,
    this.userRating,
    this.userRatingRatedAt,
    this.userWatchlist,
    this.userWatchlistedAt,
  });

  factory WatchedEpisode.fromJson(Map<String, dynamic> json) {
    final seasonRaw = json['seasonNumber'];
    final episodeRaw = json['episodeNumber'];
    final engagement = UserEpisodeEngagement.fromJson(json);
    return WatchedEpisode(
      seasonNumber: seasonRaw is int
          ? seasonRaw
          : int.tryParse(seasonRaw?.toString() ?? '') ?? 0,
      episodeNumber: episodeRaw is int
          ? episodeRaw
          : int.tryParse(episodeRaw?.toString() ?? '') ?? 0,
      watchedAt: json['watchedAt']?.toString(),
      userRating: engagement.userRating,
      userRatingRatedAt: engagement.userRatingRatedAt,
      userWatchlist: engagement.userWatchlist,
      userWatchlistedAt: engagement.userWatchlistedAt,
    );
  }

  final int seasonNumber;
  final int episodeNumber;
  final String? watchedAt;
  final double? userRating;
  final String? userRatingRatedAt;
  final bool? userWatchlist;
  final String? userWatchlistedAt;
}

extension WatchedEpisodeListX on List<WatchedEpisode> {
  bool episodeIsWatched(int seasonNumber, int episodeNumber) {
    for (final w in this) {
      if (w.seasonNumber == seasonNumber && w.episodeNumber == episodeNumber) {
        final at = w.watchedAt?.trim();
        return at != null && at.isNotEmpty;
      }
    }
    return false;
  }

  /// Episodes marked watched in [seasonNumber] (same rules as [episodeIsWatched]).
  int watchedCountInSeason(int seasonNumber) {
    var count = 0;
    for (final w in this) {
      if (w.seasonNumber != seasonNumber) {
        continue;
      }
      final at = w.watchedAt?.trim();
      if (at != null && at.isNotEmpty) {
        count++;
      }
    }
    return count;
  }
}

/// `x / y` watch progress for a season row when only summary [episodeCount] is known.
String? tvSeasonListWatchProgressLabel({
  required List<WatchedEpisode> watchedEpisodes,
  required int seasonNumber,
  required int episodeCount,
}) {
  if (episodeCount <= 0) {
    return null;
  }
  final watched = watchedEpisodes.watchedCountInSeason(seasonNumber);
  return '$watched / $episodeCount';
}

class TvSeasonSummary {
  const TvSeasonSummary({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.airDate,
    this.overview,
    this.posterUrl,
  });

  factory TvSeasonSummary.fromJson(Map<String, dynamic> json) {
    final sn = json['seasonNumber'];
    final ec = json['episodeCount'];
    return TvSeasonSummary(
      seasonNumber: sn is int ? sn : int.tryParse(sn?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      episodeCount: ec is int ? ec : int.tryParse(ec?.toString() ?? '') ?? 0,
      airDate: json['airDate']?.toString(),
      overview: json['overview']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
    );
  }

  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? airDate;
  final String? overview;
  final String? posterUrl;
}

class TvSeasonListData {
  const TvSeasonListData({required this.items});

  factory TvSeasonListData.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? [];
    return TvSeasonListData(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(TvSeasonSummary.fromJson)
          .toList(),
    );
  }

  final List<TvSeasonSummary> items;
}

class TvEpisodeCatalog {
  const TvEpisodeCatalog({
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.airDate,
    this.stillUrl,
    this.runtimeMinutes,
    this.voteAverage,
    this.guestStars = const [],
    this.userRating,
    this.userRatingRatedAt,
    this.userWatchlist,
    this.userWatchlistedAt,
  });

  factory TvEpisodeCatalog.fromJson(Map<String, dynamic> json) {
    final en = json['episodeNumber'];
    final rt = json['runtimeMinutes'];
    final va = json['voteAverage'];
    final engagement = UserEpisodeEngagement.fromJson(json);
    final guests = (json['guestStars'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MovieDetailPerson.fromJson)
        .toList();
    return TvEpisodeCatalog(
      episodeNumber: en is int ? en : int.tryParse(en?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      overview: json['overview']?.toString(),
      airDate: json['airDate']?.toString(),
      stillUrl: json['stillUrl']?.toString(),
      runtimeMinutes: rt is int ? rt : int.tryParse(rt?.toString() ?? ''),
      voteAverage: va is num ? va.toDouble() : double.tryParse(va?.toString() ?? ''),
      guestStars: guests,
      userRating: engagement.userRating,
      userRatingRatedAt: engagement.userRatingRatedAt,
      userWatchlist: engagement.userWatchlist,
      userWatchlistedAt: engagement.userWatchlistedAt,
    );
  }

  final int episodeNumber;
  final String name;
  final String? overview;
  final String? airDate;
  final String? stillUrl;
  final int? runtimeMinutes;
  final double? voteAverage;
  final List<MovieDetailPerson> guestStars;
  final double? userRating;
  final String? userRatingRatedAt;
  final bool? userWatchlist;
  final String? userWatchlistedAt;
}

class TvSeasonDetailData {
  const TvSeasonDetailData({
    required this.seasonNumber,
    required this.name,
    this.overview,
    this.airDate,
    this.posterUrl,
    required this.episodes,
    required this.watchedEpisodes,
    this.cast = const [],
    this.ratings = const [],
    this.directors = const [],
    this.userSeasonRating,
    this.userSeasonRatingRatedAt,
    this.userSeasonWatchlist,
    this.userSeasonWatchlistedAt,
  });

  factory TvSeasonDetailData.fromJson(Map<String, dynamic> json) {
    final sn = json['seasonNumber'];
    final eps = (json['episodes'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(TvEpisodeCatalog.fromJson)
        .toList();
    final watched = (json['watchedEpisodes'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(WatchedEpisode.fromJson)
        .toList();
    final cast = (json['cast'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MovieDetailPerson.fromJson)
        .toList();
    final ratings = (json['ratings'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MovieDetailMetric.fromJson)
        .toList();
    final directors = (json['directors'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MovieDetailPerson.fromJson)
        .toList();
    final seasonEngagement = UserEpisodeEngagement.seasonFromJson(json);
    return TvSeasonDetailData(
      seasonNumber: sn is int ? sn : int.tryParse(sn?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      overview: json['overview']?.toString(),
      airDate: json['airDate']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      episodes: eps,
      watchedEpisodes: watched,
      cast: cast,
      ratings: ratings,
      directors: directors,
      userSeasonRating: seasonEngagement.userRating,
      userSeasonRatingRatedAt: seasonEngagement.userRatingRatedAt,
      userSeasonWatchlist: seasonEngagement.userWatchlist,
      userSeasonWatchlistedAt: seasonEngagement.userWatchlistedAt,
    );
  }

  final int seasonNumber;
  final String name;
  final String? overview;
  final String? airDate;
  final String? posterUrl;
  final List<TvEpisodeCatalog> episodes;
  final List<WatchedEpisode> watchedEpisodes;
  final List<MovieDetailPerson> cast;
  final List<MovieDetailMetric> ratings;
  final List<MovieDetailPerson> directors;
  final double? userSeasonRating;
  final String? userSeasonRatingRatedAt;
  final bool? userSeasonWatchlist;
  final String? userSeasonWatchlistedAt;

  bool episodeIsWatched(int episodeNumber) {
    return watchedEpisodes.episodeIsWatched(seasonNumber, episodeNumber);
  }

  int get _airedEpisodeCount =>
      episodes.where((e) => tvEpisodeAiredForWatch(e.airDate)).length;

  int get _watchedAiredCountInSeason => episodes
      .where((e) => tvEpisodeAiredForWatch(e.airDate) && episodeIsWatched(e.episodeNumber))
      .length;

  String? get seasonWatchProgressLabel {
    final t = _airedEpisodeCount;
    if (t <= 0) {
      return null;
    }
    final w = _watchedAiredCountInSeason;
    return '$w / $t';
  }

  bool get seasonFullyWatched =>
      _airedEpisodeCount > 0 && _watchedAiredCountInSeason >= _airedEpisodeCount;

  /// Unique guest stars across all episodes in this season (order preserved).
  List<MovieDetailPerson> distinctGuestStarsAcrossEpisodes() {
    final out = <MovieDetailPerson>[];
    final seen = <String>{};
    for (final ep in episodes) {
      for (final g in ep.guestStars) {
        final key = (g.personId != null && g.personId!.isNotEmpty) ? 'id:${g.personId}' : 'n:${g.name}';
        if (seen.add(key)) {
          out.add(g);
        }
      }
    }
    return out;
  }
}

List<MovieDetailPerson> mergeCreditPeopleLists(
  List<MovieDetailPerson> primary,
  List<MovieDetailPerson> extras,
) {
  if (extras.isEmpty) {
    return primary;
  }
  final seen = <String>{};
  for (final p in primary) {
    final key = p.personId != null && p.personId!.isNotEmpty ? 'id:${p.personId}' : 'n:${p.name}';
    seen.add(key);
  }
  final merged = [...primary];
  for (final p in extras) {
    final key = p.personId != null && p.personId!.isNotEmpty ? 'id:${p.personId}' : 'n:${p.name}';
    if (seen.add(key)) {
      merged.add(p);
    }
  }
  return merged;
}

class TvEpisodeDetailData {
  const TvEpisodeDetailData({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.airDate,
    this.stillUrl,
    this.runtimeMinutes,
    this.voteAverage,
    this.cast = const [],
    this.guestStars = const [],
    this.ratings = const [],
    this.directors = const [],
    this.watchedAt,
    this.userRating,
    this.userRatingRatedAt,
    this.userWatchlist,
    this.userWatchlistedAt,
  });

  factory TvEpisodeDetailData.fromJson(Map<String, dynamic> json) {
    final sn = json['seasonNumber'];
    final en = json['episodeNumber'];
    final rt = json['runtimeMinutes'];
    final va = json['voteAverage'];
    final cast = (json['cast'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MovieDetailPerson.fromJson)
        .toList();
    final guests = (json['guestStars'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MovieDetailPerson.fromJson)
        .toList();
    final ratings = (json['ratings'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MovieDetailMetric.fromJson)
        .toList();
    final directors = (json['directors'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MovieDetailPerson.fromJson)
        .toList();
    final engagement = UserEpisodeEngagement.fromJson(json);
    return TvEpisodeDetailData(
      seasonNumber: sn is int ? sn : int.tryParse(sn?.toString() ?? '') ?? 0,
      episodeNumber: en is int ? en : int.tryParse(en?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      overview: json['overview']?.toString(),
      airDate: json['airDate']?.toString(),
      stillUrl: json['stillUrl']?.toString(),
      runtimeMinutes: rt is int ? rt : int.tryParse(rt?.toString() ?? ''),
      voteAverage: va is num ? va.toDouble() : double.tryParse(va?.toString() ?? ''),
      cast: cast,
      guestStars: guests,
      ratings: ratings,
      directors: directors,
      watchedAt: json['watchedAt']?.toString(),
      userRating: engagement.userRating,
      userRatingRatedAt: engagement.userRatingRatedAt,
      userWatchlist: engagement.userWatchlist,
      userWatchlistedAt: engagement.userWatchlistedAt,
    );
  }

  final int seasonNumber;
  final int episodeNumber;
  final String name;
  final String? overview;
  final String? airDate;
  final String? stillUrl;
  final int? runtimeMinutes;
  final double? voteAverage;
  final List<MovieDetailPerson> cast;
  final List<MovieDetailPerson> guestStars;
  final List<MovieDetailMetric> ratings;
  final List<MovieDetailPerson> directors;
  final String? watchedAt;
  final double? userRating;
  final String? userRatingRatedAt;
  final bool? userWatchlist;
  final String? userWatchlistedAt;

  List<MovieDetailPerson> mergedCastAndGuests() => mergeCreditPeopleLists(cast, guestStars);
}
