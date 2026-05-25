part of 'person_detail_page.dart';

enum _MediaKindFilter { all, movies, shows }

enum _TriFilter { any, yes, no }

class PersonFilmographyPanel extends ConsumerStatefulWidget {
  const PersonFilmographyPanel({
    required this.entries,
    this.booksOnly = false,
    this.musicOnly = false,
    super.key,
  });

  final List<PersonFilmographyEntry> entries;
  final bool booksOnly;
  final bool musicOnly;

  @override
  ConsumerState<PersonFilmographyPanel> createState() => _PersonFilmographyPanelState();
}

class _PersonFilmographyPanelState extends ConsumerState<PersonFilmographyPanel> {
  late final TextEditingController _bibliographySearchController;
  String _bibliographySearchQuery = '';

  _MediaKindFilter _mediaKind = _MediaKindFilter.all;
  String? _roleKey;
  String? _character;
  _TriFilter _watched = _TriFilter.any;
  _TriFilter _watchlist = _TriFilter.any;
  double? _minVote;
  String? _collectionListId;
  String? _genreKey;
  int? _year;

  @override
  void initState() {
    super.initState();
    _bibliographySearchController = TextEditingController();
  }

  @override
  void dispose() {
    _bibliographySearchController.dispose();
    super.dispose();
  }

