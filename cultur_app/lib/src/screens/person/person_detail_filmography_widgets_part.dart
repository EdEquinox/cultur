part of 'person_detail_page.dart';

class _MenuVal<T> {
  const _MenuVal(this.value, this.label);
  final T value;
  final String label;
}

Widget _chipMenu<T>(
  BuildContext context, {
  required String label,
  required String subtitle,
  required List<_MenuVal<T>> items,
  required void Function(T?) onPick,
  bool enabled = true,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  return PopupMenuButton<T>(
    enabled: enabled,
    tooltip: label,
    onSelected: onPick,
    itemBuilder: (context) => [
      for (final it in items)
        PopupMenuItem<T>(
          value: it.value,
          child: Text(it.label),
        ),
    ],
    child: InputChip(
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: CulturCatalogTypography.gridTitle(theme)),
          Text(
            subtitle,
            style: CulturCatalogTypography.gridSubtitle(theme, scheme).copyWith(
              color: scheme.primary,
            ),
          ),
        ],
      ),
      avatar: Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurfaceVariant),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
  );
}

/// One catalog row per title; [credits] holds every role on that title.
class _PersonFilmographyGroup {
  const _PersonFilmographyGroup({
    required this.media,
    required this.mediaType,
    required this.credits,
  });

  final CatalogItem media;
  final String mediaType;
  final List<PersonFilmographyEntry> credits;

  PersonFilmographyEntry get primaryCredit => credits.first;
}

List<_PersonFilmographyGroup> _groupPersonFilmographyEntries(
  List<PersonFilmographyEntry> entries,
) {
  final byMediaId = <String, List<PersonFilmographyEntry>>{};
  final order = <String>[];

  for (final entry in entries) {
    final id = entry.media.id;
    if (!byMediaId.containsKey(id)) {
      order.add(id);
      byMediaId[id] = [];
    }
    byMediaId[id]!.add(entry);
  }

  return [
    for (final id in order)
      _PersonFilmographyGroup(
        media: byMediaId[id]!.first.media,
        mediaType: byMediaId[id]!.first.mediaType,
        credits: byMediaId[id]!,
      ),
  ];
}

List<String> _personFilmographyCreditMetaParts(_PersonFilmographyGroup group) {
  if (group.mediaType == 'book' || group.mediaType == 'music') {
    return catalogRowMetaPartsForCatalogList(
      group.media,
      mediaTypeOverride: group.mediaType,
    );
  }

  final seen = <String>{};
  final labels = <String>[];

  void add(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty || !seen.add(text)) {
      return;
    }
    labels.add(text);
  }

  for (final credit in group.credits) {
    if (credit.creditKind == 'cast') {
      add(credit.role?.isNotEmpty == true ? credit.role : 'Actor');
      continue;
    }
    final job = credit.role?.trim();
    final dept = credit.department?.trim();
    if (job != null && job.isNotEmpty) {
      if (dept != null &&
          dept.isNotEmpty &&
          job.toLowerCase() != dept.toLowerCase() &&
          !job.toLowerCase().contains(dept.toLowerCase())) {
        add('$dept · $job');
      } else {
        add(job);
      }
    } else if (dept != null && dept.isNotEmpty) {
      add(dept);
    } else {
      add('Crew');
    }
  }

  final episodes = group.credits
      .map((c) => c.episodeCount)
      .whereType<int>()
      .fold<int>(0, (a, b) => a > b ? a : b);
  if (group.mediaType == 'tv' && episodes > 0) {
    add('$episodes episodes');
  }

  return labels;
}

extension _IterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
