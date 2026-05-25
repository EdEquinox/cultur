import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';

/// Collected title currently lent out, for category home grids.
class CollectedLentShelfItem {
  const CollectedLentShelfItem({
    required this.tracking,
    required this.lent,
  });

  final TrackingItem tracking;
  final CollectedLentInfo lent;
}

final collectedLentForScopeProvider = FutureProvider.autoDispose
    .family<List<CollectedLentShelfItem>, LibraryMediaScope>((ref, scope) async {
  final data = await ref.watch(libraryTrackingForScopeProvider(scope).future);
  final rows = <CollectedLentShelfItem>[];
  for (final item in data.items) {
    if (!hasTrackingFlag(item, kCollectedTrackingFlag)) {
      continue;
    }
    final lent = trackingCollectedLent(item.notes);
    if (lent == null) {
      continue;
    }
    rows.add(CollectedLentShelfItem(tracking: item, lent: lent));
  }
  rows.sort((a, b) => b.lent.lentAt.compareTo(a.lent.lentAt));
  return rows;
});
