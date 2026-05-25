part of '../library/library_external_import_page.dart';

class _ProfileStashImportCard extends ConsumerStatefulWidget {
  const _ProfileStashImportCard({required this.theme, required this.username});

  final ThemeData theme;
  final String username;

  @override
  ConsumerState<_ProfileStashImportCard> createState() => _ProfileStashImportCardState();
}

class _ProfileStashImportCardState extends ConsumerState<_ProfileStashImportCard> {
  final _stashUsernameController = TextEditingController();
  bool _isImporting = false;
  String _phase = '';
  int _processed = 0;
  int _total = 0;
  int _importedTotal = 0;
  int _pendingTotal = 0;
  int _skippedTotal = 0;
  final List<_StashImportIssue> _issues = [];

  static const _batchSize = 8;

  @override
  void dispose() {
    _stashUsernameController.dispose();
    super.dispose();
  }

  Future<void> _importFromStashProfile() async {
    final stashUser = _stashUsernameController.text.trim().replaceFirst(RegExp(r'^@+'), '');
    if (stashUser.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your Stash.games username.')),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _phase = 'Scraping Stash profile (this can take several minutes)…';
      _processed = 0;
      _total = 0;
      _importedTotal = 0;
      _pendingTotal = 0;
      _skippedTotal = 0;
      _issues.clear();
    });

