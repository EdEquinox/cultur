part of '../library/library_external_import_page.dart';

class _ProfileBookmoryImportCard extends ConsumerStatefulWidget {
  const _ProfileBookmoryImportCard({required this.theme, required this.username});

  final ThemeData theme;
  final String username;

  @override
  ConsumerState<_ProfileBookmoryImportCard> createState() =>
      _ProfileBookmoryImportCardState();
}

class _ProfileBookmoryImportCardState extends ConsumerState<_ProfileBookmoryImportCard> {
  bool _isImporting = false;
  String _phase = '';
  int _processed = 0;
  int _total = 0;
  int _importedTotal = 0;
  int _skippedTotal = 0;
  int _pendingTotal = 0;
  final List<_BookmoryImportIssue> _issues = [];

  /// Smaller batches avoid per-request timeouts while catalog lookups run.
  static const _batchSize = 10;

  List<File> _collectTxtFiles(Directory dir) {
    final files = <File>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.txt')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<void> _importFromFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Bookmory export folder',
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
    final files = _collectTxtFiles(dirEntity);
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No .txt files in that folder.')),
        );
      }
      return;
    }
    await _runImport(files);
  }

  Future<void> _importFromFiles() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
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
          _BookmoryImportIssue(
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
      _phase = 'Parsing export files…';
      _processed = 0;
      _total = files.length;
      _importedTotal = 0;
      _skippedTotal = 0;
      _pendingTotal = 0;
      _issues.clear();
    });

    final entries = <Map<String, dynamic>>[];
    for (final file in files) {
      final outcome = parseBookmoryExportText(
        sourceFile: file.name,
        text: file.text,
      );
      switch (outcome) {
        case BookmoryParseSuccess(:final entry):
          entries.add(entry.toImportJson());
        case BookmoryParseError(:final failure):
          _issues.add(
            _BookmoryImportIssue(
              sourceFile: failure.sourceFile,
              title: failure.sourceFile,
              message: failure.message,
            ),
          );
      }
    }

    if (entries.isEmpty && _issues.isEmpty) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to import.')),
        );
      }
      return;
    }

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
                'Importing batch ${batchIndex + 1}/$batchCount (books ${i + 1}–$end of ${entries.length})…';
            _processed = i;
            _total = entries.length;
          });
        }
        try {
          final out = await client.postJson(
            '/backend/import/bookmory-batch',
            data: {
              'username': widget.username,
              'entries': batch,
            },
            receiveTimeout: const Duration(minutes: 15),
            sendTimeout: const Duration(minutes: 2),
          );
          _importedTotal += (out['imported'] as num?)?.toInt() ?? 0;
          _skippedTotal += (out['skipped'] as num?)?.toInt() ?? 0;
          _pendingTotal += (out['pending'] as num?)?.toInt() ?? 0;
          final errorsRaw = out['errors'];
          if (errorsRaw is List) {
            for (final raw in errorsRaw) {
              if (raw is! Map) {
                continue;
              }
              final map = Map<String, dynamic>.from(raw);
              _issues.add(
                _BookmoryImportIssue(
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
            _BookmoryImportIssue(
              sourceFile: 'batch ${batchIndex + 1}',
              title: 'Books ${i + 1}–$end',
              message: error.toString(),
            ),
          );
        }
      }
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.book));
      invalidateBooksHomeCaches(ref, username: widget.username);
      if (!mounted) {
        return;
      }
      setState(() {
        _processed = entries.length;
        _total = entries.length;
      });
      final batchNote = failedBatches > 0 ? ' · $failedBatches batch(es) could not be sent' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _issues.isEmpty
                ? 'Imported $_importedTotal of ${entries.length} books from Bookmory.'
                    '${_pendingTotal > 0 ? ' · $_pendingTotal pending (link in library)' : ''}'
                : 'Imported $_importedTotal of ${entries.length}'
                    ' · $_skippedTotal skipped'
                    '${_pendingTotal > 0 ? ' · $_pendingTotal pending (link in library)' : ''}'
                    '$batchNote'
                    ' · ${_issues.length} issue(s) — see list below.',
          ),
          duration: Duration(seconds: _issues.isEmpty ? 4 : 12),
        ),
      );
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error, prefix: 'Bookmory import failed:');
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
            Text('Bookmory import', style: CulturCatalogTypography.listTitle(widget.theme)),
            const SizedBox(height: 4),
            Text(
              'Import from a folder (one .txt per book, including subfolders) or pick files. '
              'Catalog: PORBASE → Hardcover → Open Library. '
              'Imports run in batches of $_batchSize — keep this screen open until all batches finish.',
              style: CulturCatalogTypography.listMeta(widget.theme, scheme),
            ),
            if (_isImporting) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                minHeight: 6,
                value: _total > 0 ? (_processed / _total).clamp(0.0, 1.0) : null,
              ),
              const SizedBox(height: 8),
              Text(
                _phase,
                style: widget.theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isImporting ? null : _importFromFolder,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Choose export folder'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isImporting ? null : _importFromFiles,
                icon: _isImporting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.upload_file_outlined),
                label: Text(_isImporting ? 'Importing…' : 'Choose .txt files'),
              ),
            ),
            if (_importedTotal > 0 || _issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Last run: $_importedTotal imported'
                '${_skippedTotal > 0 ? ' · $_skippedTotal skipped on server' : ''}'
                '${_pendingTotal > 0 ? ' · $_pendingTotal pending (link in library)' : ''}'
                '${_issues.isNotEmpty ? ' · ${_issues.length} issue(s)' : ''}',
                style: widget.theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Could not import these — fix in Bookmory or add manually later:',
                style: widget.theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _issues.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final issue = _issues[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        issue.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: widget.theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${issue.sourceFile}\n${issue.message}',
                        style: widget.theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

class _BookmoryImportIssue {
  const _BookmoryImportIssue({
    required this.sourceFile,
    required this.title,
    required this.message,
  });

  final String sourceFile;
  final String title;
  final String message;
}
