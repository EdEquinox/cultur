part of '../library/library_external_import_page.dart';

class _ProfileBggImportCard extends ConsumerStatefulWidget {
  const _ProfileBggImportCard({required this.theme, required this.username});

  final ThemeData theme;
  final String username;

  @override
  ConsumerState<_ProfileBggImportCard> createState() => _ProfileBggImportCardState();
}

class _ProfileBggImportCardState extends ConsumerState<_ProfileBggImportCard> {
  late final TextEditingController _bggUsernameController;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _bggUsernameController = TextEditingController();
    Future.microtask(_loadSavedBggUsername);
  }

  @override
  void dispose() {
    _bggUsernameController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedBggUsername() async {
    final storage = ref.read(sessionStorageProvider);
    final saved = await storage.read(key: StorageKeys.bggUsername(widget.username));
    if (!mounted || saved == null || saved.trim().isEmpty) {
      return;
    }
    _bggUsernameController.text = saved.trim();
    setState(() {});
  }

  Future<void> _saveBggUsername(String value) {
    return ref.read(sessionStorageProvider).write(
          key: StorageKeys.bggUsername(widget.username),
          value: value.trim(),
        );
  }

  Future<void> _importCollection() async {
    final bggUsername = _bggUsernameController.text.trim();
    if (bggUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your BoardGameGeek username first.')),
      );
      return;
    }

    setState(() => _isImporting = true);
    try {
      await _saveBggUsername(bggUsername);
      final payload = await ref.read(apiClientProvider).postJson(
            '/backend/import/bgg-collection',
            data: {
              'username': widget.username,
              'bggUsername': bggUsername,
            },
            receiveTimeout: const Duration(minutes: 15),
            sendTimeout: const Duration(minutes: 2),
          );
      final imported = (payload['imported'] as num?)?.toInt() ?? 0;
      final skipped = (payload['skipped'] as num?)?.toInt() ?? 0;
      final total = (payload['total'] as num?)?.toInt();
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.boardgame));
      ref.invalidate(customBoardgameListsProvider);
      invalidateBoardgamesHomeCaches(ref, username: widget.username);
      if (!mounted) {
        return;
      }
      final totalLabel = total != null && total > 0 ? ' of $total' : '';
      final skippedLabel = skipped > 0 ? ' · $skipped skipped' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported $imported$totalLabel board games from BGG$skippedLabel.',
          ),
          duration: Duration(seconds: skipped > 0 ? 8 : 4),
        ),
      );
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error, prefix: 'BGG import failed:');
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
            Text('BoardGameGeek import', style: CulturCatalogTypography.listTitle(widget.theme)),
            const SizedBox(height: 4),
            Text(
              'Imports your BGG owned, wishlist, want-to-play, want-to-buy, and rated games '
              'into Later, Buy, and Owned. BGG rate limits can make this take several minutes.',
              style: CulturCatalogTypography.listMeta(widget.theme, scheme),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bggUsernameController,
              decoration: const InputDecoration(
                labelText: 'BGG username',
                hintText: 'Your profile name on boardgamegeek.com',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _isImporting ? null : _importCollection(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isImporting ? null : _importCollection,
                icon: _isImporting
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(_isImporting ? 'Importing…' : 'Import from BGG'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