    final client = ref.read(apiClientProvider);
    try {
      final out = await client.postJson(
        '/backend/import/stash-profile',
        data: {
          'username': widget.username,
          'stashUsername': stashUser,
        },
        receiveTimeout: const Duration(minutes: 45),
        sendTimeout: const Duration(minutes: 2),
      );
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
            _StashImportIssue(
              sourceFile: map['sourceFile']?.toString() ?? 'unknown',
              title: map['title']?.toString() ?? map['sourceFile']?.toString() ?? 'unknown',
              message:
                  map['message']?.toString() ?? map['reason']?.toString() ?? 'Import failed',
            ),
          );
        }
      }

      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.game));
      ref.invalidate(gameSearchTrackingProvider(widget.username));
      ref.invalidate(customGameListsProvider);
      invalidateGamesHomeCaches(ref, username: widget.username);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _issues.isEmpty
                ? 'Imported $_importedTotal games from Stash profile @$stashUser.'
                : 'Imported $_importedTotal'
                    '${_pendingTotal > 0 ? ' · $_pendingTotal pending' : ''}'
                    '${_skippedTotal > 0 ? ' · $_skippedTotal skipped' : ''}'
                    ' · ${_issues.length} note(s) — see list below.',
          ),
          duration: Duration(seconds: _issues.isEmpty ? 4 : 12),
        ),
      );
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error, prefix: 'Stash profile import failed:');
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
      dialogTitle: 'Select Stash CSV export folder',
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
    await _runImport(files);
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
    await _runImportFromTexts(payloads);
  }

  Future<void> _runImport(List<File> files) async {
    final payloads = <({String name, String text})>[];
    for (final file in files) {
      try {
        payloads.add((name: _fileName(file.path), text: await file.readAsString()));
      } catch (e) {
        _issues.add(
          _StashImportIssue(
            sourceFile: _fileName(file.path),
            title: _fileName(file.path),
            message: 'Could not read file: $e',
          ),
        );
      }
    }
    await _runImportFromTexts(payloads);
  }

  Future<void> _runImportFromTexts(List<({String name, String text})> files) async {
    setState(() {
      _isImporting = true;
      _phase = 'Parsing CSV files…';
      _processed = 0;
      _total = 0;
      _importedTotal = 0;
      _pendingTotal = 0;
      _skippedTotal = 0;
      _issues.clear();
    });

    final outcome = parseStashCsvFiles(files);
    if (outcome is StashCsvParseError) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(outcome.failure.message)),
        );
      }
      return;
    }
    final success = outcome as StashCsvParseSuccess;
    for (final failure in success.failures) {
      _issues.add(
        _StashImportIssue(
          sourceFile: failure.sourceFile,
          title: failure.sourceFile,
          message: failure.message,
        ),
      );
    }
    final games = success.games;

    if (games.isEmpty) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to import.')),
        );
      }
      return;
    }

    final entries = games.map((g) => g.toImportJson()).toList();
    final client = ref.read(apiClientProvider);
    var failedBatches = 0;

    try {
      final batchCount = (entries.length + _batchSize - 1) ~/ _batchSize;
      for (var batchIndex = 0; batchIndex < batchCount; batchIndex++) {
        final i = batchIndex * _batchSize;
        final end = (i + _batchSize < entries.length) ? i + _batchSize : entries.length;
        final batch = entries.sublist(i, end);
        if (mounted) {
          setState(() {
            _phase =
                'Importing batch ${batchIndex + 1}/$batchCount (games ${i + 1}–$end of ${entries.length})…';
            _processed = i;
            _total = entries.length;
          });
        }
        try {
          final out = await client.postJson(
            '/backend/import/stash-batch',
            data: {
              'username': widget.username,
              'entries': batch,
            },
            receiveTimeout: const Duration(minutes: 15),
            sendTimeout: const Duration(minutes: 2),
          );
          _importedTotal += (out['imported'] as num?)?.toInt() ?? 0;
          _pendingTotal += (out['pending'] as num?)?.toInt() ?? 0;
          _skippedTotal += (out['skipped'] as num?)?.toInt() ?? 0;
          final errorsRaw = out['errors'];
          if (errorsRaw is List) {
            for (final raw in errorsRaw) {
              if (raw is! Map) {
                continue;
              }
              final map = Map<String, dynamic>.from(raw);
              _issues.add(
                _StashImportIssue(
                  sourceFile: map['sourceFile']?.toString() ?? 'unknown',
                  title: map['title']?.toString() ?? map['sourceFile']?.toString() ?? 'unknown',
                  message:
                      map['message']?.toString() ?? map['reason']?.toString() ?? 'Import failed',
                ),
              );
            }
          }
          if (mounted) {
            setState(() => _processed = end);
          }
        } catch (error) {
          failedBatches++;
          _issues.add(
            _StashImportIssue(
              sourceFile: 'batch ${batchIndex + 1}',
              title: 'Games ${i + 1}–$end',
              message: error.toString(),
            ),
          );
        }
      }

      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.game));
      ref.invalidate(gameSearchTrackingProvider(widget.username));
      ref.invalidate(customGameListsProvider);
      invalidateGamesHomeCaches(ref, username: widget.username);

      if (!mounted) {
        return;
      }
      setState(() {
        _processed = entries.length;
        _total = entries.length;
      });
      final batchNote = failedBatches > 0 ? ' · $failedBatches batch(es) failed' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _issues.isEmpty
                ? 'Imported $_importedTotal of ${entries.length} games from Stash.'
                : 'Imported $_importedTotal of ${entries.length}'
                    '${_pendingTotal > 0 ? ' · $_pendingTotal pending (link in library)' : ''}'
                    '${_skippedTotal > 0 ? ' · $_skippedTotal skipped' : ''}'
                    '$batchNote'
                    ' · ${_issues.length} note(s) — see list below.',
          ),
          duration: Duration(seconds: _issues.isEmpty ? 4 : 12),
        ),
      );
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error, prefix: 'Stash import failed:');
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stash import', style: CulturCatalogTypography.listTitle(widget.theme)),
            const SizedBox(height: 4),
            Text(
              'Import from your public Stash.games profile (server scrapes reviews, library tabs, '
              'and configured collections) or from CSV exports. Games are matched on IGDB via cover URLs.',
              style: CulturCatalogTypography.listMeta(widget.theme, scheme),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stashUsernameController,
              enabled: !_isImporting,
              decoration: const InputDecoration(
                labelText: 'Stash username',
                hintText: 'edequinox',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _isImporting ? null : _importFromStashProfile(),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isImporting ? null : _importFromStashProfile,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Text(_isImporting ? 'Importing…' : 'Import from Stash profile'),
            ),
            const SizedBox(height: 12),
            Text(
              'Or import CSV files',
              style: widget.theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            if (_isImporting) ...[
              LinearProgressIndicator(
                value: _total > 0 ? _processed / _total : null,
              ),
              const SizedBox(height: 8),
              Text(_phase, style: widget.theme.textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
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
                  icon: _isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: Text(_isImporting ? 'Importing…' : 'Choose CSV files'),
                ),
              ],
            ),
            if (_importedTotal > 0 || _issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Last run: $_importedTotal imported'
                '${_skippedTotal > 0 ? ' · $_skippedTotal skipped' : ''}'
                '${_issues.isNotEmpty ? ' · ${_issues.length} issue(s)' : ''}',
                style: widget.theme.textTheme.bodySmall,
              ),
            ],
            if (_issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Could not import these:',
                style: widget.theme.textTheme.labelMedium?.copyWith(color: scheme.error),
              ),
              const SizedBox(height: 4),
              ..._issues.take(12).map(
                (issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${issue.title}: ${issue.message}',
                    style: widget.theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              ),
              if (_issues.length > 12)
                Text(
                  '… and ${_issues.length - 12} more',
                  style: widget.theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StashImportIssue {
  const _StashImportIssue({
    required this.sourceFile,
    required this.title,
    required this.message,
  });

  final String sourceFile;
  final String title;
  final String message;
}
