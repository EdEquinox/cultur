import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/models/library/collected_ownership.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';


/// Controller for managing tracking state and actions.
/// Handles toggling collected, priority, watchlist, watched, marking as watched, saving ratings,
/// toggling dropped, doing, and buying statuses.
class TrackingMutationController {
  const TrackingMutationController(this._client);

  final ApiClient _client;

  /// Toggles the collected status for a given media item.
  Future<String> toggleCollected({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking);
    final willEnable = !flags.contains(kCollectedTrackingFlag);
    if (willEnable) {
      flags
        ..add(kCollectedTrackingFlag)
        ..remove(kBuyTrackingFlag);
    } else {
      flags.remove(kCollectedTrackingFlag);
    }

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      writeCollectedAt: true,
      collectedAtUtc: willEnable ? DateTime.now().toUtc() : null,
      clearLent: !willEnable,
      clearCollectedPrice: !willEnable,
      clearMbReleaseId: !willEnable,
    );
    return willEnable
        ? 'Added to Owned.'
        : 'Removed from Owned.';
  }

  /// Persists how a collected title is owned (physical/digital, official/unofficial).
  Future<String> saveCollectedOwnership({
    required String username,
    required CatalogItem media,
    required TrackingItem? tracking,
    required CollectedOwnershipVariant variant,
    String? price,
    String? mbReleaseId,
  }) async {
    final wasCollected = hasTrackingFlag(tracking, kCollectedTrackingFlag);
    final flags = trackingFlags(tracking)..add(kCollectedTrackingFlag);
    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      ownedVariant: variant,
      collectedPrice: price,
      mbReleaseId: mbReleaseId,
      writeCollectedAt: true,
      collectedAtUtc: wasCollected ? tracking?.collectedAt?.toUtc() : DateTime.now().toUtc(),
    );
    return wasCollected ? 'Ownership updated.' : 'Added to Collected.';
  }

  /// Marks a MusicBrainz release group as owned with a specific release pressing.
  Future<String> saveAlbumOwnedRelease({
    required String username,
    required CatalogItem media,
    required TrackingItem? tracking,
    required String mbReleaseId,
    String? price,
  }) async {
    return saveCollectedOwnership(
      username: username,
      media: media,
      tracking: tracking,
      variant: CollectedOwnershipVariant.physicalLegal,
      mbReleaseId: mbReleaseId,
      price: price,
    );
  }

  /// Marks a collected title as lent to [borrowerName].
  Future<String> setCollectedLent({
    required String username,
    required CatalogItem media,
    required TrackingItem tracking,
    required String borrowerName,
    DateTime? lentAtUtc,
  }) async {
    final flags = trackingFlags(tracking)..add(kCollectedTrackingFlag);
    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      lent: CollectedLentInfo(
        borrowerName: borrowerName.trim(),
        lentAt: lentAtUtc ?? DateTime.now().toUtc(),
      ),
    );
    return 'Marked as lent to ${borrowerName.trim()}.';
  }

  /// Clears lent status; title stays in Owned.
  Future<String> clearCollectedLent({
    required String username,
    required CatalogItem media,
    required TrackingItem tracking,
  }) async {
    final flags = trackingFlags(tracking)..add(kCollectedTrackingFlag);
    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      clearLent: true,
    );
    return 'Marked as returned.';
  }

  /// Toggles the priority status for a given media item.
  Future<String> togglePriority({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking);
    final isOn = flags.contains(kPriorityTrackingFlag);
    if (isOn) {
      flags.remove(kPriorityTrackingFlag);
    } else {
      flags
        ..add(kPriorityTrackingFlag)
        ..remove(kDroppedTrackingFlag);
    }

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
    );
    return isOn ? 'Removed from priority queue.' : 'Marked as priority.';
  }

  /// Toggles the watchlist status for a given media item.
  Future<String> toggleWatchlist({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking);
    final isEnabled = trackingIsInWatchlist(tracking);
    if (isEnabled) {
      flags.remove(kWatchlistTrackingFlag);
    } else {
      flags
        ..remove(kWatchedTrackingFlag)
        ..remove(kDroppedTrackingFlag)
        ..remove(kDoingTrackingFlag)
        ..add(kWatchlistTrackingFlag);
    }

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      status: isEnabled ? 'In progress' : 'Planning',
      flags: flags,
    );
    return isEnabled
        ? 'Removed from Later.'
        : 'Added to Later.';
  }

  /// Toggles the watched status for a given media item.
  Future<String> toggleWatched({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking);
    final isWatched = trackingIsWatched(tracking);
    if (!isWatched &&
        media.mediaType == 'tv' &&
        !trackingCanMarkTvAsWatched(tracking)) {
      return 'Mark every aired episode as watched before marking this series as finished.';
    }
    if (isWatched) {
      flags.remove(kWatchedTrackingFlag);
    } else {
      flags
        ..remove(kWatchlistTrackingFlag)
        ..remove(kDroppedTrackingFlag)
        ..remove(kDoingTrackingFlag)
        ..add(kWatchedTrackingFlag);
    }

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      status: isWatched ? 'In progress' : 'Completed',
      flags: flags,
      writeCompletedAt: true,
      completedAtUtc: isWatched ? null : DateTime.now().toUtc(),
      writeDroppedAt: true,
      droppedAtUtc: null,
    );
    return isWatched ? 'Removed from Finished.' : 'Marked as Finished.';
  }

  /// Marks a media item as watched with a specific completion date and score.
  Future<String> markAsWatched({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
    required DateTime? completedAtUtc,
    double? score,
  }) async {
    if (media.mediaType == 'tv' && !trackingCanMarkTvAsWatched(tracking)) {
      return 'Mark every aired episode as watched before marking this series as finished.';
    }
    final flags = trackingFlags(tracking)
      ..remove(kWatchlistTrackingFlag)
      ..remove(kDroppedTrackingFlag)
      ..remove(kDoingTrackingFlag)
      ..add(kWatchedTrackingFlag);

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: 'Completed',
      score: score,
      writeCompletedAt: true,
      completedAtUtc: completedAtUtc,
      writeDroppedAt: true,
      droppedAtUtc: null,
    );
    return 'Marked as Finished.';
  }

  /// Saves or clears the user rating on a media item.
  Future<String> saveRating({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
    double? score,
    bool remove = false,
  }) async {
    if (remove) {
      await _writeTracking(
        username: username,
        media: media,
        tracking: tracking,
        flags: trackingFlags(tracking),
        clearScore: true,
      );
      return 'Rating removed.';
    }
    if (score == null || score <= 0) {
      throw ArgumentError('score must be between 1 and 10 when not removing');
    }
    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: trackingFlags(tracking),
      score: score,
    );
    return 'Rating saved.';
  }

  /// Toggles the dropped status for a given media item.
  Future<String> toggleDropped({
    required String username,
    required CatalogItem media,
    required TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking);
    final isOn = trackingIsDropped(tracking);
    if (isOn) {
      flags.remove(kDroppedTrackingFlag);
    } else {
      flags
        ..add(kDroppedTrackingFlag)
        ..remove(kPriorityTrackingFlag)
        ..remove(kDoingTrackingFlag)
        ..remove(kBuyTrackingFlag);
    }

    final nextStatus = isOn
        ? (flags.contains(kWatchlistTrackingFlag) ? 'Planning' : 'In progress')
        : 'Dropped';

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: nextStatus,
      writeDroppedAt: true,
      droppedAtUtc: isOn ? null : DateTime.now().toUtc(),
      writeCompletedAt: !isOn,
      completedAtUtc: null,
    );
    return isOn
        ? 'Removed from Left — back in your active lists.'
        : 'Moved to Left — hidden from Next up shelves.';
  }

  /// Ends an in-progress game: mark played or dropped and optionally save a rating.
  Future<String> finishPlayingGame({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
    required bool markAsPlayed,
    double? score,
    DateTime? actionAtUtc,
  }) async {
    final flags = trackingFlags(tracking)
      ..remove(kDoingTrackingFlag)
      ..remove(kWatchlistTrackingFlag)
      ..remove(kBuyTrackingFlag);

    if (markAsPlayed) {
      flags
        ..remove(kDroppedTrackingFlag)
        ..add(kWatchedTrackingFlag);
      await _writeTracking(
        username: username,
        media: media,
        tracking: tracking,
        flags: flags,
        status: 'Completed',
        score: score,
        writeCompletedAt: true,
        completedAtUtc: DateTime.now().toUtc(),
      );
      if (score != null) {
        return 'Marked as played with your rating.';
      }
      return 'Marked as played.';
    }

    flags
      ..add(kDroppedTrackingFlag)
      ..remove(kPriorityTrackingFlag)
      ..remove(kWatchedTrackingFlag);
    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: 'Dropped',
      score: score,
      writeDroppedAt: true,
      droppedAtUtc: actionAtUtc ?? DateTime.now().toUtc(),
      writeCompletedAt: true,
      completedAtUtc: null,
    );
    if (score != null) {
      return 'Marked as dropped with your rating saved.';
    }
    return 'Marked as dropped.';
  }

  /// Pauses an in-progress game and returns it to Later.
  Future<String> pausePlayingGame({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking)
      ..remove(kDoingTrackingFlag)
      ..remove(kWatchedTrackingFlag)
      ..remove(kDroppedTrackingFlag)
      ..add(kWatchlistTrackingFlag);

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: 'Planning',
    );
    return 'Paused — back on your Later list.';
  }

  /// Marks a book as currently reading (or removes from Reading).
  Future<String> toggleReading({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking);
    final isOn = trackingIsDoing(tracking);
    if (isOn) {
      flags.remove(kDoingTrackingFlag);
    } else {
      flags
        ..add(kDoingTrackingFlag)
        ..remove(kWatchlistTrackingFlag)
        ..remove(kWatchedTrackingFlag)
        ..remove(kDroppedTrackingFlag)
        ..remove(kBuyTrackingFlag);
    }

    final String? nextStatus;
    if (isOn) {
      nextStatus = flags.contains(kWatchlistTrackingFlag) ? 'Planning' : '';
    } else {
      nextStatus = 'In progress';
    }

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: nextStatus,
      progress: isOn ? 0 : (tracking?.progress ?? 0),
      writeStartedAt: true,
      startedAtUtc: isOn ? null : DateTime.now().toUtc(),
    );
    return isOn ? 'Removed from Reading.' : 'Added to Reading.';
  }

  /// Ends an in-progress book: mark read, left, or pause back to Later.
  Future<String> finishReadingBook({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
    required bool markAsRead,
    double? score,
    DateTime? actionAtUtc,
  }) async {
    final flags = trackingFlags(tracking)
      ..remove(kDoingTrackingFlag)
      ..remove(kWatchlistTrackingFlag)
      ..remove(kBuyTrackingFlag);

    if (markAsRead) {
      flags
        ..remove(kDroppedTrackingFlag)
        ..add(kWatchedTrackingFlag);
      await _writeTracking(
        username: username,
        media: media,
        tracking: tracking,
        flags: flags,
        status: 'Completed',
        score: score,
        writeCompletedAt: true,
        completedAtUtc: actionAtUtc ?? DateTime.now().toUtc(),
      );
      if (score != null) {
        return 'Marked as read with your rating.';
      }
      return 'Marked as read.';
    }

    flags
      ..add(kDroppedTrackingFlag)
      ..remove(kPriorityTrackingFlag)
      ..remove(kWatchedTrackingFlag);
    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: 'Dropped',
      score: score,
      progress: 0,
      writeDroppedAt: true,
      droppedAtUtc: actionAtUtc ?? DateTime.now().toUtc(),
      writeCompletedAt: true,
      completedAtUtc: null,
    );
    if (score != null) {
      return 'Marked as left with your rating saved.';
    }
    return 'Marked as left.';
  }

  /// Ends or pauses an in-progress TV series (series-level tracking flags).
  Future<String> finishWatchingTv({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
    required bool markAsFinished,
    double? score,
    DateTime? actionAtUtc,
  }) async {
    if (markAsFinished &&
        media.mediaType == 'tv' &&
        !trackingCanMarkTvAsWatched(tracking)) {
      return 'Mark every aired episode as watched before marking this series as finished.';
    }

    final flags = trackingFlags(tracking)
      ..remove(kDoingTrackingFlag)
      ..remove(kWatchlistTrackingFlag)
      ..remove(kBuyTrackingFlag);

    if (markAsFinished) {
      flags
        ..remove(kDroppedTrackingFlag)
        ..add(kWatchedTrackingFlag);
      await _writeTracking(
        username: username,
        media: media,
        tracking: tracking,
        flags: flags,
        status: 'Completed',
        score: score,
        writeCompletedAt: true,
        completedAtUtc: actionAtUtc ?? DateTime.now().toUtc(),
      );
      if (score != null) {
        return 'Marked as finished with your rating.';
      }
      return 'Marked as finished.';
    }

    flags
      ..add(kDroppedTrackingFlag)
      ..remove(kPriorityTrackingFlag)
      ..remove(kWatchedTrackingFlag);
    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: 'Dropped',
      score: score,
      writeDroppedAt: true,
      droppedAtUtc: actionAtUtc ?? DateTime.now().toUtc(),
      writeCompletedAt: true,
      completedAtUtc: null,
    );
    if (score != null) {
      return 'Stopped watching — rating saved.';
    }
    return 'Stopped watching — hidden from Next up.';
  }

  /// Pauses an in-progress TV series and returns it to Later.
  Future<String> pauseWatchingTv({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking)
      ..remove(kDoingTrackingFlag)
      ..remove(kWatchedTrackingFlag)
      ..remove(kDroppedTrackingFlag)
      ..add(kWatchlistTrackingFlag);

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: 'Planning',
    );
    return 'Paused — back on your Later list.';
  }

  /// Pauses an in-progress book and returns it to Later.
  Future<String> pauseReadingBook({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking)
      ..remove(kDoingTrackingFlag)
      ..remove(kWatchedTrackingFlag)
      ..remove(kDroppedTrackingFlag)
      ..add(kWatchlistTrackingFlag);

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: 'Planning',
      progress: 0,
    );
    return 'Paused — back on your Later list.';
  }

  /// Updates the current page for a book being read.
  Future<String> updateReadingProgress({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
    required int currentPage,
  }) async {
    final safePage = currentPage < 0 ? 0 : currentPage;
    final flags = trackingFlags(tracking)
      ..add(kDoingTrackingFlag)
      ..remove(kWatchlistTrackingFlag)
      ..remove(kWatchedTrackingFlag)
      ..remove(kDroppedTrackingFlag);

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: 'In progress',
      progress: safePage,
      writeStartedAt: tracking?.startedAt == null,
      startedAtUtc: DateTime.now().toUtc(),
    );
    return 'Reading progress updated.';
  }

  /// Toggles the doing status for a given media item.
  Future<String> toggleDoing({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking);
    final isOn = trackingIsDoing(tracking);
    if (isOn) {
      flags.remove(kDoingTrackingFlag);
    } else {
      flags
        ..add(kDoingTrackingFlag)
        ..remove(kWatchlistTrackingFlag)
        ..remove(kWatchedTrackingFlag)
        ..remove(kDroppedTrackingFlag)
        ..remove(kBuyTrackingFlag);
    }

    final String? nextStatus;
    if (isOn) {
      nextStatus = flags.contains(kWatchlistTrackingFlag) ? 'Planning' : '';
    } else {
      nextStatus = 'In progress';
    }

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
      status: nextStatus,
      writeStartedAt: true,
      startedAtUtc: isOn ? null : DateTime.now().toUtc(),
    );
    return isOn ? 'Removed from Playing.' : 'Marked as playing.';
  }

  /// Toggles the buy status for a given media item.
  Future<String> toggleBuy({
    required String username,
    required CatalogItem media,
    TrackingItem? tracking,
  }) async {
    final flags = trackingFlags(tracking);
    final isOn = trackingIsBuy(tracking);
    if (isOn) {
      flags.remove(kBuyTrackingFlag);
    } else {
      flags
        ..add(kBuyTrackingFlag)
        ..remove(kDroppedTrackingFlag);
    }

    await _writeTracking(
      username: username,
      media: media,
      tracking: tracking,
      flags: flags,
    );
    return isOn ? 'Removed from Buy.' : 'Marked as Buy — want to get or collect this.';
  }

  /// Writes the tracking data to the server.
  Future<void> _writeTracking({
    required String username,
    required CatalogItem media,
    required Set<String> flags,
    TrackingItem? tracking,
    String? status,
    double? score,
    bool clearScore = false,
    bool writeCompletedAt = false,
    DateTime? completedAtUtc,
    bool writeStartedAt = false,
    DateTime? startedAtUtc,
    bool writeDroppedAt = false,
    DateTime? droppedAtUtc,
    bool writeCollectedAt = false,
    DateTime? collectedAtUtc,
    CollectedOwnershipVariant? ownedVariant,
    String? collectedPrice,
    String? mbReleaseId,
    bool clearMbReleaseId = false,
    CollectedLentInfo? lent,
    bool clearLent = false,
    bool clearCollectedPrice = false,
    int? progress,
  }) async {
    final nextNotes = composeTrackingNotes(
      existingNotes: tracking?.notes,
      flags: flags,
      ownedStorageKey: ownedVariant?.storageKey,
      collectedPrice: collectedPrice,
      clearCollectedPrice: clearCollectedPrice,
      mbReleaseId: mbReleaseId,
      clearMbReleaseId: clearMbReleaseId,
      lent: lent,
      clearLent: clearLent,
    );
    final String nextStatus;
    if (status != null) {
      nextStatus = status;
    } else if (flags.contains(kDroppedTrackingFlag)) {
      nextStatus = 'Dropped';
    } else {
      final ts = tracking?.status.trim() ?? '';
      if (ts.isNotEmpty && ts.toLowerCase() != 'dropped') {
        nextStatus = tracking!.status;
      } else {
        nextStatus =
            flags.contains(kWatchlistTrackingFlag) ? 'Planning' : 'In progress';
      }
    }

    final payload = <String, dynamic>{
      'username': username,
      'mediaId': media.id,
      'status': nextStatus,
      'notes': nextNotes,
    };
    if (progress != null) {
      payload['progress'] = progress;
    } else if (tracking?.progress != null) {
      payload['progress'] = tracking?.progress;
    }
    if (clearScore) {
      payload['score'] = null;
    } else if (score != null) {
      payload['score'] = score;
    } else if (tracking?.score != null) {
      payload['score'] = tracking!.score;
    }
    if (writeCompletedAt) {
      payload['completedAt'] = completedAtUtc?.toUtc().toIso8601String();
    }
    if (writeStartedAt) {
      payload['startedAt'] = startedAtUtc?.toUtc().toIso8601String();
    }
    if (writeDroppedAt) {
      payload['droppedAt'] = droppedAtUtc?.toUtc().toIso8601String();
    }
    if (writeCollectedAt) {
      payload['collectedAt'] = collectedAtUtc?.toUtc().toIso8601String();
    }

    await _client.putJson(
      '/backend/tracking',
      data: payload,
    );
  }
}
