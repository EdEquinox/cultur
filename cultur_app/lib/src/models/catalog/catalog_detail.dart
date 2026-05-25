import 'package:yamtrack/src/models/catalog/catalog_detail_crew_group.dart';
import 'package:yamtrack/src/models/games/game_collection_link.dart';
import 'package:yamtrack/src/models/books/book_publisher_link.dart';
import 'package:yamtrack/src/models/games/game_company_link.dart';
import 'package:yamtrack/src/models/games/game_franchise_link.dart';
import 'package:yamtrack/src/models/games/game_time_to_beat.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_metric.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_person.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail_video.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/catalog/catalog_link.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/models/tv/series_detail.dart';
import 'package:yamtrack/src/models/tv/tv_next_episode_card_data.dart';

/// Unified catalog detail payload (`MovieCatalogDetailResponse` on the API).
class CatalogDetail {
  const CatalogDetail({
    required this.media,
    required this.galleryUrls,
    required this.genres,
    required this.keywords,
    required this.ratings,
    required this.facts,
    required this.cast,
    required this.crew,
    required this.videos,
    required this.recommendations,
    required this.links,
    this.gamePublishers = const [],
    this.gameDevelopers = const [],
    this.bookPublishers = const [],
    this.gameTimeToBeat,
    this.gameFranchise,
    this.gameCollections = const [],
    this.gameType,
    this.gameModes = const [],
    this.playerPerspectives = const [],
    this.overview,
    this.backdropUrl,
    this.tracking,
    this.watchedEpisodes = const [],
    this.nextEpisodeCard,
    this.catalogPending = false,
    this.importSource,
  });

  factory CatalogDetail.fromJson(Map<String, dynamic> json) {
    final genres = (json['genres'] as List<dynamic>? ?? [])
        .map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList();
    final keywords = (json['keywords'] as List<dynamic>? ?? [])
        .map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList();
    final ratings = (json['ratings'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogDetailMetric.fromJson)
        .toList();
    final facts = (json['facts'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogDetailMetric.fromJson)
        .toList();
    final cast = (json['cast'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogDetailPerson.fromJson)
        .toList();
    final crew = (json['crew'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogDetailCrewGroup.fromJson)
        .toList();
    final videos = (json['videos'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogDetailVideo.fromJson)
        .toList();
    final recommendations = (json['recommendations'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogItem.fromJson)
        .toList();
    final links = (json['links'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CatalogLink.fromJson)
        .toList();
    final gamePublishers = (json['gamePublishers'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(GameCompanyLink.fromJson)
        .where((c) => c.isValid)
        .toList();
    final gameDevelopers = (json['gameDevelopers'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(GameCompanyLink.fromJson)
        .where((c) => c.isValid)
        .toList();
    final bookPublishers = (json['bookPublishers'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(BookPublisherLink.fromJson)
        .where((p) => p.isValid)
        .toList();
    final gameTimeToBeatRaw = json['gameTimeToBeat'];
    final gameTimeToBeat = gameTimeToBeatRaw is Map<String, dynamic>
        ? GameTimeToBeat.fromJson(gameTimeToBeatRaw)
        : null;
    final franchiseRaw = json['gameFranchise'];
    final gameFranchise = franchiseRaw is Map<String, dynamic>
        ? GameFranchiseLink.fromJson(franchiseRaw)
        : null;
    final gameCollections = (json['gameCollections'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(GameCollectionLink.fromJson)
        .where((c) => c.isValid)
        .toList();
    final gameModes = (json['gameModes'] as List<dynamic>? ?? [])
        .map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList();
    final playerPerspectives = (json['playerPerspectives'] as List<dynamic>? ?? [])
        .map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList();
    final watchedEpisodes = (json['watchedEpisodes'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(WatchedEpisode.fromJson)
        .toList();
    final nextRaw = json['nextEpisodeCard'];
    final nextEpisodeCard = nextRaw is Map<String, dynamic>
        ? TvNextEpisodeCardData.fromJson(nextRaw)
        : null;
    final media = CatalogItem.fromJson(
      (json['media'] as Map<String, dynamic>?) ?? const {},
    );

    return CatalogDetail(
      media: media,
      overview: json['overview']?.toString(),
      backdropUrl: json['backdropUrl']?.toString(),
      galleryUrls: (json['galleryUrls'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .where((value) => value.trim().isNotEmpty)
          .toList(),
      genres: genres,
      keywords: keywords,
      ratings: ratings,
      facts: facts,
      cast: cast,
      crew: crew,
      videos: videos,
      recommendations: recommendations,
      links: links,
      gamePublishers: gamePublishers,
      gameDevelopers: gameDevelopers,
      bookPublishers: bookPublishers,
      gameTimeToBeat: gameTimeToBeat?.hasAny == true ? gameTimeToBeat : null,
      gameFranchise: gameFranchise?.isValid == true ? gameFranchise : null,
      gameCollections: gameCollections,
      gameType: json['gameType']?.toString(),
      gameModes: gameModes,
      playerPerspectives: playerPerspectives,
      tracking: json['tracking'] is Map<String, dynamic>
          ? TrackingItem.fromJson(json['tracking'] as Map<String, dynamic>)
          : null,
      watchedEpisodes: watchedEpisodes,
      nextEpisodeCard: nextEpisodeCard,
      catalogPending: json['catalogPending'] == true || media.isCatalogPending,
      importSource: json['importSource']?.toString(),
    );
  }

  final CatalogItem media;
  final String? overview;
  final String? backdropUrl;
  final List<String> galleryUrls;
  final List<String> genres;
  final List<String> keywords;
  final List<CatalogDetailMetric> ratings;
  final List<CatalogDetailMetric> facts;
  final List<CatalogDetailPerson> cast;
  final List<CatalogDetailCrewGroup> crew;
  final List<CatalogDetailVideo> videos;
  final List<CatalogItem> recommendations;
  final List<CatalogLink> links;
  final List<GameCompanyLink> gamePublishers;
  final List<GameCompanyLink> gameDevelopers;
  final List<BookPublisherLink> bookPublishers;
  final GameTimeToBeat? gameTimeToBeat;
  final GameFranchiseLink? gameFranchise;
  final List<GameCollectionLink> gameCollections;
  final String? gameType;
  final List<String> gameModes;
  final List<String> playerPerspectives;
  final TrackingItem? tracking;
  final List<WatchedEpisode> watchedEpisodes;
  final TvNextEpisodeCardData? nextEpisodeCard;
  final bool catalogPending;
  final String? importSource;

  String factValue(String label) {
    for (final fact in facts) {
      if (fact.label == label) {
        return fact.value;
      }
    }
    return '';
  }

  int? get tvTotalEpisodesFromFacts {
    final raw = factValue('Episodes').replaceAll(',', '').trim();
    return int.tryParse(raw);
  }

  String? get tvWatchedProgressLabel {
    final y = tvTotalEpisodesFromFacts;
    final x = watchedEpisodes.length;
    if (y != null && y > 0) {
      return '$x / $y';
    }
    if (x > 0) {
      return '$x / —';
    }
    return null;
  }

  bool episodeIsWatched(int seasonNumber, int episodeNumber) {
    return watchedEpisodes.episodeIsWatched(seasonNumber, episodeNumber);
  }
}
