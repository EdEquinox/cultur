import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';

/// Marks S1E1 watched and removes the show from Later (watchlist) so it appears
/// on TV home **Continue watching** (next up), not only in the priority queue.
Future<void> startTvSeriesFromFirstEpisode({
  required EpisodeWatchMutationController episodes,
  required TrackingMutationController tracking,
  required String username,
  required CatalogItem media,
  TrackingItem? trackingItem,
}) async {
  await episodes.putEpisodeWatched(
    username: username,
    mediaId: media.id,
    seasonNumber: 1,
    episodeNumber: 1,
    watched: true,
    watchedAtUtc: DateTime.now().toUtc(),
  );

  if (trackingIsInWatchlist(trackingItem)) {
    await tracking.toggleWatchlist(
      username: username,
      media: media,
      tracking: trackingItem,
    );
  }

  if (!trackingIsDoing(trackingItem) && !trackingIsDropped(trackingItem)) {
    await tracking.toggleDoing(
      username: username,
      media: media,
      tracking: trackingItem,
    );
  }
}

bool tvSeriesHasEpisodeProgress(TrackingItem? tracking) {
  final count = tracking?.episodeWatchedCount;
  return count != null && count > 0;
}
