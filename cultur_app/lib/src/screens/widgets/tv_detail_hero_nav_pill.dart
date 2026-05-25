import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Pill on TV season / episode heroes: always navigates to [targetLocation] (series or season).
class TvDetailHeroNavPill extends StatelessWidget {
  const TvDetailHeroNavPill({
    super.key,
    required this.label,
    required this.targetLocation,
  });

  final String label;
  /// Full path, e.g. `/tv/:id` or `/tv/:id/seasons/:n`.
  final String targetLocation;

  void _onTap(BuildContext context) {
    GoRouter.of(context).go(targetLocation);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = context.culturTokens.radiusTight;
    final maxW = MediaQuery.sizeOf(context).width * 0.52;
    return Material(
      color: scheme.scrim.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onTap(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back_ios_new,
                size: 13,
                color: scheme.onSurface.withValues(alpha: 0.95),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CulturCatalogTypography.listTitle(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
