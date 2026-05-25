import 'package:flutter/material.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/widgets/left_resume_sheet.dart';
import 'package:yamtrack/src/screens/widgets/tv_finish_watching_sheet.dart';
import 'package:yamtrack/src/screens/widgets/tv_series_watching_progress_button.dart';
import 'package:yamtrack/src/utils/tv_start_watching.dart';

typedef TvSeriesTrackingMutationRunner = Future<void> Function(
  Future<String?> Function(TrackingMutationController controller, String username) mutation,
);

/// Handles taps on the TV series **Watching** tile (finish / left-resume / start).
Future<void> handleTvSeriesWatchingTap({
  required BuildContext context,
  required CatalogDetail detail,
  required TvSeriesTrackingMutationRunner runTrackingMutation,
  required Future<void> Function() startWatchingTv,
}) async {
  final tracking = detail.tracking;

  if (tvSeriesIsActivelyWatching(tracking: tracking, detail: detail)) {
    await _showFinishWatchingSheet(
      context: context,
      detail: detail,
      runTrackingMutation: runTrackingMutation,
    );
    return;
  }

  if (trackingIsDropped(tracking)) {
    await _showLeftResumeSheet(
      context: context,
      detail: detail,
      runTrackingMutation: runTrackingMutation,
      startWatchingTv: startWatchingTv,
    );
    return;
  }

  if (tvSeriesWatchingTileShowsFinished(tracking: tracking, detail: detail) ||
      tvSeriesHasEpisodeProgress(tracking)) {
    await runTrackingMutation(
      (controller, username) => controller.toggleDoing(
        username: username,
        media: detail.media,
        tracking: tracking,
      ),
    );
    return;
  }

  await startWatchingTv();
}

Future<void> _showFinishWatchingSheet({
  required BuildContext context,
  required CatalogDetail detail,
  required TvSeriesTrackingMutationRunner runTrackingMutation,
}) async {
  final theme = Theme.of(context);
  final result = await showModalBottomSheet<TvFinishWatchingSheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surfaceContainerLow,
    builder: (sheetContext) {
      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: TvFinishWatchingSheet(
          seriesTitle: detail.media.title,
          initialScore: detail.tracking?.score,
        ),
      );
    },
  );
  if (result == null) {
    return;
  }

  if (result.outcome == TvWatchingOutcome.paused) {
    await runTrackingMutation(
      (controller, username) => controller.pauseWatchingTv(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
      ),
    );
    return;
  }

  await runTrackingMutation(
    (controller, username) => controller.finishWatchingTv(
      username: username,
      media: detail.media,
      tracking: detail.tracking,
      markAsFinished: result.outcome == TvWatchingOutcome.finished,
      score: result.score,
      actionAtUtc: result.actionAtUtc,
    ),
  );
}

Future<void> _showLeftResumeSheet({
  required BuildContext context,
  required CatalogDetail detail,
  required TvSeriesTrackingMutationRunner runTrackingMutation,
  required Future<void> Function() startWatchingTv,
}) async {
  final theme = Theme.of(context);
  final result = await showModalBottomSheet<LeftResumeSheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surfaceContainerLow,
    builder: (sheetContext) {
      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: LeftResumeSheet(
          headerTitle: 'Left',
          mediaTitle: detail.media.title,
          doingLabel: 'Resume watching',
          doingSubtitle: 'Back on Next up',
          doneLabel: 'Mark as finished',
          doneSubtitle: 'Moves to Finished',
          initialScore: detail.tracking?.score,
        ),
      );
    },
  );
  if (result == null) {
    return;
  }

  if (result.outcome == LeftResumeOutcome.doing) {
    final tracking = detail.tracking;
    if (trackingIsDropped(tracking)) {
      await runTrackingMutation(
        (controller, username) => controller.toggleDropped(
          username: username,
          media: detail.media,
          tracking: tracking,
        ),
      );
    }
    if (!tvSeriesHasEpisodeProgress(tracking) && !trackingIsDoing(tracking)) {
      await startWatchingTv();
    } else if (!trackingIsDoing(tracking)) {
      await runTrackingMutation(
        (controller, username) => controller.toggleDoing(
          username: username,
          media: detail.media,
          tracking: tracking,
        ),
      );
    }
    return;
  }

  await runTrackingMutation(
    (controller, username) => controller.finishWatchingTv(
      username: username,
      media: detail.media,
      tracking: detail.tracking,
      markAsFinished: true,
      score: result.score,
      actionAtUtc: result.actionAtUtc,
    ),
  );
}
