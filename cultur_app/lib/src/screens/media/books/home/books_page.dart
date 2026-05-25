import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/catalog/catalog_category.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/books_home_providers.dart';
import 'package:yamtrack/src/providers/book_search_view_provider.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';
import 'package:yamtrack/src/screens/library/widgets/library_search_filter_header.dart';
import 'package:yamtrack/src/screens/media/books/home/book_catalog_filter_options.dart';
import 'package:yamtrack/src/screens/media/books/home/book_catalog_source.dart';
import 'package:yamtrack/src/screens/media/books/home/widgets/book_results_layout.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/screens/widgets/action_sheet_button.dart';
import 'package:yamtrack/src/screens/widgets/book_finish_reading_sheet.dart';
import 'package:yamtrack/src/screens/widgets/left_resume_sheet.dart';
import 'package:yamtrack/src/screens/widgets/movie_poster_thumb.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/collected_toggle_flow.dart';
import 'package:yamtrack/src/utils/home_categories.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';

class BooksPage extends ConsumerStatefulWidget {
  const BooksPage({
    this.initialQuery = '',
    this.initialSection = '',
    super.key,
  });

  final String initialQuery;
  final String initialSection;

  @override
  ConsumerState<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends ConsumerState<BooksPage> {
  late final TextEditingController _queryController;
  late String _submittedQuery;
  late String _submittedSection;
  late String _submittedLanguage;
  late String _submittedPublishYear;
  late String _submittedGenre;
  BookCatalogSource _submittedBookSource = BookCatalogSource.hardcover;
  final Set<String> _savingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _submittedQuery = widget.initialQuery.trim();
    _submittedSection = normalizedCatalogSection(
      CatalogBrowseKind.books,
      widget.initialSection.trim(),
    );
    _submittedLanguage = '';
    _submittedPublishYear = '';
    _submittedGenre = '';
    _queryController = TextEditingController(text: _submittedQuery);
    Future.microtask(_loadSearchSettings);
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _submittedLanguage.isNotEmpty ||
      _submittedPublishYear.isNotEmpty ||
      _submittedGenre.isNotEmpty;

  bool get _hasSearchOrFilters =>
      _submittedQuery.isNotEmpty || _hasActiveFilters;

  void _submitSearch() {
    setState(() {
      _submittedQuery = _queryController.text.trim();
      _submittedSection = 'popular';
    });
  }

  void _clearFilters() {
    setState(() {
      _submittedLanguage = '';
      _submittedPublishYear = '';
      _submittedGenre = '';
    });
  }

  CatalogBrowseRequest get _browseRequest => CatalogBrowseRequest(
        section: _hasSearchOrFilters ? 'popular' : _submittedSection,
        query: _submittedQuery,
        bookSources: _submittedBookSource.apiValue,
      );

  String _resultsHeading({int? resultCount}) {
    if (_submittedQuery.isNotEmpty) {
      final countSuffix = resultCount != null ? ' · $resultCount' : '';
      return 'Results for “$_submittedQuery”$countSuffix';
    }
    if (_hasActiveFilters) {
      final parts = <String>[];
      if (_submittedGenre.isNotEmpty) {
        parts.add(_submittedGenre);
      }
      if (_submittedLanguage.isNotEmpty) {
        parts.add(
          kBookCatalogLanguageLabels[_submittedLanguage] ?? _submittedLanguage,
        );
      }
      if (_submittedPublishYear.isNotEmpty) {
        parts.add(_submittedPublishYear);
      }
      final countSuffix = resultCount != null ? ' · $resultCount' : '';
      return 'Filtered books · ${parts.join(' · ')}$countSuffix';
    }
    final countSuffix = resultCount != null ? ' · $resultCount' : '';
    return 'Popular books$countSuffix';
  }

  Future<void> _loadSearchSettings() async {
    final storage = ref.read(sessionStorageProvider);
    final columnsRaw = await storage.read(key: StorageKeys.movieSearchGridColumns);
    final viewRaw = await storage.read(key: StorageKeys.bookSearchViewMode);
    if (!mounted) {
      return;
    }
    final parsedColumns = int.tryParse(columnsRaw ?? '');
    if (parsedColumns != null) {
      ref.read(bookSearchGridColumnsProvider.notifier).state = parsedColumns.clamp(2, 4);
    }
    final parsedView = parseBookSearchViewMode(viewRaw);
    if (parsedView != null) {
      ref.read(bookSearchViewModeProvider.notifier).state = parsedView;
    }
  }

  Future<void> _persistViewMode(BookSearchViewMode mode) async {
    ref.read(bookSearchViewModeProvider.notifier).state = mode;
    await ref.read(sessionStorageProvider).write(
          key: StorageKeys.bookSearchViewMode,
          value: mode.name,
        );
  }

  Future<void> _refreshResults(CatalogBrowseRequest request, String? username) async {
    final tasks = <Future<Object?>>[ref.refresh(booksProvider(request).future)];
    if (username != null && username.isNotEmpty) {
      tasks.add(ref.refresh(bookSearchTrackingProvider(username).future));
    }
    await Future.wait(tasks);
  }

  void _showSessionRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You need an active session to update your library.'),
      ),
    );
  }

  Future<void> _runTrackingMutation({
    required String username,
    required String savingId,
    required Future<String> Function(TrackingMutationController controller) mutation,
  }) async {
    setState(() => _savingIds.add(savingId));
    try {
      final successMessage = await mutation(ref.read(trackingMutationControllerProvider));
      ref.invalidate(bookSearchTrackingProvider(username));
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.book));
      invalidateBooksHomeCaches(ref, username: username);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      showApiErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() => _savingIds.remove(savingId));
      }
    }
  }

  bool _isActivelyReading(TrackingItem? tracking) {
    if (trackingIsDropped(tracking) || trackingIsWatched(tracking)) {
      return false;
    }
    return trackingIsDoing(tracking);
  }

  ({IconData icon, bool active}) _readingSheetButton(TrackingItem? tracking) {
    if (_isActivelyReading(tracking)) {
      return (icon: Icons.menu_book, active: true);
    }
    if (trackingIsWatched(tracking)) {
      return (icon: Icons.check_circle, active: true);
    }
    if (trackingIsDropped(tracking)) {
      return (icon: Icons.flag, active: true);
    }
    return (icon: Icons.menu_book_outlined, active: false);
  }

  Future<void> _onReadingFromSheet(
    CatalogItem item,
    TrackingItem? tracking,
    String username,
  ) async {
    if (_isActivelyReading(tracking)) {
      await _showFinishReadingFromSearch(item, tracking, username);
      return;
    }

    if (trackingIsDropped(tracking)) {
      await _showLeftResumeFromSearch(item, tracking, username);
      return;
    }

    await _runTrackingMutation(
      username: username,
      savingId: item.id,
      mutation: (c) => c.toggleReading(
        username: username,
        media: item,
        tracking: tracking,
      ),
    );
  }

  Future<void> _showLeftResumeFromSearch(
    CatalogItem item,
    TrackingItem? tracking,
    String username,
  ) async {
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<LeftResumeSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: LeftResumeSheet(
            headerTitle: 'Left',
            mediaTitle: item.title,
            doingLabel: 'Resume reading',
            doingSubtitle: 'Moves to Reading',
            doneLabel: 'Mark as read',
            doneSubtitle: 'Moves to Read',
            initialScore: tracking?.score,
          ),
        );
      },
    );
    if (result == null) {
      return;
    }

    if (result.outcome == LeftResumeOutcome.doing) {
      await _runTrackingMutation(
        username: username,
        savingId: item.id,
        mutation: (c) => c.toggleReading(
          username: username,
          media: item,
          tracking: tracking,
        ),
      );
      return;
    }

    await _runTrackingMutation(
      username: username,
      savingId: item.id,
      mutation: (c) => c.finishReadingBook(
        username: username,
        media: item,
        tracking: tracking,
        markAsRead: true,
        score: result.score,
        actionAtUtc: result.actionAtUtc,
      ),
    );
  }

  Future<void> _showFinishReadingFromSearch(
    CatalogItem item,
    TrackingItem? tracking,
    String username,
  ) async {
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<BookFinishReadingSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: BookFinishReadingSheet(
            bookTitle: item.title,
            initialScore: tracking?.score,
          ),
        );
      },
    );
    if (result == null) {
      return;
    }

    if (result.outcome == BookReadingOutcome.paused) {
      await _runTrackingMutation(
        username: username,
        savingId: item.id,
        mutation: (c) => c.pauseReadingBook(
          username: username,
          media: item,
          tracking: tracking,
        ),
      );
      return;
    }

    await _runTrackingMutation(
      username: username,
      savingId: item.id,
      mutation: (c) => c.finishReadingBook(
        username: username,
        media: item,
        tracking: tracking,
        markAsRead: result.outcome == BookReadingOutcome.read,
        score: result.score,
        actionAtUtc: result.actionAtUtc,
      ),
    );
  }

  Future<void> _showReadSheet(
    CatalogItem item,
    TrackingItem? tracking,
    String username,
  ) async {
    final isRead = trackingIsWatched(tracking);
    final shouldApply = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isRead ? 'Update read status' : 'Mark as read',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                isRead
                    ? 'Remove this book from your read list.'
                    : 'Mark the book as finished reading.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: Icon(
                        isRead ? Icons.check_circle : Icons.check_circle_outline,
                      ),
                      label: Text(isRead ? 'Remove read' : 'Mark read'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (shouldApply != true) {
      return;
    }
    await _runTrackingMutation(
      username: username,
      savingId: item.id,
      mutation: (controller) => controller.toggleWatched(
        username: username,
        media: item,
        tracking: tracking,
      ),
    );
  }

  Future<void> _showActionsSheet(
    CatalogItem item,
    TrackingItem? tracking,
    String? username,
  ) async {
    final theme = Theme.of(context);
    final collected = hasTrackingFlag(tracking, kCollectedTrackingFlag);
    final readingBtn = _readingSheetButton(tracking);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MoviePosterThumb(
                    imageUrl: item.imageUrl,
                    width: 42,
                    height: 60,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ActionSheetButton(
                      icon: trackingIsInWatchlist(tracking)
                          ? Icons.bookmark
                          : Icons.bookmark_border_outlined,
                      label: 'Later',
                      active: trackingIsInWatchlist(tracking),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (username == null || username.isEmpty) {
                          _showSessionRequiredMessage();
                          return;
                        }
                        _runTrackingMutation(
                          username: username,
                          savingId: item.id,
                          mutation: (c) => c.toggleWatchlist(
                            username: username,
                            media: item,
                            tracking: tracking,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ActionSheetButton(
                      icon: readingBtn.icon,
                      label: 'Reading',
                      active: readingBtn.active,
                      onTap: () {
                        Navigator.of(context).pop();
                        if (username == null || username.isEmpty) {
                          _showSessionRequiredMessage();
                          return;
                        }
                        _onReadingFromSheet(item, tracking, username);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ActionSheetButton(
                      icon: trackingIsBuy(tracking)
                          ? Icons.shopping_bag
                          : Icons.shopping_bag_outlined,
                      label: 'Buy',
                      active: trackingIsBuy(tracking),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (username == null || username.isEmpty) {
                          _showSessionRequiredMessage();
                          return;
                        }
                        _runTrackingMutation(
                          username: username,
                          savingId: item.id,
                          mutation: (c) => c.toggleBuy(
                            username: username,
                            media: item,
                            tracking: tracking,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ActionSheetButton(
                      icon: trackingIsWatched(tracking)
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      label: 'Read',
                      active: trackingIsWatched(tracking),
                      onTap: () {
                        Navigator.of(context).pop();
                        if (username == null || username.isEmpty) {
                          _showSessionRequiredMessage();
                          return;
                        }
                        _showReadSheet(item, tracking, username);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ActionSheetButton(
                      icon: collected
                          ? Icons.inventory_2
                          : Icons.inventory_2_outlined,
                      label: 'Owned',
                      active: collected,
                      onTap: () async {
                        final pageContext = this.context;
                        Navigator.of(context).pop();
                        if (username == null || username.isEmpty) {
                          _showSessionRequiredMessage();
                          return;
                        }
                        final message = await runCollectedToggle(
                          context: pageContext,
                          controller: ref.read(trackingMutationControllerProvider),
                          username: username,
                          media: item,
                          tracking: tracking,
                        );
                        if (message == null || !mounted) {
                          return;
                        }
                        ref.invalidate(bookSearchTrackingProvider(username));
                        ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.book));
                        invalidateBooksHomeCaches(ref, username: username);
                        if (!pageContext.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(content: Text(message)),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(catalogItemDetailPath(item));
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View book details'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _resultsHeader(BuildContext context, BookSearchViewMode viewMode, {int? resultCount}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _resultsHeading(resultCount: resultCount),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        PopupMenuButton<BookSearchViewMode>(
          tooltip: 'Change layout',
          icon: Icon(viewMode.icon),
          onSelected: _persistViewMode,
          itemBuilder: (context) => [
            for (final mode in BookSearchViewMode.values)
              PopupMenuItem<BookSearchViewMode>(
                value: mode,
                child: Row(
                  children: [
                    Icon(mode.icon, size: 18),
                    const SizedBox(width: 10),
                    Text(mode.label),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final trackingByMediaId = username == null || username.isEmpty
        ? const <String, TrackingItem>{}
        : (ref.watch(bookSearchTrackingProvider(username)).asData?.value ??
            const <String, TrackingItem>{});
    final gridColumns = switch (ref.watch(bookSearchGridColumnsProvider)) {
      4 => 4,
      2 => 2,
      _ => 3,
    };
    final results = ref.watch(booksProvider(_browseRequest));
    final viewMode = ref.watch(bookSearchViewModeProvider);

    const filterOptions = <LibraryFilterOption>[];

    return Scaffold(
      extendBody: true,
      appBar: const CulturAppBar(),
      body: RefreshIndicator(
        onRefresh: () => _refreshResults(_browseRequest, username),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 132),
          children: [
            LibrarySearchFilterHeader(
              searchController: _queryController,
              searchHint: 'Title, author, ISBN…',
              onSearchChanged: (_) => setState(() {}),
              onSearchSubmitted: (_) => _submitSearch(),
              filterOptions: filterOptions,
              onClearAll: _hasActiveFilters ? _clearFilters : null,
              padding: EdgeInsets.zero,
              searchTrailing: IconButton(
                tooltip: 'Search',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                onPressed: _submitSearch,
                icon: const Icon(Icons.search, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            results.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => ErrorState(
                error: error,
                onRetry: () => ref.invalidate(booksProvider(_browseRequest)),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _resultsHeader(context, viewMode, resultCount: 0),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 280,
                        child: EmptyState(
                          title: 'No books',
                          message:
                              'Try another search, ISBN, publisher:Name, or adjust filters.',
                          icon: Icons.menu_book_outlined,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _resultsHeader(context, viewMode, resultCount: data.items.length),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: BookResultsLayout(
                        key: ValueKey(viewMode),
                        viewMode: viewMode,
                        items: data.items,
                        gridColumns: gridColumns,
                        onOpenBook: (item) => context.push(catalogItemDetailPath(item)),
                        onOpenActions: (item) =>
                            _showActionsSheet(item, trackingByMediaId[item.id], username),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.book,
      ),
    );
  }
}
