import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class GameCompanyChip extends StatelessWidget {
  const GameCompanyChip({
    super.key,
    required this.name,
    required this.icon,
    this.onTap,
    this.expanded = false,
  });

  final String name;
  final IconData icon;
  final VoidCallback? onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              if (expanded)
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CulturCatalogTypography.gridTitle(theme),
                  ),
                )
              else
                Flexible(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CulturCatalogTypography.gridTitle(theme),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
