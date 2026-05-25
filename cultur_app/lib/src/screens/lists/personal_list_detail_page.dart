import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/library/library_tracking_filter_model.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list.dart';
import 'package:yamtrack/src/models/lists/tv_custom_list_item.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/models/library/library_enums.dart';
import 'package:yamtrack/src/screens/library/library_navigation.dart';
import 'package:yamtrack/src/screens/library/widgets/custom_list_movie_tile.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/screens/library/widgets/library_search_filter_header.dart';
import 'package:yamtrack/src/screens/library/widgets/library_tracking_filter_options.dart';
import 'package:yamtrack/src/screens/library/widgets/tv_custom_list_item_tile.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/library_item_search.dart';
import 'package:yamtrack/src/utils/library_utils.dart';

class PersonalListDetailPage extends ConsumerStatefulWidget {
  const PersonalListDetailPage({
    required this.listId,
    required this.mediaScope,
    super.key,
  });

  final String listId;
  final LibraryMediaScope mediaScope;

  @override
  ConsumerState<PersonalListDetailPage> createState() => _PersonalListDetailPageState();
}

class _PersonalListDetailPageState extends ConsumerState<PersonalListDetailPage> {
  bool _entryEditMode = false;
  final LibraryTrackingFilterModel _listFilterModel = LibraryTrackingFilterModel();
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _searchQuery => _searchController.text;

  Widget _personalListHeader() {
    return LibrarySearchFilterHeader(
      searchController: _searchController,
      searchHint: switch (widget.mediaScope) {
        LibraryMediaScope.tv => 'Search series, seasons, episodes…',
        LibraryMediaScope.game => 'Search games in this list…',
        LibraryMediaScope.boardgame => 'Search board games in this list…',
        LibraryMediaScope.music => 'Search albums in this list…',
        LibraryMediaScope.book => 'Search books in this list…',
        _ => 'Search movies in this list…',
      },
      onSearchChanged: (_) => setState(() {}),
      filterOptions: buildLibraryTrackingFilterOptions(
        context: context,
        surface: LibraryFilterSurface.personalList,
        trackingCollectionKind: null,
        mediaScope: widget.mediaScope,
        model: _listFilterModel,
        onModelChanged: (_) => setState(() {}),
      ),
      onClearAll: () {
        _listFilterModel.clearAll();
        setState(() {});
      },
    );
  }

