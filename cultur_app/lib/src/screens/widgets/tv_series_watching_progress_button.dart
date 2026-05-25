import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

/// Episode progress label for a series being tracked (e.g. `12/24`).
String? tvSeriesEpisodeProgressLabel({
  TrackingItem? tracking,
  CatalogDetail? detail,
}) {
  final watched = tracking?.episodeWatchedCount ?? detail?.watchedEpisodes.length ?? 0;
  if (watched <= 0) {
    return null;
  }
  final total = tracking?.tvAiredEpisodeTotal ?? detail?.tvTotalEpisodesFromFacts;
  if (total != null && total > 0) {
    return '$watched/$total';
  }
  return '$watched/—';
}

int tvSeriesWatchedEpisodeCount({
  required TrackingItem? tracking,
  required CatalogDetail detail,
}) {
  final fromTracking = tracking?.episodeWatchedCount;
  if (fromTracking != null && fromTracking > 0) {
    return fromTracking;
  }
  return detail.watchedEpisodes.length;
}

/// Series is actively followed (episode progress or doing), excluding Left.
bool tvSeriesIsActivelyWatching({
  required TrackingItem? tracking,
  required CatalogDetail detail,
}) {
  if (trackingIsDropped(tracking)) {
    return false;
  }
  final watched = tvSeriesWatchedEpisodeCount(tracking: tracking, detail: detail);
  if (watched > 0 || trackingIsDoing(tracking)) {
    if (tracking != null &&
        tracking.tvFullyWatched &&
        trackingIsWatched(tracking) &&
        !trackingIsDoing(tracking)) {
      return false;
    }
    return true;
  }
  return false;
}

/// Watching tile shows check when the series is finished (not actively following).
bool tvSeriesWatchingTileShowsFinished({
  required TrackingItem? tracking,
  required CatalogDetail detail,
}) {
  if (tvSeriesIsActivelyWatching(tracking: tracking, detail: detail)) {
    return false;
  }
  return trackingIsWatched(tracking) ||
      (tracking?.tvFullyWatched == true &&
          tvSeriesWatchedEpisodeCount(tracking: tracking, detail: detail) > 0);
}
