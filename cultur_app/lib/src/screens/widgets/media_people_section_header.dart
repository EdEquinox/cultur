import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Section title with optional chevron (Cast / Crew on detail People tab).
class MediaPeopleSectionHeader extends StatelessWidget {
  const MediaPeopleSectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
  });

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: CulturCatalogTypography.sectionHeading(theme),
          ),
        ),
        if (onSeeAll != null)
          IconButton(
            onPressed: onSeeAll,
            tooltip: 'See all',
            icon: Icon(Icons.chevron_right_rounded, color: muted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
      ],
    );
  }
}
