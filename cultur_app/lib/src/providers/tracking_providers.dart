import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/next_to_watch_providers.dart';

final trackingMutationControllerProvider = Provider<TrackingMutationController>((
  ref,
) {
  return TrackingMutationController(ref.watch(apiClientProvider));
});

final episodeWatchMutationControllerProvider =
    Provider<EpisodeWatchMutationController>((ref) {
      return EpisodeWatchMutationController(ref.watch(apiClientProvider));
    });

class EpisodeWatchMutationController {
  const EpisodeWatchMutationController(this._client);

  final ApiClient _client;

  Future<void> putEpisodeWatched({
    required String username,
    required String mediaId,
    required int seasonNumber,
    required int episodeNumber,
    required bool watched,
    DateTime? watchedAtUtc,
  }) async {
    final data = <String, dynamic>{
      'username': username,
      'mediaId': mediaId,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'watched': watched,
    };
    if (watched && watchedAtUtc != null) {
      data['watchedAt'] = watchedAtUtc.toIso8601String().replaceAll('+00:00', 'Z');
    }
    await _client.putJson('/backend/tracking/tv/episodes', data: data);
  }

  Future<void> markEpisodesWatchedThrough({
    required String username,
    required String mediaId,
    required int throughSeasonNumber,
    required int throughEpisodeNumber,
    DateTime? watchedAtUtc,
    int? onlySeasonNumber,
  }) async {
    final data = <String, dynamic>{
      'username': username,
      'mediaId': mediaId,
      'throughSeasonNumber': throughSeasonNumber,
      'throughEpisodeNumber': throughEpisodeNumber,
    };
    if (watchedAtUtc != null) {
      data['watchedAt'] = watchedAtUtc.toIso8601String().replaceAll('+00:00', 'Z');
    }
    if (onlySeasonNumber != null) {
      data['onlySeasonNumber'] = onlySeasonNumber;
    }
    await _client.putJson('/backend/tracking/tv/episodes/mark-through', data: data);
  }

  Future<void> clearSeasonEpisodeWatches({
    required String username,
    required String mediaId,
    required int seasonNumber,
  }) async {
    await _client.putJson(
      '/backend/tracking/tv/episodes/clear-season',
      data: {
        'username': username,
        'mediaId': mediaId,
        'seasonNumber': seasonNumber,
      },
    );
  }
}

/// Refreshes TV home shelves and library after an episode watch change.
void invalidateTvEpisodeWatchCaches(WidgetRef ref, {required String username}) {
  if (username.isEmpty) {
    return;
  }
  invalidateNextToWatchCaches(ref, username: username, isTv: true);
  ref.invalidate(tvWatchedEpisodesLibraryProvider);
  ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.tv));
}
