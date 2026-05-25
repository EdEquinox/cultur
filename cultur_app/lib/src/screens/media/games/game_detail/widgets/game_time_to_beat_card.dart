import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/games/game_time_to_beat.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class GameTimeToBeatCard extends StatelessWidget {
  const GameTimeToBeatCard({super.key, required this.timeToBeat});

  final GameTimeToBeat timeToBeat;

  @override
  Widget build(BuildContext context) {
    if (!timeToBeat.hasAny) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Time to Beat', style: CulturCatalogTypography.sectionHeading(theme)),
            const SizedBox(height: 12),
            if (timeToBeat.main?.trim().isNotEmpty ?? false)
              _TimeToBeatRow(
                icon: Icons.timelapse_outlined,
                label: 'Main story',
                value: timeToBeat.main!,
                scheme: scheme,
                theme: theme,
              ),
            if (timeToBeat.extras?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              _TimeToBeatRow(
                icon: Icons.hourglass_bottom_outlined,
                label: 'Main story + extras',
                value: timeToBeat.extras!,
                scheme: scheme,
                theme: theme,
              ),
            ],
            if (timeToBeat.completion?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              _TimeToBeatRow(
                icon: Icons.emoji_events_outlined,
                label: '100% completion',
                value: timeToBeat.completion!,
                scheme: scheme,
                theme: theme,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeToBeatRow extends StatelessWidget {
  const _TimeToBeatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.scheme,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: CulturCatalogTypography.listMeta(theme, scheme),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            value,
            style: CulturCatalogTypography.gridTitle(theme),
          ),
        ),
      ],
    );
  }
}
