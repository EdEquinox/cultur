part of '../library/library_external_import_page.dart';

/// Cultur destination for a Hardcover list or library shelf.
enum _HardcoverCulturTarget {
  skip,
  later,
  laterPriority,
  buy,
  read,
  owned,
  reading,
  dropped,
  customList,
}

extension on _HardcoverCulturTarget {
  String get apiValue => switch (this) {
        _HardcoverCulturTarget.skip => 'skip',
        _HardcoverCulturTarget.later => 'later',
        _HardcoverCulturTarget.laterPriority => 'later_priority',
        _HardcoverCulturTarget.buy => 'buy',
        _HardcoverCulturTarget.read => 'read',
        _HardcoverCulturTarget.owned => 'owned',
        _HardcoverCulturTarget.reading => 'reading',
        _HardcoverCulturTarget.dropped => 'dropped',
        _HardcoverCulturTarget.customList => 'custom_list',
      };

  String get label => switch (this) {
        _HardcoverCulturTarget.skip => 'Skip',
        _HardcoverCulturTarget.later => 'Later',
        _HardcoverCulturTarget.laterPriority => 'Later + priority',
        _HardcoverCulturTarget.buy => 'Buy',
        _HardcoverCulturTarget.read => 'Read',
        _HardcoverCulturTarget.owned => 'Owned',
        _HardcoverCulturTarget.reading => 'Reading',
        _HardcoverCulturTarget.dropped => 'Dropped',
        _HardcoverCulturTarget.customList => 'Custom list (same name)',
      };

}

_HardcoverCulturTarget? _hardcoverTargetFromApi(String? raw) {
  return switch (raw?.trim().toLowerCase()) {
    'skip' => _HardcoverCulturTarget.skip,
    'later' => _HardcoverCulturTarget.later,
    'later_priority' => _HardcoverCulturTarget.laterPriority,
    'priority' => _HardcoverCulturTarget.laterPriority,
    'buy' => _HardcoverCulturTarget.buy,
    'read' => _HardcoverCulturTarget.read,
    'owned' => _HardcoverCulturTarget.owned,
    'reading' => _HardcoverCulturTarget.reading,
    'dropped' => _HardcoverCulturTarget.dropped,
    'custom_list' => _HardcoverCulturTarget.customList,
    _ => null,
  };
}

class _HardcoverImportSourceRow {
  const _HardcoverImportSourceRow({
    required this.sourceKey,
    required this.kind,
    required this.name,
    required this.booksCount,
    this.isPublic,
  });

  final String sourceKey;
  final String kind;
  final String name;
  final int booksCount;
  final bool? isPublic;
}

class _ProfileHardcoverImportCard extends ConsumerStatefulWidget {
  const _ProfileHardcoverImportCard({required this.theme, required this.username});

  final ThemeData theme;
  final String username;

  @override
  ConsumerState<_ProfileHardcoverImportCard> createState() => _ProfileHardcoverImportCardState();
}

class _ProfileHardcoverImportCardState extends ConsumerState<_ProfileHardcoverImportCard> {
  final _usernameController = TextEditingController();
  bool _loadingSources = false;
  bool _isImporting = false;
  List<_HardcoverImportSourceRow> _sources = const [];
  final Map<String, _HardcoverCulturTarget> _targets = {};
  final Set<String> _selectedSourceKeys = {};
  int _importedTotal = 0;
  int _pendingTotal = 0;
  int _skippedTotal = 0;
  String? _resolvedHcUsername;

