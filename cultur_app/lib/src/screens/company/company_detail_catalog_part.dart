part of 'company_detail_page.dart';

class _CompanyCatalogTab extends StatelessWidget {
  const _CompanyCatalogTab({
    required this.items,
    required this.digest,
    required this.onOpenItem,
  });

  final List<GameCompanyCatalogItem> items;
  final UserGameTrackingDigest digest;
  final ValueChanged<GameCompanyCatalogItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogItems = _dedupeCompanyCatalogItems(items);

    if (catalogItems.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No games in this catalog yet.',
          style: CulturCatalogTypography.emptyState(
            theme,
            theme.colorScheme,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < catalogItems.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          CulturCatalogListRow(
            item: catalogItems[i].media,
            metaParts: _companyCatalogMetaParts(catalogItems[i]),
            score: digest.byMediaId[catalogItems[i].media.id]?.score,
            onTap: () => onOpenItem(catalogItems[i]),
          ),
        ],
      ],
    );
  }
}

List<GameCompanyCatalogItem> _dedupeCompanyCatalogItems(
  List<GameCompanyCatalogItem> items,
) {
  final merged = <String, GameCompanyCatalogItem>{};
  final order = <String>[];

  for (final item in items) {
    final key = _companyCatalogDedupeKey(item.media);
    final existing = merged[key];
    if (existing == null) {
      order.add(key);
      merged[key] = item;
      continue;
    }
    final roles = <String>{
      ...existing.roles,
      ...item.roles,
    }.toList()
      ..sort((a, b) {
        final cmp = _companyRoleSortRank(a).compareTo(_companyRoleSortRank(b));
        return cmp != 0 ? cmp : a.compareTo(b);
      });
    merged[key] = GameCompanyCatalogItem(
      media: _preferredCompanyCatalogMedia(existing.media, item.media),
      roles: roles,
    );
  }

  return [for (final key in order) merged[key]!];
}

String _companyCatalogDedupeKey(CatalogItem media) {
  final slug = media.metadata['slug']?.toString().trim();
  if (slug != null && slug.isNotEmpty) {
    return 'slug:${slug.toLowerCase()}';
  }
  final title = media.title.trim().toLowerCase();
  if (title.isEmpty) {
    return 'id:${media.externalId}';
  }
  final year = media.metadata['firstReleaseDate']?.toString().trim() ?? '';
  if (year.isNotEmpty) {
    return 'title:$title|y:$year';
  }
  return 'title:$title';
}

CatalogItem _preferredCompanyCatalogMedia(CatalogItem left, CatalogItem right) {
  double ratingOf(CatalogItem item) {
    final raw = item.metadata['igdbRating'];
    return switch (raw) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };
  }

  int releaseOf(CatalogItem item) {
    final raw = item.metadata['firstReleaseDateUnix'];
    return switch (raw) {
      int v => v,
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };
  }

  final leftRating = ratingOf(left);
  final rightRating = ratingOf(right);
  if (rightRating > leftRating) {
    return right;
  }
  if (leftRating > rightRating) {
    return left;
  }
  if (releaseOf(right) > releaseOf(left)) {
    return right;
  }
  return left;
}

int _companyRoleSortRank(String role) => switch (role) {
      'Developer' => 0,
      'Publisher' => 1,
      _ => 2,
    };

List<String> _companyCatalogMetaParts(GameCompanyCatalogItem item) {
  final seen = <String>{};
  final parts = <String>[];
  for (final role in item.roles) {
    final text = role.trim();
    if (text.isEmpty || !seen.add(text)) {
      continue;
    }
    parts.add(text);
  }
  if (parts.isEmpty) {
    parts.add('Game');
  }
  return parts;
}
