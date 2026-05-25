import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/tv/series_detail.dart';

final tvSeasonListCatalogProvider =
    FutureProvider.autoDispose.family<TvSeasonListData, String>((ref, mediaId) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson('/catalog/tv/$mediaId/seasons');
      return TvSeasonListData.fromJson(payload);
    });

@immutable
class TvSeasonDetailCatalogRequest {
  const TvSeasonDetailCatalogRequest({
    required this.mediaId,
    required this.seasonNumber,
    this.username,
  });

  final String mediaId;
  final int seasonNumber;
  final String? username;

  @override
  bool operator ==(Object other) {
    return other is TvSeasonDetailCatalogRequest &&
        other.mediaId == mediaId &&
        other.seasonNumber == seasonNumber &&
        other.username == username;
  }

  @override
  int get hashCode => Object.hash(mediaId, seasonNumber, username);
}

final tvSeasonDetailCatalogProvider =
    FutureProvider.autoDispose.family<TvSeasonDetailData, TvSeasonDetailCatalogRequest>((
      ref,
      request,
    ) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/tv/${request.mediaId}/seasons/${request.seasonNumber}',
        queryParameters: {
          if (request.username != null && request.username!.isNotEmpty)
            'username': request.username,
        },
      );
      return TvSeasonDetailData.fromJson(payload);
    });

@immutable
class TvEpisodeDetailCatalogRequest {
  const TvEpisodeDetailCatalogRequest({
    required this.mediaId,
    required this.seasonNumber,
    required this.episodeNumber,
    this.username,
  });

  final String mediaId;
  final int seasonNumber;
  final int episodeNumber;
  final String? username;

  @override
  bool operator ==(Object other) {
    return other is TvEpisodeDetailCatalogRequest &&
        other.mediaId == mediaId &&
        other.seasonNumber == seasonNumber &&
        other.episodeNumber == episodeNumber &&
        other.username == username;
  }

  @override
  int get hashCode => Object.hash(mediaId, seasonNumber, episodeNumber, username);
}

final tvEpisodeDetailCatalogProvider =
    FutureProvider.autoDispose.family<TvEpisodeDetailData, TvEpisodeDetailCatalogRequest>((
      ref,
      request,
    ) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/tv/${request.mediaId}/seasons/${request.seasonNumber}/episodes/${request.episodeNumber}',
        queryParameters: {
          if (request.username != null && request.username!.isNotEmpty)
            'username': request.username,
        },
      );
      return TvEpisodeDetailData.fromJson(payload);
    });
