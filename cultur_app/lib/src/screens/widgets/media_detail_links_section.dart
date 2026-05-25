import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_link.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Centered external links row for movie, TV, and game detail pages.
class MediaDetailLinksSection extends StatelessWidget {
  const MediaDetailLinksSection({
    super.key,
    required this.links,
    required this.onOpenLink,
    this.onRefreshMetadata,
    this.isRefreshingMetadata = false,
  });

  final List<CatalogLink> links;
  final ValueChanged<String> onOpenLink;
  final VoidCallback? onRefreshMetadata;
  final bool isRefreshingMetadata;

  @override
  Widget build(BuildContext context) {
    final validLinks = links
        .where((link) => link.label.isNotEmpty && link.url.isNotEmpty)
        .toList();
    if (validLinks.isEmpty && onRefreshMetadata == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(
            'Links',
            style: CulturCatalogTypography.mutedSectionTitle(theme, scheme),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final link in validLinks)
                OutlinedButton.icon(
                  onPressed: () => onOpenLink(link.url),
                  icon: Icon(Icons.open_in_new, size: 16, color: muted),
                  label: Text(
                    link.label,
                    style: CulturCatalogTypography.listMeta(theme, scheme),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: muted,
                    side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              if (onRefreshMetadata != null)
                OutlinedButton.icon(
                  onPressed: isRefreshingMetadata ? null : onRefreshMetadata,
                  icon: isRefreshingMetadata
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: muted,
                          ),
                        )
                      : Icon(Icons.cloud_sync_outlined, size: 16, color: muted),
                  label: Text(
                    isRefreshingMetadata ? 'Fetching…' : 'Fetch more info',
                    style: CulturCatalogTypography.listMeta(theme, scheme),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: muted,
                    side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
