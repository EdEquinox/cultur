part of 'company_detail_page.dart';

class _CompanyDetailsTab extends StatelessWidget {
  const _CompanyDetailsTab({
    required this.company,
    required this.displayName,
    required this.bioExpanded,
    required this.onToggleBio,
    required this.onOpenLink,
    required this.onOpenCatalogItem,
  });

  final GameCompanyCatalogDetail company;
  final String displayName;
  final bool bioExpanded;
  final VoidCallback onToggleBio;
  final ValueChanged<String> onOpenLink;
  final ValueChanged<GameCompanyCatalogItem> onOpenCatalogItem;

  @override
  Widget build(BuildContext context) {
    final bio = company.description?.trim() ?? '';
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bio.isNotEmpty) ...[
          Text(
            bio,
            maxLines: bioExpanded ? null : 5,
            overflow: bioExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: CulturCatalogTypography.bodyText(theme, scheme),
          ),
          if (bio.length > 220)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onToggleBio,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary.withValues(alpha: 0.75),
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  bioExpanded ? 'Show less' : 'View more',
                  style: CulturCatalogTypography.linkAction(theme, scheme),
                ),
              ),
            ),
        ],
        if (company.popularCatalog.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Popular titles',
            style: CulturCatalogTypography.sectionHeading(theme),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: GameHomePosterCard.cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: company.popularCatalog.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = company.popularCatalog[index];
                return GameHomePosterCard(
                  catalogItem: entry.media,
                  onTap: () => onOpenCatalogItem(entry),
                );
              },
            ),
          ),
        ],
        if (company.links.isNotEmpty) ...[
          const SizedBox(height: 8),
          MediaDetailLinksSection(
            links: company.links,
            onOpenLink: onOpenLink,
          ),
        ],
      ],
    );
  }
}
