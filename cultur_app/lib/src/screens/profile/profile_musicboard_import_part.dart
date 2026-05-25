part of '../library/library_external_import_page.dart';

enum _MusicboardCulturTarget {
  skip,
  later,
  laterPriority,
  buy,
  listened,
  owned,
  priority,
  customList,
  rating,
}

extension on _MusicboardCulturTarget {
  String get apiValue => switch (this) {
        _MusicboardCulturTarget.skip => 'skip',
        _MusicboardCulturTarget.later => 'later',
        _MusicboardCulturTarget.laterPriority => 'later_priority',
        _MusicboardCulturTarget.buy => 'buy',
        _MusicboardCulturTarget.listened => 'listened',
        _MusicboardCulturTarget.owned => 'owned',
        _MusicboardCulturTarget.priority => 'priority',
        _MusicboardCulturTarget.customList => 'custom_list',
        _MusicboardCulturTarget.rating => 'rating',
      };

  String get label => switch (this) {
        _MusicboardCulturTarget.skip => 'Skip',
        _MusicboardCulturTarget.later => 'Later',
        _MusicboardCulturTarget.laterPriority => 'Later + priority',
        _MusicboardCulturTarget.buy => 'Buy',
        _MusicboardCulturTarget.listened => 'Listened',
        _MusicboardCulturTarget.owned => 'Owned',
        _MusicboardCulturTarget.priority => 'Priority only',
        _MusicboardCulturTarget.customList => 'Custom list (same name)',
        _MusicboardCulturTarget.rating => 'Rating only (reviews)',
      };
}

_MusicboardCulturTarget? _musicboardTargetFromApi(String? raw) {
  return switch (raw?.trim().toLowerCase()) {
    'skip' => _MusicboardCulturTarget.skip,
    'later' => _MusicboardCulturTarget.later,
    'later_priority' => _MusicboardCulturTarget.laterPriority,
    'priority' => _MusicboardCulturTarget.laterPriority,
    'buy' => _MusicboardCulturTarget.buy,
    'listened' => _MusicboardCulturTarget.listened,
    'watched' => _MusicboardCulturTarget.listened,
    'owned' => _MusicboardCulturTarget.owned,
    'collected' => _MusicboardCulturTarget.owned,
    'custom_list' => _MusicboardCulturTarget.customList,
    'rating' => _MusicboardCulturTarget.rating,
    _ => null,
  };
}

class _MusicboardImportSourceRow {
  const _MusicboardImportSourceRow({
    required this.sourceKey,
    required this.kind,
    required this.name,
    required this.path,
  });

  final String sourceKey;
  final String kind;
  final String name;
  final String path;
}

class _ProfileMusicboardImportCard extends ConsumerStatefulWidget {
  const _ProfileMusicboardImportCard({required this.theme, required this.username});

  final ThemeData theme;
  final String username;

  @override
  ConsumerState<_ProfileMusicboardImportCard> createState() =>
      _ProfileMusicboardImportCardState();
}

class _ProfileMusicboardImportCardState extends ConsumerState<_ProfileMusicboardImportCard> {
  final _musicboardUsernameController = TextEditingController();
  bool _loadingSources = false;
  bool _isImporting = false;
  String _phase = '';
  List<_MusicboardImportSourceRow> _sources = const [];
  final Map<String, _MusicboardCulturTarget> _targets = {};
  final Set<String> _selectedSourceKeys = {};
  int _importedTotal = 0;
  int _pendingTotal = 0;
  int _skippedTotal = 0;
  final List<_MusicboardImportIssue> _issues = [];
  String? _resolvedBoardUsername;

  static const _batchSize = 8;
  static const _importableTargets = [
    _MusicboardCulturTarget.later,
    _MusicboardCulturTarget.laterPriority,
    _MusicboardCulturTarget.buy,
    _MusicboardCulturTarget.listened,
    _MusicboardCulturTarget.owned,
    _MusicboardCulturTarget.priority,
    _MusicboardCulturTarget.customList,
    _MusicboardCulturTarget.rating,
  ];

