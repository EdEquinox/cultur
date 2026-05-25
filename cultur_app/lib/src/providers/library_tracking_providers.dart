import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/library/watched_tv_episode_library_row.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

final libraryTrackingForScopeProvider =
    FutureProvider.autoDispose.family<TrackingListData, LibraryMediaScope>((
  ref,
  scope,
) async {
  final authState = ref.watch(authControllerProvider).asData?.value;
  final username = authState?.session?.username;
  if (username == null || username.isEmpty) {
    return const TrackingListData(items: []);
  }

  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson(
    '/backend/tracking',
    queryParameters: {
      'username': username,
      'mediaType': scope.trackingApiMediaType,
      'limit': 2000,
    },
  );
  return TrackingListData.fromJson(payload);
});

/// All watched TV episodes for the Library → TV → Watched tab (newest `watchedAt` first).
final tvWatchedEpisodesLibraryProvider =
    FutureProvider.autoDispose<TvWatchedEpisodesLibraryData>((ref) async {
  final authState = ref.watch(authControllerProvider).asData?.value;
  final username = authState?.session?.username;
  if (username == null || username.isEmpty) {
    return const TvWatchedEpisodesLibraryData(items: []);
  }
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson(
    '/backend/tracking/tv/watched-episodes',
    queryParameters: {
      'username': username,
      'limit': '500',
    },
  );
  return TvWatchedEpisodesLibraryData.fromJson(payload);
});

/// TV series where every aired episode (all seasons) has been marked watched.
final tvFullyWatchedSeriesLibraryProvider =
    FutureProvider.autoDispose.family<TrackingListData, String>((ref, username) async {
  if (username.isEmpty) {
    return const TrackingListData(items: []);
  }
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson(
    '/backend/tracking/tv/fully-watched-series',
    queryParameters: {
      'username': username,
      'limit': '500',
    },
  );
  return TrackingListData.fromJson(payload);
});

/// Rebuilds cached TV progress / fully-watched flags (after upgrade or bulk import).
Future<int> recomputeTvSeriesWatchState(
  ApiClient client, {
  required String username,
  int limit = 200,
}) async {
  if (username.isEmpty) {
    return 0;
  }
  final payload = await client.postJson(
    '/backend/tracking/tv/recompute-series-state'
    '?username=${Uri.encodeComponent(username)}&limit=$limit',
  );
  return switch (payload['updated']) {
    int value => value,
    String value => int.tryParse(value) ?? 0,
    _ => 0,
  };
}
