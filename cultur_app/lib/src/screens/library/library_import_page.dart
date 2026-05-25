import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client_provider.dart';
import '../../core/api_error_ui.dart';
import '../../core/session_storage.dart';
import '../../core/storage_keys.dart';
import '../../controllers/auth_controller.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/person_providers.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/utils/backup_export.dart';
import '../../providers/library_tracking_providers.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';

/// Cultur JSON backup export/import (v3). Legacy AVA/SeriesGuide files are also accepted on import.
class LibraryBackupPage extends ConsumerStatefulWidget {
  const LibraryBackupPage({super.key});

  @override
  ConsumerState<LibraryBackupPage> createState() => _LibraryBackupPageState();
}

class _LibraryBackupPageState extends ConsumerState<LibraryBackupPage> {
  bool _busy = false;
  bool _exporting = false;
  String? _lastResult;
  String? _lastExportResult;
  String _busyPhase = '';
  String? _busyFileName;
  DateTime? _busyStartedAt;
  Timer? _busyElapsedTicker;

  void _setBusyPhase(String phase) {
    if (!mounted) {
      return;
    }
    setState(() => _busyPhase = phase);
  }

  void _startBusyUi(String fileName) {
    _busyElapsedTicker?.cancel();
    _busyStartedAt = DateTime.now();
    _busyFileName = fileName;
    _busyPhase = 'Preparing…';
    if (mounted) {
      setState(() {});
    }
    _busyElapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_busy) {
        return;
      }
      setState(() {});
    });
  }

  void _stopBusyUi() {
    _busyElapsedTicker?.cancel();
    _busyElapsedTicker = null;
    _busyStartedAt = null;
    _busyFileName = null;
    _busyPhase = '';
  }

  String _elapsedLabel() {
    final start = _busyStartedAt;
    if (start == null) {
      return '';
    }
    final d = DateTime.now().difference(start);
    if (d.inMinutes >= 1) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${d.inSeconds}s';
  }

  Future<bool> _restoreLocalFromBackup(String username, Map<String, dynamic> local) async {
    final storage = ref.read(sessionStorageProvider);
    var changed = false;

    final movieLists = parseLocalMovieLists(local);
    if (movieLists != null) {
      await storage.write(
        key: StorageKeys.customMovieLists(username),
        value: movieLists.toJsonString(),
      );
      changed = true;
    }

    final tvLists = parseLocalTvLists(local);
    if (tvLists != null) {
      await storage.write(
        key: StorageKeys.customTvLists(username),
        value: tvLists.toJsonString(),
      );
      changed = true;
    }

    final people = parseLocalFavoritePeople(local);
    if (people != null) {
      await storage.write(
        key: StorageKeys.favoritePeople(username),
        value: people.toJsonString(),
      );
      changed = true;
    }

    return changed;
  }

  Future<void> _exportBackup() async {
    final auth = ref.read(authControllerProvider).asData?.value;
    final username = auth?.session?.username;
    if (username == null || username.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to export a backup.')),
        );
      }
      return;
    }

    setState(() {
      _busy = true;
      _exporting = true;
      _lastExportResult = null;
    });
    final fileName = defaultCulturBackupFileNameV3();
    _startBusyUi(fileName);
    try {
      final client = ref.read(apiClientProvider);

      _setBusyPhase('Exporting full library from server…');
      final out = await client.postJson(
        '/backend/export/cultur-backup-v3',
        data: {'username': username},
        receiveTimeout: const Duration(minutes: 5),
      );
      if (!mounted) {
        return;
      }
      final documentRaw = out['document'];
      if (documentRaw is! Map) {
        throw const FormatException('Export response missing document object.');
      }
      final document = Map<String, dynamic>.from(documentRaw.cast<String, dynamic>());

      _setBusyPhase('Reading data stored on this device…');
      final movieLists = await ref.read(customListsControllerProvider).load(username);
      final tvLists = await ref.read(customTvListsControllerProvider).load(username);
      final favoritePeople =
          await ref.read(favoritePeopleControllerProvider).loadFavoritePeople(username);
      document['local'] = buildLocalBackupAppendix(
        movieLists: movieLists,
        tvLists: tvLists,
        favoritePeople: favoritePeople,
      );

      _setBusyPhase('Saving JSON file…');
      final encoder = const JsonEncoder.withIndent('  ');
      final bytes = utf8.encode(encoder.convert(document));

      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup JSON',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (!mounted) {
        return;
      }

      final summary = out['summary'];
      final trackingN = summary is Map ? summary['tracking'] : null;
      final watchedN = summary is Map ? summary['tvEpisodeWatches'] : null;
      final followsN = summary is Map ? summary['follows'] : null;
      final listsN = summary is Map ? summary['collectionLists'] : null;
      final msg = out['message']?.toString() ?? 'Export complete.';
      setState(() {
        final buf = StringBuffer()
          ..writeln(msg)
          ..writeln(
            'Server — tracking: $trackingN · TV episode watches: $watchedN · '
            'follows: $followsN · lists: $listsN',
          )
          ..writeln(
            'Device appendix — movie lists: ${movieLists.lists.length} · TV lists: ${tvLists.lists.length} · '
            'favorite people: ${favoritePeople.people.length}',
          );
        if (savedPath != null && savedPath.trim().isNotEmpty) {
          buf.writeln('Saved to: $savedPath');
        } else {
          buf.writeln(
            'File save was cancelled or the platform did not return a path. '
            'On mobile, use Share if the system offered it.',
          );
        }
        _lastExportResult = buf.toString();
      });
      if (savedPath != null && savedPath.trim().isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup exported.')),
        );
      }
    } catch (e, st) {
      debugPrint('export failed: $e\n$st');
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, e, prefix: 'Export failed:');
    } finally {
      _stopBusyUi();
      if (mounted) {
        setState(() {
          _busy = false;
          _exporting = false;
        });
      }
    }
  }

  Future<void> _pickAndImport() async {
    final auth = ref.read(authControllerProvider).asData?.value;
    final username = auth?.session?.username;
    if (username == null || username.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to import a backup.')),
        );
      }
      return;
    }

    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'json', 'avabackup'],
      withData: true,
    );
    if (pick == null || pick.files.isEmpty) {
      return;
    }
    final file = pick.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file bytes. Try a smaller file or another picker.')),
        );
      }
      return;
    }

    setState(() {
      _busy = true;
      _exporting = false;
      _lastResult = null;
    });
    _startBusyUi(file.name);
    try {
      _setBusyPhase('Reading JSON…');
      final text = utf8.decode(bytes);
      final decodedRaw = jsonDecode(text);
      final Map<String, dynamic> decoded;
      if (decodedRaw is Map<String, dynamic>) {
        decoded = decodedRaw;
      } else if (decodedRaw is List) {
        final list = List<dynamic>.from(decodedRaw);
        if (list.isNotEmpty && list.first is Map) {
          final first = Map<String, dynamic>.from(list.first as Map);
          final hasSeasons = first.containsKey('seasons');
          decoded = hasSeasons ? {'shows': list} : {'movies': list};
        } else {
          decoded = {'movies': list};
        }
      } else {
        throw const FormatException(
          'Backup must be a JSON object (Cultur full backup or AVA export) or a JSON array of movie or show rows.',
        );
      }

      final localSection = extractLocalBackupSection(decoded);
      final client = ref.read(apiClientProvider);
      Map<String, dynamic> out;
      if (isCulturFullBackup(decoded)) {
        _setBusyPhase(
          'Restoring Cultur backup on server (tracking, lists, follows, TV data)…',
        );
        out = await client.postJson(
          '/backend/import/cultur-backup-v3',
          data: {
            'username': username,
            'document': decoded,
            'skipExistingTracking': false,
            'importLegacyAva': decoded['format']?.toString() == culturBackupFormatV2,
          },
          receiveTimeout: const Duration(minutes: 15),
          sendTimeout: const Duration(minutes: 5),
        );
      } else {
        final importPayload = extractAvaImportPayload(decoded);
        final moviesN = (importPayload['movies'] is List) ? (importPayload['movies'] as List).length : 0;
        final showsN = (importPayload['shows'] is List) ? (importPayload['shows'] as List).length : 0;
        final epsN = (importPayload['episodes'] is List) ? (importPayload['episodes'] as List).length : 0;
        _setBusyPhase(
          'Sending legacy AVA backup (~$moviesN movies, ~$showsN shows, ~$epsN episode rows). '
          'TMDB lookups can take several minutes — keep this screen open.',
        );
        out = await client.postJson(
          '/backend/import/ava-backup-v1',
          data: {
            'username': username,
            'skipExistingTracking': false,
            'backup': importPayload,
          },
          receiveTimeout: const Duration(minutes: 15),
          sendTimeout: const Duration(minutes: 5),
        );
      }
      if (!mounted) {
        return;
      }
      var restoredLocal = false;
      if (localSection != null) {
        _setBusyPhase('Restoring lists and favorites on this device…');
        restoredLocal = await _restoreLocalFromBackup(username, localSection);
      } else if (!isCulturFullBackup(decoded)) {
        _setBusyPhase('Merging custom lists on this device…');
        final movieListsRaw = out['importedMovieLists'];
        final tvListsRaw = out['importedTvLists'];
        if (movieListsRaw is List<dynamic> && movieListsRaw.isNotEmpty) {
          await ref.read(customListsControllerProvider).mergeImportedLists(username, movieListsRaw);
        }
        if (tvListsRaw is List<dynamic> && tvListsRaw.isNotEmpty) {
          await ref.read(customTvListsControllerProvider).mergeImportedTvLists(username, tvListsRaw);
        }
      }
      if (!mounted) {
        return;
      }
      _invalidateLibraryAfterImport();
      if (restoredLocal) {
        ref.invalidate(favoritePeopleProvider);
      }
      final msg = out['message']?.toString() ?? 'Done';
      final importWarnings = _readImportWarnings(out, isCulturFullBackup(decoded));
      setState(() {
        final buf = StringBuffer()..writeln(msg);
        if (isCulturFullBackup(decoded)) {
          final summary = out['summary'];
          if (summary is Map) {
            buf.writeln(
              'Tracking: ${summary['trackingWritten']} · TV watches: ${summary['tvEpisodeWatchesWritten']} · '
              'Collections: ${summary['collectionsSynced']} · Follows: ${summary['followsWritten']}',
            );
          }
        } else {
          buf
            ..writeln('Movies: ${out['moviesImported']} · Shows: ${out['showsImported']}')
            ..writeln('Episode marks: ${out['episodeWatchesWritten']}');
        }
        if (restoredLocal) {
          buf.writeln('Device lists and favorites were restored from the backup file.');
        }
        if (importWarnings.isNotEmpty) {
          buf
            ..writeln()
            ..writeln('Issues (${importWarnings.length}):');
          for (final w in importWarnings) {
            buf.writeln('• $w');
          }
        }
        _lastResult = buf.toString();
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            importWarnings.isEmpty
                ? 'Import completed.'
                : 'Import finished with ${importWarnings.length} reported issue(s). Check the summary below.',
          ),
          duration: Duration(seconds: importWarnings.isEmpty ? 4 : 10),
        ),
      );
    } catch (e, st) {
      debugPrint('import failed: $e\n$st');
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, e, prefix: 'Import failed:');
    } finally {
      _stopBusyUi();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  List<String> _readImportWarnings(Map<String, dynamic> out, bool culturBackup) {
    final raw = culturBackup ? out['warnings'] : out['importWarnings'];
    if (raw is! List<dynamic>) {
      return const [];
    }
    return raw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }

  void _invalidateLibraryAfterImport() {
    for (final scope in LibraryMediaScope.values) {
      ref.invalidate(libraryTrackingForScopeProvider(scope));
    }
    ref.invalidate(customMovieListsProvider);
    ref.invalidate(customTvListsProvider);
    ref.invalidate(tvWatchedEpisodesLibraryProvider);
    ref.invalidate(favoritePeopleProvider);
  }

  @override
  void dispose() {
    _busyElapsedTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _busy && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _exporting
                    ? 'Export still running — wait until it finishes.'
                    : 'Import still running — wait until it finishes or you may lose the result.',
              ),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: CulturAppBar(
          backEnabled: !_busy,
          onBack: () => context.pop(),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Export',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Saves a Cultur backup v3 JSON file: tracking (all media), flags, loans, collections, '
              'follows, and TV progress on the server, plus an optional device appendix for legacy '
              'local lists. Default name: cultur-backup-v3-YYYY-MM-DD.json.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _exportBackup,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(_exporting ? 'Exporting…' : 'Export JSON backup'),
            ),
            if (_lastExportResult != null) ...[
              const SizedBox(height: 16),
              Text('Export result', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SelectableText(_lastExportResult!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 32),
            Text(
              'Import',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a Cultur backup (`cultur-backup-v3` or `cultur-backup-v2`) or a legacy SeriesGuide / '
              'AVA file. Cultur backups restore the full server library; v2/v3 files may also include a '
              '`local` section for device-only lists. AVA imports are TMDB movies/TV only.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _exporting ? 'Export in progress' : 'Import in progress',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (_busyStartedAt != null)
                            Text(
                              _elapsedLabel(),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.surface,
                        ),
                      ),
                      if (_busyFileName != null && _busyFileName!.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          _busyFileName!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (_busyPhase.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _busyPhase,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _pickAndImport,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(_busy ? 'Importing…' : 'Choose file & import'),
            ),
            if (_lastResult != null) ...[
              const SizedBox(height: 24),
              Text('Result', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_lastResult!.contains('Issues / skipped rows')) ...[
                Card(
                  elevation: 0,
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.onErrorContainer,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Some rows were skipped or could not be matched on TMDB. '
                            'Read the bullet list in the text below.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SelectableText(_lastResult!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
