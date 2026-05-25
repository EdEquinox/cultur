import 'package:flutter/material.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/library/collected_ownership.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/collections/widgets/collected_ownership_sheet.dart';

/// Adds or removes collected tracking. When adding, prompts for format and price.
/// Returns `null` if the user cancelled the sheet.
Future<String?> runCollectedToggle({
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

  final pick = await showCollectedOwnershipSheet(
    context,
    current: resolveCollectedOwnership(tracking: tracking, media: media),
    currentPrice: trackingCollectedPrice(tracking?.notes),
  );
  if (!context.mounted || pick == null) {
    return null;
  }

  return controller.saveCollectedOwnership(
    username: username,
    media: media,
    tracking: tracking,
    variant: pick.variant,
    price: pick.price,
  );
}
