part of 'person_detail_page.dart';

class _PersonProfileHeader extends StatelessWidget {
  const _PersonProfileHeader({
    required this.person,
    required this.watchedCount,
    required this.isLoggedIn,
    required this.isFavorite,
    required this.onWatchedTap,
    required this.onFavoriteTap,
    this.watchedLabel = 'Watched',
    this.useFollowButton = false,
    this.isFollowing = false,
  });

  final PersonCatalogDetail person;
  final int watchedCount;
  final bool isLoggedIn;
  final bool isFavorite;
  final VoidCallback? onWatchedTap;
  final VoidCallback onFavoriteTap;
  final String watchedLabel;
  final bool useFollowButton;
  final bool isFollowing;

  static const double _portraitSize = 108;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.culturTokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: tokens.borderRadiusTight,
          child: SizedBox(
            width: _portraitSize,
            height: _portraitSize,
            child: person.imageUrl == null || person.imageUrl!.isEmpty
                ? ColoredBox(
                    color: scheme.surfaceContainerHigh,
                    child: const Icon(Icons.person_outline, size: 40),
                  )
                : Image.network(
                    person.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return ColoredBox(
                        color: scheme.surfaceContainerHigh,
                        child: const Icon(Icons.person_outline, size: 40),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                person.name,
                style: CulturCatalogTypography.profileTitle(theme),
              ),
              if (person.knownForDepartment != null &&
                  person.knownForDepartment!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  person.knownForDepartment!,
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
                          watchedLabel == 'Read'
                              ? Icons.menu_book_outlined
                              : watchedLabel == 'Listened'
                              ? Icons.album_outlined
                              : Icons.visibility_outlined,
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
                          watchedLabel.toLowerCase(),
                          style: CulturCatalogTypography.actionLabel(theme, scheme),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onFavoriteTap,
                    icon: Icon(
                      useFollowButton
                          ? (isFollowing
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_none_outlined)
                          : (isFavorite ? Icons.favorite : Icons.favorite_border),
                      size: 18,
                    ),
                    label: Text(useFollowButton
                        ? (isFollowing ? 'Following' : 'Follow')
                        : 'Favorite'),
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
}

class _PersonDetailsTab extends StatelessWidget {
  const _PersonDetailsTab({
    required this.person,
    required this.bioExpanded,
    required this.onToggleBio,
    required this.onOpenLink,
    required this.onOpenFilmographyEntry,
    this.popularSectionTitle = 'Popular titles',
  });

  final PersonCatalogDetail person;
  final bool bioExpanded;
  final VoidCallback onToggleBio;
  final ValueChanged<String> onOpenLink;
  final ValueChanged<PersonFilmographyEntry> onOpenFilmographyEntry;
  final String popularSectionTitle;

  @override
  Widget build(BuildContext context) {
    final bio = person.biography?.trim() ?? '';
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
        if (person.popularFilmography.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            popularSectionTitle,
            style: CulturCatalogTypography.sectionHeading(theme),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: GameHomePosterCard.cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: person.popularFilmography.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = person.popularFilmography[index];
                return GameHomePosterCard(
                  catalogItem: entry.media,
                  onTap: () => onOpenFilmographyEntry(entry),
                );
              },
            ),
          ),
        ],
        if (person.links.isNotEmpty) ...[
          const SizedBox(height: 8),
          MediaDetailLinksSection(
            links: person.links,
            onOpenLink: onOpenLink,
          ),
        ],
        _PersonMoreDetailsSection(person: person),
      ],
    );
  }
}

class _PersonMoreDetailsSection extends StatelessWidget {
  const _PersonMoreDetailsSection({required this.person});

  final PersonCatalogDetail person;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[];
    final gender = person.gender?.trim();
    if (gender != null && gender.isNotEmpty) {
      rows.add((label: 'Gender', value: gender));
    }
    final place = person.placeOfBirth?.trim();
    if (place != null && place.isNotEmpty) {
      rows.add((label: 'Place of birth', value: place));
    }
    final birthday = person.birthday?.trim();
    if (birthday != null && birthday.isNotEmpty) {
      final isAuthor = person.knownForDepartment?.trim().toLowerCase() == 'author';
      rows.add((
        label: isAuthor ? 'Life dates' : 'Birthday',
        value: birthday,
      ));
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.culturTokens;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Text(
            'More details',
            style: CulturCatalogTypography.mutedSectionTitle(theme, scheme),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: tokens.shelfRowBackgroundElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 20),
                  _PersonDetailFactRow(label: rows[i].label, value: rows[i].value),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonDetailFactRow extends StatelessWidget {
  const _PersonDetailFactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: CulturCatalogTypography.factLabel(theme, scheme),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: CulturCatalogTypography.factValue(theme),
        ),
      ],
    );
  }
}