  static const _importableTargets = [
    _HardcoverCulturTarget.later,
    _HardcoverCulturTarget.laterPriority,
    _HardcoverCulturTarget.buy,
    _HardcoverCulturTarget.read,
    _HardcoverCulturTarget.owned,
    _HardcoverCulturTarget.reading,
    _HardcoverCulturTarget.dropped,
    _HardcoverCulturTarget.customList,
  ];

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    final hcUser = _usernameController.text.trim().replaceFirst(RegExp(r'^@+'), '');
    if (hcUser.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a Hardcover username.')),
      );
      return;
    }
    setState(() {
      _loadingSources = true;
      _sources = const [];
      _targets.clear();
      _selectedSourceKeys.clear();
    });
    try {
      final client = ref.read(apiClientProvider);
      final payload = await client.getJson(
        '/backend/import/hardcover-lists',
        queryParameters: {'hardcover_username': hcUser},
      );
      if (!mounted) {
        return;
      }
      final sourcesRaw = payload['sources'] as List<dynamic>? ?? payload['lists'] as List<dynamic>? ?? [];
      final rows = <_HardcoverImportSourceRow>[];
      final targets = <String, _HardcoverCulturTarget>{};
      final selected = <String>{};

      for (final raw in sourcesRaw.whereType<Map<String, dynamic>>()) {
        final sourceKey = raw['sourceKey']?.toString();
        if (sourceKey == null || sourceKey.isEmpty) {
          final listId = int.tryParse(raw['listId']?.toString() ?? '');
          if (listId == null || listId <= 0) {
            continue;
          }
          final key = 'list:$listId';
          rows.add(
            _HardcoverImportSourceRow(
              sourceKey: key,
              kind: 'list',
              name: raw['name']?.toString() ?? 'List',
              booksCount: int.tryParse(raw['booksCount']?.toString() ?? '') ?? 0,
              isPublic: raw['public'] == true,
            ),
          );
          targets[key] = _HardcoverCulturTarget.customList;
          selected.add(key);
          continue;
        }
        final kind = raw['kind']?.toString() ?? 'list';
        final defaultTarget =
            _hardcoverTargetFromApi(raw['defaultCulturTarget']?.toString()) ??
                (kind == 'shelf' ? _HardcoverCulturTarget.later : _HardcoverCulturTarget.customList);
        rows.add(
          _HardcoverImportSourceRow(
            sourceKey: sourceKey,
            kind: kind,
            name: raw['name']?.toString() ?? 'Source',
            booksCount: int.tryParse(raw['booksCount']?.toString() ?? '') ?? 0,
            isPublic: raw['public'] == true,
          ),
        );
        targets[sourceKey] = defaultTarget;
        selected.add(sourceKey);
      }

      setState(() {
        _sources = rows;
        _targets.addAll(targets);
        _selectedSourceKeys.addAll(selected);
        _resolvedHcUsername = payload['hardcoverUsername']?.toString() ?? hcUser;
        _loadingSources = false;
      });
      if (rows.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No library shelves or lists found for this user.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loadingSources = false);
        showApiErrorSnackBar(context, error, prefix: 'Hardcover:');
      }
    }
  }

  Future<void> _applyCustomListAssignments(List<dynamic> raw) async {
    if (raw.isEmpty) {
      return;
    }
    final controller = ref.read(customBookListsControllerProvider);
    var data = await controller.load(widget.username);

    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      final listName = entry['listName']?.toString().trim();
      final mediaId = entry['mediaId']?.toString();
      if (listName == null || listName.isEmpty || mediaId == null || mediaId.isEmpty) {
        continue;
      }
      CustomMovieList? list;
      for (final candidate in data.lists) {
        if (candidate.name.trim().toLowerCase() == listName.toLowerCase()) {
          list = candidate;
          break;
        }
      }
      if (list == null) {
        list = await controller.createList(widget.username, listName);
        data = await controller.load(widget.username);
      }
      final item = CatalogItem(
        id: mediaId,
        source: entry['source']?.toString() ?? 'hardcover',
        externalId: entry['externalId']?.toString() ?? '',
        mediaType: 'book',
        title: entry['title']?.toString() ?? listName,
        metadata: const {},
      );
      final alreadyIn = list.items.any((existing) => existing.id == item.id);
      if (!alreadyIn) {
        await controller.toggleItem(
          username: widget.username,
          listId: list.id,
          item: item,
        );
      }
    }
    ref.invalidate(customBookListsProvider);
  }

  Future<void> _runImport() async {
    final hcUser = (_resolvedHcUsername ?? _usernameController.text.trim())
        .replaceFirst(RegExp(r'^@+'), '');
    if (hcUser.isEmpty) {
      return;
    }
    final mappings = <Map<String, String>>[];
    for (final source in _sources) {
      if (!_selectedSourceKeys.contains(source.sourceKey)) {
        continue;
      }
      final target = _targets[source.sourceKey] ?? _HardcoverCulturTarget.skip;
      mappings.add({
        'sourceKey': source.sourceKey,
        'culturTarget': target.apiValue,
      });
    }
    final active = mappings.where((m) => m['culturTarget'] != 'skip').length;
    if (active == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one source with a Cultur mapping other than Skip.')),
      );
      return;
    }
    setState(() => _isImporting = true);
    try {
      final client = ref.read(apiClientProvider);
      final out = await client.postJson(
        '/backend/import/hardcover-batch',
        data: {
          'username': widget.username,
          'hardcoverUsername': hcUser,
          'mappings': mappings,
        },
      );
      if (!mounted) {
        return;
      }
      await _applyCustomListAssignments(out['customListAssignments'] as List<dynamic>? ?? []);
      setState(() {
        _importedTotal += int.tryParse(out['imported']?.toString() ?? '') ?? 0;
        _pendingTotal += int.tryParse(out['pending']?.toString() ?? '') ?? 0;
        _skippedTotal += int.tryParse(out['skipped']?.toString() ?? '') ?? 0;
        _isImporting = false;
      });
      invalidateBooksHomeCaches(ref, username: widget.username);
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.book));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Hardcover import: ${out['imported']} added'
            '${(int.tryParse(out['pending']?.toString() ?? '') ?? 0) > 0 ? ', ${out['pending']} pending' : ''}.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _isImporting = false);
        showApiErrorSnackBar(context, error, prefix: 'Import failed:');
      }
    }
  }

  String _sourceSubtitle(_HardcoverImportSourceRow source) {
    final kindLabel = source.kind == 'shelf' ? 'Library shelf' : 'List';
    final visibility = source.kind == 'list' && source.isPublic == false ? ' · private' : '';
    return '$kindLabel · ${source.booksCount} books$visibility';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.theme.colorScheme;
    final metaStyle = CulturCatalogTypography.listMeta(widget.theme, scheme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Import from Hardcover', style: CulturCatalogTypography.listTitle(widget.theme)),
            const SizedBox(height: 4),
            Text(
              'Import library shelves (Want to Read, Reading, Read, …) and custom lists. '
              'Map each source to Later, Later + priority (Next to read), Buy, Read, Owned, Reading, Dropped, or a Cultur list with the same name. '
              'Books in multiple sources merge flags (e.g. Want to Read + Priorities).',
              style: metaStyle,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Hardcover username',
                hintText: 'your_handle',
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadSources(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: _loadingSources || _isImporting ? null : _loadSources,
                  child: _loadingSources
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Load shelves & lists'),
                ),
                if (_sources.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _isImporting
                        ? null
                        : () => setState(() {
                              if (_selectedSourceKeys.length == _sources.length) {
                                _selectedSourceKeys.clear();
                              } else {
                                _selectedSourceKeys.addAll(_sources.map((s) => s.sourceKey));
                              }
                            }),
                    child: Text(
                      _selectedSourceKeys.length == _sources.length ? 'Clear all' : 'Select all',
                    ),
                  ),
                ],
              ],
            ),
            if (_sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _sources.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final source = _sources[index];
                    final selected = _selectedSourceKeys.contains(source.sourceKey);
                    final target = _targets[source.sourceKey] ?? _HardcoverCulturTarget.skip;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: selected,
                            onChanged: _isImporting
                                ? null
                                : (value) => setState(() {
                                      if (value == true) {
                                        _selectedSourceKeys.add(source.sourceKey);
                                      } else {
                                        _selectedSourceKeys.remove(source.sourceKey);
                                      }
                                    }),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  source.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: CulturCatalogTypography.listTitle(widget.theme),
                                ),
                                Text(_sourceSubtitle(source), style: metaStyle),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<_HardcoverCulturTarget>(
                                  value: target,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Import to Cultur',
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: _HardcoverCulturTarget.skip,
                                      child: Text('Skip'),
                                    ),
                                    ..._importableTargets.map(
                                      (t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(t.label),
                                      ),
                                    ),
                                  ],
                                  onChanged: _isImporting || !selected
                                      ? null
                                      : (value) {
                                          if (value == null) {
                                            return;
                                          }
                                          setState(() => _targets[source.sourceKey] = value);
                                        },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _isImporting ? null : _runImport,
                icon: _isImporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 18),
                label: const Text('Import selected'),
              ),
            ],
            if (_importedTotal > 0 || _pendingTotal > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Session totals: $_importedTotal imported, $_pendingTotal pending, $_skippedTotal skipped.',
                style: metaStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