  int? _releaseYear(PersonFilmographyEntry e) {
    if (e.mediaType == 'book') {
      final year = e.media.metadata['firstPublishYear'];
      if (year is int && year > 0) {
        return year;
      }
      final parsed = int.tryParse(year?.toString() ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    if (e.mediaType == 'music') {
      final year = e.media.metadata['year'];
      if (year is int && year > 0) {
        return year;
      }
      final parsed = int.tryParse(year?.toString() ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    final d = e.media.metadata['releaseDate']?.toString();
    if (d == null || d.length < 4) {
      return null;
    }
    return int.tryParse(d.substring(0, 4));
  }

  double? _entryVote(PersonFilmographyEntry e) {
    if (e.voteAverage != null) {
      return e.voteAverage;
    }
    final raw = e.media.metadata['tmdbRating']?.toString();
    return double.tryParse(raw ?? '');
  }

  bool _inList(CustomMovieList list, String mediaId) {
    return list.items.any((m) => m.id == mediaId);
  }

  List<PersonFilmographyEntry> _applyFilters(
    List<PersonFilmographyEntry> all,
    UserMovieTrackingDigest digest,
    CustomMovieListsData? listsData,
  ) {
    if (widget.booksOnly || widget.musicOnly) {
      Iterable<PersonFilmographyEntry> q = all;
      final query = _bibliographySearchQuery.trim();
      if (query.isNotEmpty) {
        q = q.where((e) => catalogItemMatchesLibrarySearch(e.media, query));
      }
      final out = q.toList();
      out.sort((a, b) {
        final ya = _releaseYear(a) ?? 0;
        final yb = _releaseYear(b) ?? 0;
        if (ya != yb) {
          return yb.compareTo(ya);
        }
        return a.media.title.toLowerCase().compareTo(b.media.title.toLowerCase());
      });
      return out;
    }

    Iterable<PersonFilmographyEntry> q = all;
    switch (_mediaKind) {
      case _MediaKindFilter.movies:
        q = q.where((e) => e.mediaType == 'movie');
      case _MediaKindFilter.shows:
        q = q.where((e) => e.mediaType == 'tv');
      case _MediaKindFilter.all:
        break;
    }

    if (_roleKey == 'cast') {
      q = q.where((e) => e.creditKind == 'cast');
    } else if (_roleKey != null && _roleKey!.startsWith('dept:')) {
      final dept = _roleKey!.substring(5);
      q = q.where((e) => e.creditKind == 'crew' && (e.department ?? '') == dept);
    }

    if (_character != null && _character!.trim().isNotEmpty) {
      final needle = _character!.trim().toLowerCase();
      q = q.where(
        (e) =>
            e.creditKind == 'cast' &&
            (e.role ?? '').toLowerCase().contains(needle),
      );
    }

    switch (_watched) {
      case _TriFilter.yes:
        q = q.where((e) => digest.watchedIds.contains(e.media.id));
      case _TriFilter.no:
        q = q.where((e) => !digest.watchedIds.contains(e.media.id));
      case _TriFilter.any:
        break;
    }

    switch (_watchlist) {
      case _TriFilter.yes:
        q = q.where((e) => digest.watchlistIds.contains(e.media.id));
      case _TriFilter.no:
        q = q.where((e) => !digest.watchlistIds.contains(e.media.id));
      case _TriFilter.any:
        break;
    }

    if (_minVote != null) {
      q = q.where((e) {
        final v = _entryVote(e);
        return v != null && v >= _minVote!;
      });
    }

    if (_collectionListId != null && listsData != null) {
      final list = listsData.lists.where((l) => l.id == _collectionListId).firstOrNull;
      if (list != null) {
        q = q.where((e) => _inList(list, e.media.id));
      }
    }

    if (_genreKey != null) {
      final parts = _genreKey!.split(':');
      if (parts.length == 2) {
        final mt = parts[0];
        final gid = int.tryParse(parts[1]);
        if (gid != null) {
          q = q.where(
            (e) => e.mediaType == mt && e.genreIds.contains(gid),
          );
        }
      }
    }

    if (_year != null) {
      q = q.where((e) => _releaseYear(e) == _year);
    }

    final out = q.toList();
    out.sort((a, b) {
      final ya = _releaseYear(a) ?? 0;
      final yb = _releaseYear(b) ?? 0;
      if (ya != yb) {
        return yb.compareTo(ya);
      }
      return a.media.title.toLowerCase().compareTo(b.media.title.toLowerCase());
    });
    return out;
  }

  Future<void> _openGroup(_PersonFilmographyGroup group) async {
    final e = group.primaryCredit;
    if (e.mediaType == 'book') {
      if (!mounted) {
        return;
      }
      context.push('/books/${e.media.id}');
      return;
    }
    if (e.mediaType == 'music') {
      if (!mounted) {
        return;
      }
      context.push('/albums/${e.media.id}');
      return;
    }
    if (e.mediaType == 'movie') {
      if (!mounted) {
        return;
      }
      context.push('/movies/${e.media.id}');
      return;
    }
    final uri = Uri.parse('https://www.themoviedb.org/tv/${e.media.externalId}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final digestAsync = widget.booksOnly || widget.musicOnly
        ? null
        : ref.watch(userMovieTrackingDigestProvider);
    final bookTrackingAsync = widget.booksOnly
        ? ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.book))
        : null;
    final musicTrackingAsync = widget.musicOnly
        ? ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.music))
        : null;
    final listsAsync = widget.booksOnly || widget.musicOnly
        ? null
        : ref.watch(customMovieListsProvider);
    final theme = Theme.of(context);

    final digest = switch (digestAsync) {
      AsyncData(:final value) => value,
      _ => const UserMovieTrackingDigest(
          watchedIds: {},
          watchlistIds: {},
          byMediaId: {},
        ),
    };

    final bookTrackingByMediaId = switch (bookTrackingAsync) {
      AsyncData(:final value) => {
          for (final item in value.items) item.media.id: item,
        },
      _ => const <String, TrackingItem>{},
    };

    final musicTrackingByMediaId = switch (musicTrackingAsync) {
      AsyncData(:final value) => {
          for (final item in value.items) item.media.id: item,
        },
      _ => const <String, TrackingItem>{},
    };

    final listsData = switch (listsAsync) {
      AsyncData(:final value) => value,
      _ => null,
    };

    final filtered = _applyFilters(widget.entries, digest, listsData);

    final departments = <String>{};
    final characters = <String>{};
    final genreChoices = <String, String>{};
    final years = <int>{};
    for (final e in widget.entries) {
      if (e.creditKind == 'crew' && (e.department ?? '').isNotEmpty) {
        departments.add(e.department!);
      }
      if (e.creditKind == 'cast' && (e.role ?? '').trim().isNotEmpty) {
        characters.add(e.role!.trim());
      }
      for (var i = 0; i < e.genreIds.length; i++) {
        final id = e.genreIds[i];
        final name = i < e.genreNames.length ? e.genreNames[i] : 'Genre $id';
        genreChoices['${e.mediaType}:$id'] = name;
      }
      final y = _releaseYear(e);
      if (y != null) {
        years.add(y);
      }
    }
    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    final sortedDepts = departments.toList()..sort();
    final sortedChars = characters.toList()..sort();

    final hasBibliographySearch = widget.booksOnly && _bibliographySearchQuery.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.booksOnly) ...[
          LibraryItemSearchField(
            controller: _bibliographySearchController,
            hintText: 'Search books…',
            registerForPageSearchFab: true,
            onChanged: (value) => setState(() => _bibliographySearchQuery = value),
          ),
          const SizedBox(height: 12),
        ],
        if (!widget.booksOnly)
          SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chipMenu<_MediaKindFilter>(
                context,
                label: 'Type',
                subtitle: switch (_mediaKind) {
                  _MediaKindFilter.all => 'Movies & shows',
                  _MediaKindFilter.movies => 'Movies',
                  _MediaKindFilter.shows => 'Shows',
                },
                items: const [
                  _MenuVal(_MediaKindFilter.all, 'Movies & shows'),
                  _MenuVal(_MediaKindFilter.movies, 'Movies'),
                  _MenuVal(_MediaKindFilter.shows, 'Shows'),
                ],
                onPick: (v) => setState(() => _mediaKind = v ?? _MediaKindFilter.all),
              ),
              const SizedBox(width: 8),
              _chipMenu<String?>(
                context,
                label: 'Role',
                subtitle: _roleKey == null
                    ? 'All'
                    : (_roleKey == 'cast' ? 'Actor' : _roleKey!.substring(5)),
                items: [
                  const _MenuVal<String?>(null, 'All roles'),
                  const _MenuVal<String?>('cast', 'Actor (cast)'),
                  for (final d in sortedDepts) _MenuVal<String?>('dept:$d', d),
                ],
                onPick: (v) => setState(() {
                  _roleKey = v;
                  if (v != 'cast') {
                    _character = null;
                  }
                }),
              ),
              const SizedBox(width: 8),
              _chipMenu<String?>(
                context,
                label: 'Character',
                subtitle: _character ?? 'Any',
                enabled: _roleKey == null || _roleKey == 'cast',
                items: [
                  const _MenuVal<String?>(null, 'Any character'),
                  for (final c in sortedChars) _MenuVal<String?>(c, c),
                ],
                onPick: (v) => setState(() => _character = v),
              ),
              const SizedBox(width: 8),
              _chipMenu<_TriFilter>(
                context,
                label: 'Watched',
                subtitle: switch (_watched) {
                  _TriFilter.any => 'Any',
                  _TriFilter.yes => 'Yes',
                  _TriFilter.no => 'No',
                },
                items: const [
                  _MenuVal(_TriFilter.any, 'Any'),
                  _MenuVal(_TriFilter.yes, 'Watched'),
                  _MenuVal(_TriFilter.no, 'Not watched'),
                ],
                onPick: (v) => setState(() => _watched = v ?? _TriFilter.any),
              ),
              const SizedBox(width: 8),
              _chipMenu<_TriFilter>(
                context,
                label: 'Watchlist',
                subtitle: switch (_watchlist) {
                  _TriFilter.any => 'Any',
                  _TriFilter.yes => 'On list',
                  _TriFilter.no => 'Not on list',
                },
                items: const [
                  _MenuVal(_TriFilter.any, 'Any'),
                  _MenuVal(_TriFilter.yes, 'On watchlist'),
                  _MenuVal(_TriFilter.no, 'Not on watchlist'),
                ],
                onPick: (v) => setState(() => _watchlist = v ?? _TriFilter.any),
              ),
              const SizedBox(width: 8),
              _chipMenu<double?>(
                context,
                label: 'Rating',
                subtitle: _minVote == null ? 'Any' : '≥ ${_minVote!.toStringAsFixed(0)}',
                items: const [
                  _MenuVal<double?>(null, 'Any TMDB rating'),
                  _MenuVal(6.0, '≥ 6'),
                  _MenuVal(7.0, '≥ 7'),
                  _MenuVal(8.0, '≥ 8'),
                ],
                onPick: (v) => setState(() => _minVote = v),
              ),
              const SizedBox(width: 8),
              _chipMenu<String?>(
                context,
                label: 'Collection',
                subtitle: _collectionListId == null
                    ? 'Any'
                    : (listsData?.lists.where((l) => l.id == _collectionListId).firstOrNull?.name ??
                        'List'),
                items: [
                  const _MenuVal<String?>(null, 'Any list'),
                  if (listsData != null)
                    for (final list in listsData.lists)
                      _MenuVal<String?>(list.id, list.name),
                ],
                onPick: (v) => setState(() => _collectionListId = v),
              ),
              const SizedBox(width: 8),
              _chipMenu<String?>(
                context,
                label: 'Genre',
                subtitle: _genreKey == null ? 'Any' : (genreChoices[_genreKey!] ?? 'Genre'),
                items: [
                  const _MenuVal<String?>(null, 'Any genre'),
                  for (final e in genreChoices.entries)
                    _MenuVal<String?>(e.key, e.value),
                ],
                onPick: (v) => setState(() => _genreKey = v),
              ),
              const SizedBox(width: 8),
              _chipMenu<int?>(
                context,
                label: 'Year',
                subtitle: _year?.toString() ?? 'Any',
                items: [
                  const _MenuVal<int?>(null, 'Any year'),
                  for (final y in sortedYears) _MenuVal<int?>(y, y.toString()),
                ],
                onPick: (v) => setState(() => _year = v),
              ),
            ],
          ),
        ),
        if (!widget.booksOnly && !widget.musicOnly) const SizedBox(height: 12),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.booksOnly
                  ? (hasBibliographySearch
                      ? 'No books match your search.'
                      : 'No books listed for this author yet.')
                  : widget.musicOnly
                  ? (hasBibliographySearch
                      ? 'No albums match your search.'
                      : 'No albums listed for this artist yet.')
                  : 'No credits match these filters.',
              style: CulturCatalogTypography.emptyState(theme, theme.colorScheme),
            ),
          )
        else
          ..._buildYearSections(
            context,
            _groupPersonFilmographyEntries(filtered),
            digest,
            bookTrackingByMediaId: bookTrackingByMediaId,
            musicTrackingByMediaId: musicTrackingByMediaId,
          ),
      ],
    );
  }

  int? _groupReleaseYear(_PersonFilmographyGroup group) {
    if (group.mediaType == 'book' || group.mediaType == 'music') {
      return _releaseYear(
        PersonFilmographyEntry(media: group.media, mediaType: group.mediaType),
      );
    }
    final d = group.media.metadata['releaseDate']?.toString();
    if (d == null || d.length < 4) {
      return null;
    }
    return int.tryParse(d.substring(0, 4));
  }

  List<Widget> _buildYearSections(
    BuildContext context,
    List<_PersonFilmographyGroup> groups,
    UserMovieTrackingDigest digest, {
    Map<String, TrackingItem> bookTrackingByMediaId = const {},
    Map<String, TrackingItem> musicTrackingByMediaId = const {},
  }) {
    final theme = Theme.of(context);
    final byYear = <int, List<_PersonFilmographyGroup>>{};
    for (final group in groups) {
      final y = _groupReleaseYear(group) ?? 0;
      byYear.putIfAbsent(y, () => []).add(group);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    final widgets = <Widget>[];
    for (final y in years) {
      final label = y == 0 ? 'Unknown year' : '$y';
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: CulturCatalogTypography.yearDivider(theme, theme.colorScheme),
            ),
          ),
        ),
      );
      final yearGroups = byYear[y]!;
      for (var i = 0; i < yearGroups.length; i++) {
        if (i > 0) {
          widgets.add(const SizedBox(height: 12));
        }
        final group = yearGroups[i];
        final tracking = widget.booksOnly
            ? bookTrackingByMediaId[group.media.id]
            : widget.musicOnly
            ? musicTrackingByMediaId[group.media.id]
            : digest.byMediaId[group.media.id];
        widgets.add(
          CulturCatalogListRow(
            item: group.media,
            metaParts: _personFilmographyCreditMetaParts(group),
            score: tracking?.score,
            onTap: () => _openGroup(group),
          ),
        );
      }
    }
    return widgets;
  }
}