  @override
  void didUpdateWidget(PersonalListDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listId != widget.listId) {
      _entryEditMode = false;
    }
  }

  String? get _username =>
      ref.read(authControllerProvider).asData?.value.session?.username;

  Future<String?> _askListName(String title, String hint, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'List name',
              hintText: hint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final t = controller.text.trim();
                if (t.isEmpty) {
                  return;
                }
                Navigator.pop(ctx, t);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _renameMovieList(CustomMovieList list) async {
    final u = _username;
    if (u == null || u.isEmpty || !mounted) {
      return;
    }
    final name = await _askListName('Rename list', 'List name', list.name);
    if (!mounted || name == null || name == list.name) {
      return;
    }
    await ref.read(customListsControllerProvider).renameList(u, list.id, name);
    ref.invalidate(customMovieListsProvider);
  }

  Future<void> _renameMusicList(CustomMovieList list) async {
    final u = _username;
    if (u == null || u.isEmpty || !mounted) {
      return;
    }
    final name = await _askListName('Rename list', 'List name', list.name);
    if (!mounted || name == null || name == list.name) {
      return;
    }
    await ref.read(customMusicListsControllerProvider).renameList(u, list.id, name);
    ref.invalidate(customMusicListsProvider);
  }

  Future<void> _renameGameList(CustomMovieList list) async {
    final u = _username;
    if (u == null || u.isEmpty || !mounted) {
      return;
    }
    final name = await _askListName('Rename list', 'List name', list.name);
    if (!mounted || name == null || name == list.name) {
      return;
    }
    await ref.read(customGameListsControllerProvider).renameList(u, list.id, name);
    ref.invalidate(customGameListsProvider);
  }

  Future<void> _renameTvList(TvCustomList list) async {
    if (BuiltInTvLists.isBuiltIn(list.id)) {
      return;
    }
    final u = _username;
    if (u == null || u.isEmpty || !mounted) {
      return;
    }
    final name = await _askListName('Rename list', 'List name', list.name);
    if (!mounted || name == null || name == list.name) {
      return;
    }
    await ref.read(customTvListsControllerProvider).renameList(u, list.id, name);
    ref.invalidate(customTvListsProvider);
  }

  Future<void> _confirmDeleteMovieList(CustomMovieList list) async {
    if (BuiltInMovieLists.isBuiltIn(list.id)) {
      return;
    }
    final u = _username;
    if (u == null || u.isEmpty || !mounted) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete list'),
        content: Text('Delete "${list.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    await ref.read(customListsControllerProvider).deleteList(u, list.id);
    ref.invalidate(customMovieListsProvider);
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _confirmDeleteMusicList(CustomMovieList list) async {
    if (BuiltInMusicLists.isBuiltIn(list.id)) {
      return;
    }
    final u = _username;
    if (u == null || u.isEmpty || !mounted) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete list'),
        content: Text('Delete "${list.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    await ref.read(customMusicListsControllerProvider).deleteList(u, list.id);
    ref.invalidate(customMusicListsProvider);
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _confirmDeleteGameList(CustomMovieList list) async {
    if (BuiltInGameLists.isBuiltIn(list.id)) {
      return;
    }
    final u = _username;
    if (u == null || u.isEmpty || !mounted) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete list'),
        content: Text('Delete "${list.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    await ref.read(customGameListsControllerProvider).deleteList(u, list.id);
    ref.invalidate(customGameListsProvider);
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _confirmDeleteTvList(TvCustomList list) async {
    if (BuiltInTvLists.isBuiltIn(list.id)) {
      return;
    }
    final u = _username;
    if (u == null || u.isEmpty || !mounted) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete list'),
        content: Text('Delete "${list.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    await ref.read(customTvListsControllerProvider).deleteList(u, list.id);
    ref.invalidate(customTvListsProvider);
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _removeMovieItem(String listId, CatalogItem item) async {
    final u = _username;
    if (u == null || u.isEmpty) {
      return;
    }
    if (BuiltInMovieLists.isPendingImportsList(listId)) {
      return;
    }
    await ref.read(customListsControllerProvider).toggleItem(
          username: u,
          listId: listId,
          item: item,
        );
    ref.invalidate(customMovieListsProvider);
  }

  Future<void> _removeMusicItem(String listId, CatalogItem item) async {
    final u = _username;
    if (u == null || u.isEmpty) {
      return;
    }
    if (BuiltInMusicLists.isPendingImportsList(listId)) {
      return;
    }
    if (listId == BuiltInMusicLists.priorityListId) {
      await ref.read(trackingMutationControllerProvider).togglePriority(
            username: u,
            media: item,
          );
    } else {
      await ref.read(customMusicListsControllerProvider).toggleItem(
            username: u,
            listId: listId,
            item: item,
          );
    }
    ref.invalidate(customMusicListsProvider);
    ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.music));
  }

  Future<void> _removeGameItem(String listId, CatalogItem item) async {
    final u = _username;
    if (u == null || u.isEmpty) {
      return;
    }
    final isBoardgame = widget.mediaScope == LibraryMediaScope.boardgame;
    final isBook = widget.mediaScope == LibraryMediaScope.book;
    if (widget.mediaScope == LibraryMediaScope.game &&
        BuiltInGameLists.isPendingImportsList(listId)) {
      return;
    }
    if (isBook && BuiltInBookLists.isPendingImportsList(listId)) {
      return;
    }
    final priorityId = isBook
        ? BuiltInBookLists.priorityListId
        : isBoardgame
            ? BuiltInBoardgameLists.priorityListId
            : BuiltInGameLists.priorityListId;
    if (listId == priorityId) {
      await ref.read(trackingMutationControllerProvider).togglePriority(
            username: u,
            media: item,
          );
    } else if (isBook) {
      await ref.read(customBookListsControllerProvider).toggleItem(
            username: u,
            listId: listId,
            item: item,
          );
    } else if (isBoardgame) {
      await ref.read(customBoardgameListsControllerProvider).toggleItem(
            username: u,
            listId: listId,
            item: item,
          );
    } else {
      await ref.read(customGameListsControllerProvider).toggleItem(
            username: u,
            listId: listId,
            item: item,
          );
    }
    ref.invalidate(
      isBook
          ? customBookListsProvider
          : isBoardgame
              ? customBoardgameListsProvider
              : customGameListsProvider,
    );
    ref.invalidate(
      libraryTrackingForScopeProvider(
        isBook
            ? LibraryMediaScope.book
            : isBoardgame
                ? LibraryMediaScope.boardgame
                : LibraryMediaScope.game,
      ),
    );
  }

  Future<void> _removeTvItem(String listId, TvCustomListItem item) async {
    final u = _username;
    if (u == null || u.isEmpty) {
      return;
    }
    await ref.read(customTvListsControllerProvider).toggleItem(
          username: u,
          listId: listId,
          item: item,
        );
    ref.invalidate(customTvListsProvider);
  }

  List<Widget> _actionsForTvList(TvCustomList list) {
    return [
      if (list.items.isNotEmpty || _entryEditMode)
        IconButton(
          icon: Icon(_entryEditMode ? Icons.check : Icons.playlist_remove_outlined),
          tooltip: _entryEditMode ? 'Done' : 'Remove entries',
          onPressed: () {
            setState(() {
              if (list.items.isEmpty) {
                _entryEditMode = false;
              } else {
                _entryEditMode = !_entryEditMode;
              }
            });
          },
        ),
      PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'rename') {
            await _renameTvList(list);
          }
          if (!mounted) {
            return;
          }
          if (v == 'delete') {
            await _confirmDeleteTvList(list);
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename list')),
          if (!BuiltInTvLists.isBuiltIn(list.id))
            const PopupMenuItem(value: 'delete', child: Text('Delete list')),
        ],
      ),
    ];
  }

  List<Widget> _actionsForScopedCatalogList(
    CustomMovieList list, {
    required Future<void> Function(CustomMovieList) onRename,
    required Future<void> Function(CustomMovieList) onDelete,
    required bool Function(String listId) isBuiltIn,
  }) {
    return [
      if (list.items.isNotEmpty || _entryEditMode)
        IconButton(
          icon: Icon(_entryEditMode ? Icons.check : Icons.playlist_remove_outlined),
          tooltip: _entryEditMode ? 'Done' : 'Remove entries',
          onPressed: () {
            setState(() {
              if (list.items.isEmpty) {
                _entryEditMode = false;
              } else {
                _entryEditMode = !_entryEditMode;
              }
            });
          },
        ),
      PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'rename') {
            await onRename(list);
          }
          if (!mounted) {
            return;
          }
          if (v == 'delete') {
            await onDelete(list);
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename list')),
          if (!isBuiltIn(list.id))
            const PopupMenuItem(value: 'delete', child: Text('Delete list')),
        ],
      ),
    ];
  }

  List<Widget> _actionsForGameList(CustomMovieList list) {
    return _actionsForScopedCatalogList(
      list,
      onRename: _renameGameList,
      onDelete: _confirmDeleteGameList,
      isBuiltIn: BuiltInGameLists.isBuiltIn,
    );
  }

  List<Widget> _actionsForMusicList(CustomMovieList list) {
    return _actionsForScopedCatalogList(
      list,
      onRename: _renameMusicList,
      onDelete: _confirmDeleteMusicList,
      isBuiltIn: BuiltInMusicLists.isBuiltIn,
    );
  }

  List<Widget> _actionsForMovieList(CustomMovieList list) {
    return [
      if (list.items.isNotEmpty || _entryEditMode)
        IconButton(
          icon: Icon(_entryEditMode ? Icons.check : Icons.playlist_remove_outlined),
          tooltip: _entryEditMode ? 'Done' : 'Remove entries',
          onPressed: () {
            setState(() {
              if (list.items.isEmpty) {
                _entryEditMode = false;
              } else {
                _entryEditMode = !_entryEditMode;
              }
            });
          },
        ),
      PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'rename') {
            await _renameMovieList(list);
          }
          if (!mounted) {
            return;
          }
          if (v == 'delete') {
            await _confirmDeleteMovieList(list);
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename list')),
          if (!BuiltInMovieLists.isBuiltIn(list.id))
            const PopupMenuItem(value: 'delete', child: Text('Delete list')),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaScope == LibraryMediaScope.tv) {
      final lists = ref.watch(customTvListsProvider);
      return lists.when(
        loading: () => Scaffold(
          extendBody: true,
          appBar: const CulturAppBar(),
          body: const Center(child: CircularProgressIndicator()),
          bottomNavigationBar: FloatingLibraryNav(
            currentDestination: FloatingLibraryDestination.personalLists,
            mediaScope: widget.mediaScope,
          ),
        ),
        error: (error, stackTrace) => Scaffold(
          extendBody: true,
          appBar: const CulturAppBar(),
          body: ErrorState(
            error: error,
            onRetry: () => ref.invalidate(customTvListsProvider),
          ),
          bottomNavigationBar: FloatingLibraryNav(
            currentDestination: FloatingLibraryDestination.personalLists,
            mediaScope: widget.mediaScope,
          ),
        ),
        data: (data) {
          TvCustomList? list;
          for (final entry in data.lists) {
            if (entry.id == widget.listId) {
              list = entry;
              break;
            }
          }
          if (list == null) {
            return Scaffold(
              extendBody: true,
              appBar: const CulturAppBar(),
              body: const EmptyState(
                title: 'List not found',
                message: 'This custom list no longer exists.',
                icon: Icons.list_alt_outlined,
              ),
              bottomNavigationBar: FloatingLibraryNav(
                currentDestination: FloatingLibraryDestination.personalLists,
                mediaScope: widget.mediaScope,
              ),
            );
          }
          final resolvedList = list;
          return Scaffold(
            extendBody: true,
            appBar: CulturAppBar(
              additionalActions: _actionsForTvList(resolvedList),
            ),
            body: resolvedList.items.isEmpty
                ? EmptyState(
                    title: resolvedList.name,
                    message: BuiltInTvLists.isPendingImportsList(resolvedList.id)
                        ? 'After an AVA backup import, series without a TMDB match are listed here. '
                            'Open a title and tap Search catalog to link it.'
                        : 'Use the Lists action on a series, season, or episode page to add entries.',
                    icon: Icons.tv_outlined,
                  )
                : Builder(
                    builder: (context) {
                      final filtered = resolvedList.items
                          .where((e) => tvCustomListItemMatchesLibrarySearch(e, _searchQuery))
                          .where(_listFilterModel.passesTvCustomListRow)
                          .toList();
                      if (filtered.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 16, librarySearchHorizontalInset, 132),
                          child: ListView(
                            children: [
                              _personalListHeader(),
                              const SizedBox(height: 24),
                              const EmptyState(
                                title: 'No matches',
                                message: 'Nothing matches the current filters.',
                                icon: Icons.filter_alt_outlined,
                              ),
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 16, librarySearchHorizontalInset, 132),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _personalListHeader(),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  return TvCustomListItemTile(
                                    item: item,
                                    showRemoveButton: _entryEditMode,
                                    onRemove: _entryEditMode
                                        ? () => _removeTvItem(resolvedList.id, item)
                                        : null,
                                    onTap: _entryEditMode
                                        ? null
                                        : () => openTvCustomListItem(context, item),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            bottomNavigationBar: FloatingLibraryNav(
              currentDestination: FloatingLibraryDestination.personalLists,
              mediaScope: widget.mediaScope,
            ),
          );
        },
      );
    }

    if (widget.mediaScope == LibraryMediaScope.music) {
      final lists = ref.watch(customMusicListsProvider);
      return lists.when(
        loading: () => Scaffold(
          extendBody: true,
          appBar: const CulturAppBar(),
          body: const Center(child: CircularProgressIndicator()),
          bottomNavigationBar: FloatingLibraryNav(
            currentDestination: FloatingLibraryDestination.personalLists,
            mediaScope: widget.mediaScope,
          ),
        ),
        error: (error, stackTrace) => Scaffold(
          extendBody: true,
          appBar: const CulturAppBar(),
          body: ErrorState(
            error: error,
            onRetry: () => ref.invalidate(customMusicListsProvider),
          ),
          bottomNavigationBar: FloatingLibraryNav(
            currentDestination: FloatingLibraryDestination.personalLists,
            mediaScope: widget.mediaScope,
          ),
        ),
        data: (data) {
          CustomMovieList? list;
          for (final entry in data.lists) {
            if (entry.id == widget.listId) {
              list = entry;
              break;
            }
          }
          if (list == null) {
            return Scaffold(
              extendBody: true,
              appBar: const CulturAppBar(),
              body: const EmptyState(
                title: 'List not found',
                message: 'This custom list no longer exists.',
                icon: Icons.list_alt_outlined,
              ),
              bottomNavigationBar: FloatingLibraryNav(
                currentDestination: FloatingLibraryDestination.personalLists,
                mediaScope: widget.mediaScope,
              ),
            );
          }
          final resolvedList = list;
          return Scaffold(
            extendBody: true,
            appBar: CulturAppBar(
              additionalActions: _actionsForMusicList(resolvedList),
            ),
            body: resolvedList.items.isEmpty
                ? EmptyState(
                    title: resolvedList.name,
                    message: BuiltInMusicLists.isBuiltIn(resolvedList.id)
                        ? (BuiltInMusicLists.isPendingImportsList(resolvedList.id)
                            ? 'After an import, albums without a MusicBrainz match are listed here. '
                                'Open one and tap Search catalog to link it.'
                            : 'Use the pin on an album page to add titles to your priority queue.')
                        : 'Use the Lists action on any album to add titles to this custom list.',
                    icon: Icons.album_outlined,
                  )
                : Builder(
                    builder: (context) {
                      final filtered = resolvedList.items
                          .where((e) => catalogItemMatchesLibrarySearch(e, _searchQuery))
                          .where(_listFilterModel.passesCatalogForUniversalFilters)
                          .toList();
                      if (filtered.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                            librarySearchHorizontalInset,
                            16,
                            librarySearchHorizontalInset,
                            132,
                          ),
                          child: ListView(
                            children: [
                              _personalListHeader(),
                              const SizedBox(height: 24),
                              const EmptyState(
                                title: 'No matches',
                                message: 'Nothing matches the current filters.',
                                icon: Icons.filter_alt_outlined,
                              ),
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          librarySearchHorizontalInset,
                          16,
                          librarySearchHorizontalInset,
                          132,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _personalListHeader(),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  return CustomListMovieTile(
                                    item: item,
                                    mediaTypeOverride: 'music',
                                    showRemoveButton: _entryEditMode,
                                    onRemove: _entryEditMode
                                        ? () => _removeMusicItem(resolvedList.id, item)
                                        : null,
                                    onTap: _entryEditMode
                                        ? null
                                        : () => context.push(catalogItemDetailPath(item)),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            bottomNavigationBar: FloatingLibraryNav(
              currentDestination: FloatingLibraryDestination.personalLists,
              mediaScope: widget.mediaScope,
            ),
          );
        },
      );
    }

    if (widget.mediaScope == LibraryMediaScope.game ||
        widget.mediaScope == LibraryMediaScope.boardgame ||
        widget.mediaScope == LibraryMediaScope.book) {
      final isBoardgame = widget.mediaScope == LibraryMediaScope.boardgame;
      final isBook = widget.mediaScope == LibraryMediaScope.book;
      final lists = ref.watch(
        isBook
            ? customBookListsProvider
            : isBoardgame
                ? customBoardgameListsProvider
                : customGameListsProvider,
      );
      return lists.when(
        loading: () => Scaffold(
          extendBody: true,
          appBar: const CulturAppBar(),
          body: const Center(child: CircularProgressIndicator()),
          bottomNavigationBar: FloatingLibraryNav(
            currentDestination: FloatingLibraryDestination.personalLists,
            mediaScope: widget.mediaScope,
          ),
        ),
        error: (error, stackTrace) => Scaffold(
          extendBody: true,
          appBar: const CulturAppBar(),
          body: ErrorState(
            error: error,
            onRetry: () => ref.invalidate(
              isBook
                  ? customBookListsProvider
                  : isBoardgame
                      ? customBoardgameListsProvider
                      : customGameListsProvider,
            ),
          ),
          bottomNavigationBar: FloatingLibraryNav(
            currentDestination: FloatingLibraryDestination.personalLists,
            mediaScope: widget.mediaScope,
          ),
        ),
        data: (data) {
          CustomMovieList? list;
          for (final entry in data.lists) {
            if (entry.id == widget.listId) {
              list = entry;
              break;
            }
          }
          if (list == null) {
            return Scaffold(
              extendBody: true,
              appBar: const CulturAppBar(),
              body: const EmptyState(
                title: 'List not found',
                message: 'This custom list no longer exists.',
                icon: Icons.list_alt_outlined,
              ),
              bottomNavigationBar: FloatingLibraryNav(
                currentDestination: FloatingLibraryDestination.personalLists,
                mediaScope: widget.mediaScope,
              ),
            );
          }
          final resolvedList = list;
          final builtIn = isBook
              ? BuiltInBookLists.isBuiltIn
              : isBoardgame
                  ? BuiltInBoardgameLists.isBuiltIn
                  : BuiltInGameLists.isBuiltIn;
          return Scaffold(
            extendBody: true,
            appBar: CulturAppBar(
              additionalActions: _actionsForGameList(resolvedList),
            ),
            body: resolvedList.items.isEmpty
                ? EmptyState(
                    title: resolvedList.name,
                    message: builtIn(resolvedList.id)
                        ? (BuiltInGameLists.isPendingImportsList(resolvedList.id) ||
                                BuiltInBookLists.isPendingImportsList(resolvedList.id))
                            ? 'After an import, titles without a catalog match are listed here. '
                                'Open one and tap Search catalog to link it.'
                            : isBook
                                ? 'Use the pin on a book page to add titles to your priority queue.'
                                : isBoardgame
                                    ? 'Use the pin on a board game page to add titles to your priority queue.'
                                    : 'Use the pin on a game page to add titles to your priority queue.'
                        : isBook
                            ? 'Use the Lists action on any book to add titles to this custom list.'
                            : isBoardgame
                                ? 'Use the Lists action on any board game to add titles to this custom list.'
                                : 'Use the Lists action on any game to add titles to this custom list.',
                    icon: isBook
                        ? Icons.menu_book_outlined
                        : isBoardgame
                            ? Icons.casino_outlined
                            : Icons.sports_esports_outlined,
                  )
                : Builder(
                    builder: (context) {
                      final filtered = resolvedList.items
                          .where((e) => catalogItemMatchesLibrarySearch(e, _searchQuery))
                          .where(_listFilterModel.passesCatalogForUniversalFilters)
                          .toList();
                      if (filtered.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(
                            librarySearchHorizontalInset,
                            16,
                            librarySearchHorizontalInset,
                            132,
                          ),
                          child: ListView(
                            children: [
                              _personalListHeader(),
                              const SizedBox(height: 24),
                              const EmptyState(
                                title: 'No matches',
                                message: 'Nothing matches the current filters.',
                                icon: Icons.filter_alt_outlined,
                              ),
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          librarySearchHorizontalInset,
                          16,
                          librarySearchHorizontalInset,
                          132,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _personalListHeader(),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  return CustomListMovieTile(
                                    item: item,
                                    showRemoveButton: _entryEditMode,
                                    onRemove: _entryEditMode
                                        ? () => _removeGameItem(resolvedList.id, item)
                                        : null,
                                    onTap: _entryEditMode
                                        ? null
                                        : () => context.push(catalogItemDetailPath(item)),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            bottomNavigationBar: FloatingLibraryNav(
              currentDestination: FloatingLibraryDestination.personalLists,
              mediaScope: widget.mediaScope,
            ),
          );
        },
      );
    }

    final lists = ref.watch(customMovieListsProvider);
    return lists.when(
      loading: () => Scaffold(
        extendBody: true,
        appBar: const CulturAppBar(),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: FloatingLibraryNav(
          currentDestination: FloatingLibraryDestination.personalLists,
          mediaScope: widget.mediaScope,
        ),
      ),
      error: (error, stackTrace) => Scaffold(
        extendBody: true,
        appBar: const CulturAppBar(),
        body: ErrorState(
          error: error,
          onRetry: () => ref.invalidate(customMovieListsProvider),
        ),
        bottomNavigationBar: FloatingLibraryNav(
          currentDestination: FloatingLibraryDestination.personalLists,
          mediaScope: widget.mediaScope,
        ),
      ),
      data: (data) {
        CustomMovieList? list;
        for (final entry in data.lists) {
          if (entry.id == widget.listId) {
            list = entry;
            break;
          }
        }
        if (list == null) {
          return Scaffold(
            extendBody: true,
            appBar: const CulturAppBar(),
            body: const EmptyState(
              title: 'List not found',
              message: 'This custom list no longer exists.',
              icon: Icons.list_alt_outlined,
            ),
            bottomNavigationBar: FloatingLibraryNav(
              currentDestination: FloatingLibraryDestination.personalLists,
              mediaScope: widget.mediaScope,
            ),
          );
        }
        final resolvedList = list;
        return Scaffold(
          extendBody: true,
          appBar: CulturAppBar(
            additionalActions: _actionsForMovieList(resolvedList),
          ),
          body: resolvedList.items.isEmpty
              ? EmptyState(
                  title: resolvedList.name,
                  message: BuiltInMovieLists.isPendingImportsList(resolvedList.id)
                      ? 'After an AVA backup import, movies without a TMDB match are listed here. '
                          'Open a title and tap Search catalog to link it.'
                      : BuiltInMovieLists.isBuiltIn(resolvedList.id)
                          ? 'Use the pins on a movie page (watchlist / recent release) to fill this queue.'
                          : 'Use the Lists action on any movie to add titles to this custom list.',
                  icon: Icons.movie_outlined,
                )
              : Builder(
                  builder: (context) {
                    final filtered = resolvedList.items
                        .where((e) => catalogItemMatchesLibrarySearch(e, _searchQuery))
                        .where(_listFilterModel.passesCatalogForUniversalFilters)
                        .toList();
                    if (filtered.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 16, librarySearchHorizontalInset, 132),
                        child: ListView(
                          children: [
                            _personalListHeader(),
                            const SizedBox(height: 24),
                            const EmptyState(
                              title: 'No matches',
                              message: 'Nothing matches the current filters.',
                              icon: Icons.filter_alt_outlined,
                            ),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(librarySearchHorizontalInset, 16, librarySearchHorizontalInset, 132),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _personalListHeader(),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return CustomListMovieTile(
                                  item: item,
                                  showRemoveButton: _entryEditMode,
                                  onRemove: _entryEditMode
                                      ? () => _removeMovieItem(resolvedList.id, item)
                                      : null,
                                  onTap: _entryEditMode
                                      ? null
                                      : () {
                                          final path = item.mediaType == 'tv'
                                              ? '/tv/${item.id}'
                                              : '/movies/${item.id}';
                                          context.push(path);
                                        },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          bottomNavigationBar: FloatingLibraryNav(
            currentDestination: FloatingLibraryDestination.personalLists,
            mediaScope: widget.mediaScope,
          ),
        );
      },
    );
  }
}
