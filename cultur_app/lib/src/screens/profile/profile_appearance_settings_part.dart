part of 'profile_page.dart';

class _ProfileAppearanceSettingsCard extends StatelessWidget {
  const _ProfileAppearanceSettingsCard({
    required this.theme,
    required this.selected,
    required this.onAccentSelected,
  });

  final ThemeData theme;
  final CulturAccentId selected;
  final ValueChanged<CulturAccentId> onAccentSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: CulturCatalogTypography.sectionHeading(theme)),
            const SizedBox(height: 8),
            Text(
              'Accent colour used for buttons, highlights, and navigation.',
              style: CulturCatalogTypography.bodyText(theme, scheme),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final option in CulturAccentOption.all)
                  _AccentColourSwatch(
                    option: option,
                    selected: selected == option.id,
                    onTap: () => onAccentSelected(option.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccentColourSwatch extends StatelessWidget {
  const _AccentColourSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CulturAccentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onAccent = ColorScheme.fromSeed(
      seedColor: option.seed,
      brightness: Brightness.dark,
    ).onPrimary;

    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: option.seed,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.onSurface : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: option.seed.withValues(alpha: 0.45),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 20, color: onAccent)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                option.label,
                style: CulturCatalogTypography.listMeta(
                  theme,
                  scheme,
                  fontWeight: selected ? FontWeight.w600 : null,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
