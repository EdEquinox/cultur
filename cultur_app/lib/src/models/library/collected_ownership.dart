import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

/// Result of the ownership bottom sheet (format + optional purchase price).
class CollectedOwnershipPick {
  const CollectedOwnershipPick({
    required this.variant,
    this.price,
  });

  final CollectedOwnershipVariant variant;
  final String? price;
}

/// How a collected title is owned (physical/digital × official/unofficial copy).
enum CollectedOwnershipVariant {
  digitalLegal,
  digitalPirate,
  physicalLegal,
  physicalPirate,
}

const _ownedStorageKeys = <CollectedOwnershipVariant, String>{
  CollectedOwnershipVariant.digitalLegal: 'digital_legal',
  CollectedOwnershipVariant.digitalPirate: 'digital_pirate',
  CollectedOwnershipVariant.physicalLegal: 'physical_legal',
  CollectedOwnershipVariant.physicalPirate: 'physical_pirate',
};

extension CollectedOwnershipVariantX on CollectedOwnershipVariant {
  String get storageKey => _ownedStorageKeys[this]!;

  IconData get icon => switch (this) {
        CollectedOwnershipVariant.digitalLegal => Icons.cloud_outlined,
        CollectedOwnershipVariant.digitalPirate => Icons.sailing_outlined,
        CollectedOwnershipVariant.physicalLegal => Icons.album_outlined,
        CollectedOwnershipVariant.physicalPirate => Icons.sailing_outlined,
      };

  String get sheetLabel => switch (this) {
        CollectedOwnershipVariant.digitalLegal => 'Digital',
        CollectedOwnershipVariant.digitalPirate => 'Digital · unofficial',
        CollectedOwnershipVariant.physicalLegal => 'Physical',
        CollectedOwnershipVariant.physicalPirate => 'Physical · unofficial',
      };
  String get iconLabel => switch (this) {
        CollectedOwnershipVariant.digitalLegal => 'Digital',
        CollectedOwnershipVariant.digitalPirate => 'Digital',
        CollectedOwnershipVariant.physicalLegal => 'Physical',
        CollectedOwnershipVariant.physicalPirate => 'Physical',
      };

  bool get isDigital => switch (this) {
        CollectedOwnershipVariant.digitalLegal ||
        CollectedOwnershipVariant.digitalPirate =>
          true,
        CollectedOwnershipVariant.physicalLegal ||
        CollectedOwnershipVariant.physicalPirate =>
          false,
      };

  bool get isPirate => switch (this) {
        CollectedOwnershipVariant.digitalPirate ||
        CollectedOwnershipVariant.physicalPirate =>
          true,
        CollectedOwnershipVariant.digitalLegal ||
        CollectedOwnershipVariant.physicalLegal =>
          false,
      };
}

CollectedOwnershipVariant? collectedOwnershipFromStorageKey(String raw) {
  final key = raw.trim().toLowerCase();
  for (final entry in _ownedStorageKeys.entries) {
    if (entry.value == key) {
      return entry.key;
    }
  }
  return null;
}

CollectedOwnershipVariant? trackingCollectedOwnership(String? notes) {
  final key = trackingCollectedOwnershipKey(notes);
  if (key == null) {
    return null;
  }
  return collectedOwnershipFromStorageKey(key);
}

/// Resolves ownership for a collected row: tracking notes first, then catalog metadata.
CollectedOwnershipVariant? resolveCollectedOwnership({
  TrackingItem? tracking,
  required CatalogItem media,
}) {
  final fromNotes = trackingCollectedOwnership(tracking?.notes);
  if (fromNotes != null) {
    return fromNotes;
  }
  return switch (inferCollectedOwnershipKind(media)) {
    CollectedOwnershipKind.digital => CollectedOwnershipVariant.digitalLegal,
    CollectedOwnershipKind.physical => CollectedOwnershipVariant.physicalLegal,
    CollectedOwnershipKind.unknown => null,
  };
}
