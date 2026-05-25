import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/library/collected_ownership.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/screens/collections/widgets/collected_ownership_sheet.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_grid_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Poster card for the Collected library tab — uses [CulturCatalogGridCard] + ownership pill.
class CollectedCatalogPosterCard extends StatelessWidget {
  const CollectedCatalogPosterCard({
    required this.media,
    required this.tracking,
    super.key,
    this.ownership,
    this.onTap,
    this.onLongPress,
    this.onRemove,
    this.onOwnershipChanged,
    this.removing = false,
    this.ownershipBusy = false,
  });

  static const double posterAspectRatio = CulturCatalogGridCard.posterAspectRatio;
  static const double gridChildAspectRatio = CulturCatalogGridCard.gridChildAspectRatio;

  final CatalogItem media;
  final TrackingItem tracking;
  final CollectedOwnershipVariant? ownership;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemove;
  final Future<void> Function(CollectedOwnershipPick pick)? onOwnershipChanged;
  final bool removing;
  final bool ownershipBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resolved = ownership ?? resolveCollectedOwnership(tracking: tracking, media: media);
    final pillColors = _pillColors(scheme, resolved);

    return CulturCatalogGridCard(
      item: media,
      onTap: onTap,
      onLongPress: onLongPress,
      imageOverlay: Positioned(
        top: 4,
        right: 4,
        child: _OwnershipCornerPill(
          variant: resolved,
          background: pillColors.$1,
          foreground: pillColors.$2,
          busy: ownershipBusy,
          onTap: onOwnershipChanged == null
              ? null
              : () async {
                  final picked = await showCollectedOwnershipSheet(
                    context,
                    current: resolved,
                    currentPrice: trackingCollectedPrice(tracking.notes),
                  );
                  if (picked == null) {
                    return;
                  }
                  final sameVariant = picked.variant == resolved;
                  final samePrice =
                      (picked.price ?? '') == (trackingCollectedPrice(tracking.notes) ?? '');
                  if (sameVariant && samePrice) {
                    return;
                  }
                  await onOwnershipChanged!(picked);
                },
        ),
      ),
    );
  }

  (Color, Color) _pillColors(ColorScheme scheme, CollectedOwnershipVariant? variant) {
    if (variant == null) {
      return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    }
    if (variant.isDigital) {
      return variant.isPirate
          ? (scheme.errorContainer, scheme.onErrorContainer)
          : (scheme.primaryContainer, scheme.onPrimaryContainer);
    }
    return variant.isPirate
        ? (scheme.errorContainer.withValues(alpha: 0.92), scheme.onErrorContainer)
        : (scheme.tertiaryContainer, scheme.onTertiaryContainer);
  }
}

class _OwnershipCornerPill extends StatelessWidget {
  const _OwnershipCornerPill({
    required this.background,
    required this.foreground,
    this.variant,
    this.onTap,
    this.busy = false,
  });

  final CollectedOwnershipVariant? variant;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: busy
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              : Row(
                  children: [
                    Icon(
                      variant?.icon ?? Icons.help_outline,
                      size: 12,
                      color: foreground,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      variant?.iconLabel ?? '',
                      style: CulturCatalogTypography.gridSubtitle(theme, theme.colorScheme).copyWith(
                        fontSize: 10,
                        height: 1,
                        letterSpacing: -0.10,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
