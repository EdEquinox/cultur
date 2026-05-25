import 'package:flutter/material.dart';

class GamePendingCatalogBanner extends StatelessWidget {
  const GamePendingCatalogBanner({
    required this.onSearchCatalog,
    this.importSource,
    this.catalogProviderLabel,
    super.key,
  });

  final VoidCallback onSearchCatalog;
  final String? importSource;
  final String? catalogProviderLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sourceLabel = switch (importSource) {
      'stash' => 'Stash import',
      'bookmory' => 'Bookmory import',
      'ava' => 'AVA backup import',
      'manual' => 'Added manually',
      _ => 'Import',
    };

    final catalogHint = catalogProviderLabel ??
        switch (importSource) {
          'bookmory' => 'Hardcover',
          'ava' => 'TMDB',
          'manual' => 'a catalog',
          _ => 'IGDB',
        };

    return Material(
      color: scheme.tertiaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link_off_outlined, color: scheme.onTertiaryContainer, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pending catalog match',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$sourceLabel could not match this title in $catalogHint automatically. '
              'Your tracking is saved — link the correct entry to fill in details.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer.withValues(alpha: 0.9),
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onSearchCatalog,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Search catalog'),
            ),
          ],
        ),
      ),
    );
  }
}
