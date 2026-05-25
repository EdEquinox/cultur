part of 'profile_page.dart';

enum _LibraryPurgeCategory {
  movie('movie', 'Movies', 'Tracking and custom movie lists'),
  tv('tv', 'TV shows', 'Tracking, episode marks, and custom TV lists'),
  game('game', 'Games', 'Tracking, custom game lists, and favorite companies'),
  boardgame('boardgame', 'Board games', 'Tracking and custom board game lists'),
  book('book', 'Books', 'Tracking, custom book lists, and favorite publishers'),
  music('music', 'Albums', 'Tracking, custom album lists, and followed artists');

  const _LibraryPurgeCategory(this.apiValue, this.title, this.subtitle);

  final String apiValue;
  final String title;
  final String subtitle;

  LibraryMediaScope get scope => switch (this) {
        _LibraryPurgeCategory.movie => LibraryMediaScope.movie,
        _LibraryPurgeCategory.tv => LibraryMediaScope.tv,
        _LibraryPurgeCategory.game => LibraryMediaScope.game,
        _LibraryPurgeCategory.boardgame => LibraryMediaScope.boardgame,
        _LibraryPurgeCategory.book => LibraryMediaScope.book,
        _LibraryPurgeCategory.music => LibraryMediaScope.music,
      };
}

extension _ProfilePurgeLibrary on _ProfilePageState {
  Future<Set<_LibraryPurgeCategory>?> _pickPurgeCategories() async {
    final theme = Theme.of(context);
    final selected = <_LibraryPurgeCategory>{
      for (final category in _LibraryPurgeCategory.values) category,
    };

    return showDialog<Set<_LibraryPurgeCategory>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allSelected = selected.length == _LibraryPurgeCategory.values.length;
          return AlertDialog(
            title: const Text('Delete library data'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose which categories to remove from the server and this device. '
                    'Your account stays signed in.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        setDialogState(() {
                          if (allSelected) {
                            selected.clear();
                          } else {
                            selected.addAll(_LibraryPurgeCategory.values);
                          }
                        });
                      },
                      child: Text(allSelected ? 'Clear all' : 'Select all'),
                    ),
                  ),
                  for (final category in _LibraryPurgeCategory.values)
                    CheckboxListTile(
                      value: selected.contains(category),
                      onChanged: (checked) {
                        setDialogState(() {
                          if (checked == true) {
                            selected.add(category);
                          } else {
                            selected.remove(category);
                          }
                        });
                      },
                      title: Text(category.title),
                      subtitle: Text(
                        category.subtitle,
                        style: theme.textTheme.bodySmall,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  if (selected.contains(_LibraryPurgeCategory.movie) ||
                      selected.contains(_LibraryPurgeCategory.tv))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Also clears favorite people stored on this device.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, Set.of(selected)),
                child: const Text('Delete selected'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _invalidateLibraryCachesForCategories(
    String username,
    Set<_LibraryPurgeCategory> categories,
  ) {
    final scopes = categories.map((c) => c.scope).toSet();
    if (scopes.contains(LibraryMediaScope.movie)) {
      ref.invalidate(movieHomeShelvesProvider);
      ref.invalidate(movieSearchTrackingProvider(username));
      ref.invalidate(customMovieListsProvider);
    }
    if (scopes.contains(LibraryMediaScope.tv)) {
      ref.invalidate(tvHomeShelvesProvider(username));
      ref.invalidate(tvSearchTrackingProvider(username));
      ref.invalidate(nextToWatchShelfProvider(username));
      ref.invalidate(tvNextToWatchShelfProvider(username));
      ref.invalidate(customTvListsProvider);
    }
    if (scopes.contains(LibraryMediaScope.game)) {
      ref.invalidate(gameSearchTrackingProvider(username));
      ref.invalidate(customGameListsProvider);
      ref.invalidate(favoriteCompaniesProvider);
    }
    if (scopes.contains(LibraryMediaScope.boardgame)) {
      ref.invalidate(customBoardgameListsProvider);
    }
    if (scopes.contains(LibraryMediaScope.book)) {
      ref.invalidate(bookSearchTrackingProvider(username));
      ref.invalidate(customBookListsProvider);
      ref.invalidate(favoritePublishersProvider);
    }
    if (scopes.contains(LibraryMediaScope.music)) {
      invalidateAlbumsHomeCaches(ref, username: username);
      ref.invalidate(customMusicListsProvider);
      ref.invalidate(followedMusicArtistsProvider(username));
    }
    if (scopes.contains(LibraryMediaScope.movie) || scopes.contains(LibraryMediaScope.tv)) {
      ref.invalidate(favoritePeopleProvider);
    }
    for (final scope in scopes) {
      ref.invalidate(libraryTrackingForScopeProvider(scope));
    }
  }

  Future<void> _purgeLocalLibraryData(
    SessionStorage storage,
    String username,
    Set<_LibraryPurgeCategory> categories,
  ) async {
    if (categories.contains(_LibraryPurgeCategory.movie)) {
      await storage.delete(key: StorageKeys.customMovieLists(username));
    }
    if (categories.contains(_LibraryPurgeCategory.tv)) {
      await storage.delete(key: StorageKeys.customTvLists(username));
    }
    if (categories.contains(_LibraryPurgeCategory.game)) {
      await storage.delete(key: StorageKeys.customGameLists(username));
      await storage.delete(key: StorageKeys.favoriteCompanies(username));
    }
    if (categories.contains(_LibraryPurgeCategory.boardgame)) {
      await storage.delete(key: StorageKeys.customBoardgameLists(username));
    }
    if (categories.contains(_LibraryPurgeCategory.book)) {
      await storage.delete(key: StorageKeys.customBookLists(username));
      await storage.delete(key: StorageKeys.favoritePublishers(username));
    }
    if (categories.contains(_LibraryPurgeCategory.music)) {
      await storage.delete(key: StorageKeys.customMusicLists(username));
    }
    if (categories.contains(_LibraryPurgeCategory.movie) ||
        categories.contains(_LibraryPurgeCategory.tv)) {
      await storage.delete(key: StorageKeys.favoritePeople(username));
    }
  }

  Future<void> _confirmAndPurgeLibraryData() async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }

    final categories = await _pickPurgeCategories();
    if (categories == null || categories.isEmpty || !mounted) {
      return;
    }

    try {
      await ref.read(apiClientProvider).postJson(
            '/backend/user/purge-library',
            data: {
              'username': username,
              'mediaTypes': categories.map((c) => c.apiValue).toList(),
            },
          );
      final storage = ref.read(sessionStorageProvider);
      await _purgeLocalLibraryData(storage, username, categories);
      _invalidateLibraryCachesForCategories(username, categories);
      if (mounted) {
        final labels = categories.map((c) => c.title).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed library data for: $labels.')),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, e, prefix: 'Could not delete data:');
    }
  }
}