  @override
  void dispose() {
    _musicboardUsernameController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    final boardUser = _musicboardUsernameController.text.trim().replaceFirst(RegExp(r'^@+'), '');
    if (boardUser.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your Musicboard username.')),
      );
      return;
    }
    setState(() {
      _loadingSources = true;
      _sources = const [];
      _targets.clear();
      _selectedSourceKeys.clear();
      _issues.clear();
    });
    try {
      final client = ref.read(apiClientProvider);
      final payload = await client.getJson(
        '/backend/import/musicboard-sources',
        queryParameters: {'musicboard_username': boardUser},
      );
      if (!mounted) {
        return;
      }
      final sourcesRaw = payload['sources'] as List<dynamic>? ?? [];
      final rows = <_MusicboardImportSourceRow>[];
      final targets = <String, _MusicboardCulturTarget>{};
      final selected = <String>{};

      for (final raw in sourcesRaw.whereType<Map<String, dynamic>>()) {
        final sourceKey = raw['sourceKey']?.toString();
        if (sourceKey == null || sourceKey.isEmpty) {
          continue;
        }
        final kind = raw['kind']?.toString() ?? 'list';
        final defaultTarget =
            _musicboardTargetFromApi(raw['defaultCulturTarget']?.toString()) ??
                (kind == 'list'
                    ? _MusicboardCulturTarget.customList
                    : _MusicboardCulturTarget.later);
        rows.add(
          _MusicboardImportSourceRow(
            sourceKey: sourceKey,
            kind: kind,
            name: raw['name']?.toString() ?? 'Source',
            path: raw['path']?.toString() ?? '',
          ),
        );
        targets[sourceKey] = defaultTarget;
        selected.add(sourceKey);
      }

      setState(() {
        _sources = rows;
        _targets.addAll(targets);
        _selectedSourceKeys.addAll(selected);
        _resolvedBoardUsername = payload['musicboardUsername']?.toString() ?? boardUser;
        _loadingSources = false;
      });
      if (rows.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No lists or profile areas found for this user.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loadingSources = false);
        showApiErrorSnackBar(context, error, prefix: 'Musicboard:');
      }
    }
  }

  Future<void> _applyCustomListAssignments(List<dynamic> raw) async {
    if (raw.isEmpty) {
      return;
    }
    final controller = ref.read(customMusicListsControllerProvider);
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
        source: entry['source']?.toString() ?? 'musicbrainz',
        externalId: entry['externalId']?.toString() ?? '',
        mediaType: 'music',
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
    ref.invalidate(customMusicListsProvider);
  }

  Future<void> _runProfileImport() async {
    final boardUser = (_resolvedBoardUsername ?? _musicboardUsernameController.text.trim())
        .replaceFirst(RegExp(r'^@+'), '');
    if (boardUser.isEmpty) {
      return;
    }
    final mappings = <Map<String, String>>[];
    for (final source in _sources) {
      if (!_selectedSourceKeys.contains(source.sourceKey)) {
        continue;
      }
      final target = _targets[source.sourceKey] ?? _MusicboardCulturTarget.skip;
      mappings.add({
        'sourceKey': source.sourceKey,
        'culturTarget': target.apiValue,
      });
    }
    final active = mappings.where((m) => m['culturTarget'] != 'skip').length;
    if (active == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one source with a Cultur mapping other than Skip.'),
        ),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _phase = 'Scraping and importing (this can take several minutes)…';
      _importedTotal = 0;
      _pendingTotal = 0;
      _skippedTotal = 0;
      _issues.clear();
    });

    try {
      final client = ref.read(apiClientProvider);
      final out = await client.postJson(
        '/backend/import/musicboard-profile',
        data: {
          'username': widget.username,
          'musicboardUsername': boardUser,
          'mappings': mappings,
        },
        receiveTimeout: const Duration(minutes: 45),
        sendTimeout: const Duration(minutes: 2),
      );
      if (!mounted) {
        return;
      }
      await _applyCustomListAssignments(out['customListAssignments'] as List<dynamic>? ?? []);
      _importedTotal = (out['imported'] as num?)?.toInt() ?? 0;
      _pendingTotal = (out['pending'] as num?)?.toInt() ?? 0;
      _skippedTotal = (out['skipped'] as num?)?.toInt() ?? 0;
      final errorsRaw = out['errors'];
      if (errorsRaw is List) {
        for (final raw in errorsRaw) {
          if (raw is! Map) {
            continue;
          }
          final map = Map<String, dynamic>.from(raw);
          _issues.add(
            _MusicboardImportIssue(
              sourceFile: map['sourceFile']?.toString() ?? 'unknown',
              title: map['title']?.toString() ?? 'unknown',
              message:
                  map['message']?.toString() ?? map['reason']?.toString() ?? 'Import failed',
            ),
          );
        }
      }
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.music));
      ref.invalidate(customMusicListsProvider);
      invalidateAlbumsHomeCaches(ref, username: widget.username);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _issues.isEmpty
                ? 'Imported $_importedTotal albums from Musicboard @$boardUser.'
                : 'Imported $_importedTotal'
                    '${_pendingTotal > 0 ? ' · $_pendingTotal pending' : ''}'
                    '${_skippedTotal > 0 ? ' · $_skippedTotal skipped' : ''}'
                    ' · ${_issues.length} note(s).',
          ),
          duration: Duration(seconds: _issues.isEmpty ? 4 : 12),
        ),
      );
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error, prefix: 'Musicboard import failed:');
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  List<File> _collectCsvFiles(Directory dir) {
    final files = <File>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.csv')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<void> _importFromFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Musicboard CSV export folder',
    );
    if (dir == null || dir.trim().isEmpty) {
      return;
    }
    final dirEntity = Directory(dir);
    if (!dirEntity.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Folder not found.')),
        );
      }
      return;
    }
    final files = _collectCsvFiles(dirEntity);
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No .csv files in that folder.')),
        );
      }
      return;
    }
    await _runCsvImport(files);
  }

  Future<void> _importFromFiles() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      allowMultiple: true,
      withData: true,
    );
    if (pick == null || pick.files.isEmpty) {
      return;
    }
    final payloads = <({String name, String text})>[];
    for (final f in pick.files) {
      final name = f.name;
      String? text;
      if (f.bytes != null) {
        text = utf8.decode(f.bytes!);
      } else if (f.path != null) {
        text = await File(f.path!).readAsString();
      }
      if (text != null) {
        payloads.add((name: name, text: text));
      }
    }
    if (payloads.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read selected files.')),
        );
      }
      return;
    }
    await _runCsvImportFromTexts(payloads);
  }

  Future<void> _runCsvImport(List<File> files) async {
    final payloads = <({String name, String text})>[];
    for (final file in files) {
      try {
        payloads.add((name: _fileName(file.path), text: await file.readAsString()));
      } catch (e) {
        _issues.add(
          _MusicboardImportIssue(
            sourceFile: _fileName(file.path),
            title: _fileName(file.path),
            message: 'Could not read file: $e',
          ),
        );
      }
    }
    await _runCsvImportFromTexts(payloads);
  }

  Future<void> _runCsvImportFromTexts(List<({String name, String text})> files) async {
    setState(() {
      _isImporting = true;
      _phase = 'Parsing CSV files…';
      _importedTotal = 0;
      _pendingTotal = 0;
      _skippedTotal = 0;
      _issues.clear();
    });

    final outcome = parseMusicboardCsvFiles(files);
    if (outcome is MusicboardCsvParseError) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(outcome.failure.message)),
        );
      }
      return;
    }
    final success = outcome as MusicboardCsvParseSuccess;
    for (final failure in success.failures) {
      _issues.add(
        _MusicboardImportIssue(
          sourceFile: failure.sourceFile,
          title: failure.sourceFile,
          message: failure.message,
        ),
      );
    }
    final albums = success.albums;
    if (albums.isEmpty) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to import.')),
        );
      }
      return;
    }

    final entries = albums.map((a) => a.toImportJson()).toList();
    final client = ref.read(apiClientProvider);
    try {
      final batchCount = (entries.length + _batchSize - 1) ~/ _batchSize;
      for (var batchIndex = 0; batchIndex < batchCount; batchIndex++) {
        final i = batchIndex * _batchSize;
        final end = (i + _batchSize < entries.length) ? i + _batchSize : entries.length;
        final batch = entries.sublist(i, end);
        if (mounted) {
          setState(() {
            _phase = 'Importing batch ${batchIndex + 1}/$batchCount…';
          });
        }
        final out = await client.postJson(
          '/backend/import/musicboard-batch',
          data: {'username': widget.username, 'entries': batch},
          receiveTimeout: const Duration(minutes: 15),
        );
        _importedTotal += (out['imported'] as num?)?.toInt() ?? 0;
        _pendingTotal += (out['pending'] as num?)?.toInt() ?? 0;
        _skippedTotal += (out['skipped'] as num?)?.toInt() ?? 0;
        await _applyCustomListAssignments(out['customListAssignments'] as List<dynamic>? ?? []);
      }
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.music));
      ref.invalidate(customMusicListsProvider);
      invalidateAlbumsHomeCaches(ref, username: widget.username);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $_importedTotal of ${entries.length} albums from CSV.')),
        );
      }
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error, prefix: 'CSV import failed:');
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  String _sourceSubtitle(_MusicboardImportSourceRow source) {
    final kindLabel = source.kind == 'builtin' ? 'Profile area' : 'Playlist / list';
    return '$kindLabel · ${source.path}';
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
            Text('Musicboard import', style: CulturCatalogTypography.listTitle(widget.theme)),
            const SizedBox(height: 4),
            Text(
              'Load your public Musicboard lists and map each one to Cultur zones (Later, Buy, Listened, Owned, …) '
              'or to a custom album list with the same name — like Hardcover or Stash collections. '
              'Includes profile areas, your lists page, and any extra list paths configured on the server.',
              style: metaStyle,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _musicboardUsernameController,
              enabled: !_isImporting && !_loadingSources,
              decoration: const InputDecoration(
                labelText: 'Musicboard username',
                hintText: 'edequinox',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadingSources || _isImporting ? null : _loadSources(),
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
                      : const Text('Load lists & profile areas'),
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
            if (_isImporting && _phase.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_phase, style: widget.theme.textTheme.bodySmall),
            ],
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
                    final target = _targets[source.sourceKey] ?? _MusicboardCulturTarget.skip;
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
                                DropdownButtonFormField<_MusicboardCulturTarget>(
                                  value: target,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Import to Cultur',
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: _MusicboardCulturTarget.skip,
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
                onPressed: _isImporting ? null : _runProfileImport,
                icon: _isImporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('Import selected'),
              ),
            ],
            const SizedBox(height: 16),
            Text('Or import CSV exports', style: widget.theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isImporting ? null : _importFromFolder,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Export folder'),
                ),
                OutlinedButton.icon(
                  onPressed: _isImporting ? null : _importFromFiles,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Choose CSV files'),
                ),
              ],
            ),
            if (_importedTotal > 0 || _issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Last run: $_importedTotal imported'
                '${_pendingTotal > 0 ? ' · $_pendingTotal pending' : ''}'
                '${_issues.isNotEmpty ? ' · ${_issues.length} issue(s)' : ''}',
                style: widget.theme.textTheme.bodySmall,
              ),
              if (_issues.isNotEmpty) ...[
                const SizedBox(height: 4),
                ..._issues.take(8).map(
                  (issue) => Text(
                    '${issue.title}: ${issue.message}',
                    style: widget.theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _MusicboardImportIssue {
  const _MusicboardImportIssue({
    required this.sourceFile,
    required this.title,
    required this.message,
  });

  final String sourceFile;
  final String title;
  final String message;
}
