part of 'company_detail_page.dart';

class _CompanyProfileHeader extends StatelessWidget {
  const _CompanyProfileHeader({
    required this.company,
    required this.displayName,
    required this.watchedCount,
    required this.isLoggedIn,
    required this.isFavorite,
    required this.onWatchedTap,
    required this.onFavoriteTap,
  });

  final GameCompanyCatalogDetail company;
  final String displayName;
  final int watchedCount;
  final bool isLoggedIn;
  final bool isFavorite;
  final VoidCallback? onWatchedTap;
  final VoidCallback onFavoriteTap;

  static const double _logoSize = 108;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.culturTokens;
    final logoUrl = igdbDisplayImageUrl(company.imageUrl, source: 'igdb');
    final role = company.primaryRole?.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: tokens.borderRadiusTight,
          child: SizedBox(
            width: _logoSize,
            height: _logoSize,
            child: logoUrl != null && logoUrl.isNotEmpty
                ? Image.network(
                    logoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _logoPlaceholder(scheme);
                    },
                  )
                : _logoPlaceholder(scheme),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: CulturCatalogTypography.profileTitle(theme),
              ),
              if (role != null && role.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  role,
                  style: CulturCatalogTypography.profileSubtitle(theme, scheme),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: onWatchedTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary.withValues(alpha: 0.42),
                      foregroundColor: scheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: tokens.borderRadiusTight,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.visibility_outlined,
                          size: 18,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isLoggedIn ? '$watchedCount' : '—',
                          style: CulturCatalogTypography.actionCount(theme),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'played',
                          style: CulturCatalogTypography.actionLabel(theme, scheme),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onFavoriteTap,
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                    ),
                    label: const Text('Favorite'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      backgroundColor: scheme.surfaceContainerHigh,
                      side: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: tokens.borderRadiusTight,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logoPlaceholder(ColorScheme scheme) {
    return ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Icon(Icons.business_outlined, size: 40, color: scheme.onSurfaceVariant),
    );
  }
}
