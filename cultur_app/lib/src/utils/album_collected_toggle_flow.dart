import 'package:flutter/material.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/media/albums/album_detail/widgets/album_release_version_sheet.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/collected_toggle_flow.dart';

/// Owned toggle for album release groups — pick a release version, then mark owned.
Future<String?> runAlbumCollectedToggle({
  required BuildContext context,
  required TrackingMutationController controller,
  required String username,
  required CatalogItem media,
  TrackingItem? tracking,
}) async {
  if (hasTrackingFlag(tracking, kCollectedTrackingFlag)) {
    return controller.toggleCollected(
      username: username,
      media: media,
      tracking: tracking,
    );
  }

  if (!catalogItemIsMusicReleaseGroup(media)) {
    return runCollectedToggle(
      context: context,
      controller: controller,
      username: username,
      media: media,
      tracking: tracking,
    );
  }

  final pick = await showAlbumReleaseVersionSheet(
    context,
    mediaId: media.id,
    initialPrice: trackingCollectedPrice(tracking?.notes),
  );
  if (!context.mounted || pick == null) {
    return null;
  }

  return controller.saveAlbumOwnedRelease(
    username: username,
    media: media,
    tracking: tracking,
    mbReleaseId: pick.version.releaseMbid,
    price: pick.price,
  );
}
