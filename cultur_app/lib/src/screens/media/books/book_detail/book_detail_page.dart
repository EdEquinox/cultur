import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/rating_sheet_result.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/books_home_providers.dart';
import 'package:yamtrack/src/providers/catalog_detail_providers.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/media/books/book_detail/widgets/book_authors_section.dart';
import 'package:yamtrack/src/screens/media/books/book_detail/widgets/book_publishers_section.dart';
import 'package:yamtrack/src/screens/media/books/book_detail/widgets/book_hero_carousel.dart';
import 'package:yamtrack/src/screens/media/books/book_detail/widgets/book_reading_progress_card.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_detail_nav_row.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_pending_catalog_banner.dart';
import 'package:yamtrack/src/screens/media/books/book_detail/widgets/book_resolve_hardcover_sheet.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_hero_carousel.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_ratings_row.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/screens/widgets/book_action_row.dart';
import 'package:yamtrack/src/screens/widgets/book_finish_reading_sheet.dart';
import 'package:yamtrack/src/screens/widgets/left_resume_sheet.dart';
import 'package:yamtrack/src/screens/widgets/game_lists_sheet.dart';
import 'package:yamtrack/src/screens/widgets/genres_tags_card.dart';
import 'package:yamtrack/src/screens/widgets/media_detail_links_section.dart';
import 'package:yamtrack/src/screens/widgets/mark_watched_sheet.dart';
import 'package:yamtrack/src/screens/widgets/movie_rating_sheet.dart';
import 'package:yamtrack/src/utils/book_progress_utils.dart';
import 'package:yamtrack/src/utils/book_series_utils.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/collected_toggle_flow.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class BookDetailPage extends ConsumerStatefulWidget {
  const BookDetailPage({required this.mediaId, super.key});

  final String mediaId;

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  bool _isSaving = false;
  bool _isRefreshingMetadata = false;
  bool _showFullOverview = false;

  CatalogDetailRequest get _request {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    return CatalogDetailRequest(
      mediaId: widget.mediaId,
      username: username,
      kind: CatalogDetailKind.book,
    );
  }

  Future<void> _runTrackingMutation({
    required Future<String?> Function(TrackingMutationController controller, String username)
        mutation,
  }) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to update tracking.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final message = await mutation(ref.read(trackingMutationControllerProvider), username);
      if (message == null) {
        return;
      }
      ref.invalidate(catalogDetailProvider(_request));
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.book));
      ref.invalidate(customBookListsProvider);
      invalidateBooksHomeCaches(ref, username: username);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  bool _isActivelyReading(TrackingItem? tracking) => trackingIsActivelyDoing(tracking);

  Future<void> _onReadingTap(CatalogDetail detail) async {
    if (_isActivelyReading(detail.tracking)) {
      await _showFinishReadingSheet(detail);
      return;
    }

    if (trackingIsDropped(detail.tracking)) {
      await _showLeftResumeSheet(detail);
      return;
    }

    await _runTrackingMutation(
      mutation: (controller, username) => controller.toggleReading(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
      ),
    );
  }

  Future<void> _showLeftResumeSheet(CatalogDetail detail) async {
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
            mediaTitle: detail.media.title,
            doingLabel: 'Resume reading',
            doingSubtitle: 'Moves to Reading',
            doneLabel: 'Mark as read',
            doneSubtitle: 'Moves to Read',
            initialScore: detail.tracking?.score,
          ),
        );
      },
    );
    if (result == null) {
      return;
    }

    if (result.outcome == LeftResumeOutcome.doing) {
      await _runTrackingMutation(
        mutation: (controller, username) => controller.toggleReading(
          username: username,
          media: detail.media,
          tracking: detail.tracking,
        ),
      );
      return;
    }

    await _runTrackingMutation(
      mutation: (controller, username) => controller.finishReadingBook(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
        markAsRead: true,
        score: result.score,
        actionAtUtc: result.actionAtUtc,
      ),
    );
  }

  Future<void> _showFinishReadingSheet(CatalogDetail detail) async {
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
            bookTitle: detail.media.title,
            initialScore: detail.tracking?.score,
          ),
        );
      },
    );
    if (result == null) {
      return;
    }

    if (result.outcome == BookReadingOutcome.paused) {
      await _runTrackingMutation(
        mutation: (controller, username) => controller.pauseReadingBook(
          username: username,
          media: detail.media,
          tracking: detail.tracking,
        ),
      );
      return;
    }

    await _runTrackingMutation(
      mutation: (controller, username) => controller.finishReadingBook(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
        markAsRead: result.outcome == BookReadingOutcome.read,
        score: result.score,
        actionAtUtc: result.actionAtUtc,
      ),
    );
  }

  Future<void> _togglePriority(CatalogDetail detail) async {
    await _runTrackingMutation(
      mutation: (controller, username) => controller.togglePriority(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
      ),
    );
  }

  Widget _heroPriorityPin(CatalogDetail detail) {
    final inPriority = trackingIsPriority(detail.tracking);
    return GameHeroOverlayPinButton(
      icon: inPriority ? Icons.push_pin : Icons.push_pin_outlined,
      tooltip: inPriority ? 'Remove from priority' : 'Priority — show in Next to read',
      onPressed: _isSaving ? null : () => _togglePriority(detail),
    );
  }

  Future<void> _showReadSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to update tracking.')),
      );
      return;
    }

    final tracking = detail.tracking;
    final theme = Theme.of(context);
    if (trackingIsWatched(tracking)) {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        builder: (context) => RemoveWatchedSheet.forCatalog(media: detail.media),
      );
      if (confirmed != true || !mounted) {
        return;
      }
      await _runTrackingMutation(
        mutation: (controller, u) => controller.toggleWatched(
          username: u,
          media: detail.media,
          tracking: tracking,
        ),
      );
      return;
    }

    final result = await showModalBottomSheet<MarkWatchedSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: MarkWatchedSheet.forCatalog(
            media: detail.media,
            tracking: tracking,
          ),
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    await _runTrackingMutation(
      mutation: (controller, u) => controller.markAsWatched(
        username: u,
        media: detail.media,
        tracking: tracking,
        completedAtUtc: result.completedAtUtc,
        score: result.score,
      ),
    );
  }

  Future<void> _showRatingSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }
    var stars = detail.tracking?.score?.round().clamp(0, 10) ?? 0;
    final hasExisting = detail.tracking?.score != null;

    final result = await showModalBottomSheet<RatingSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return MovieRatingSheet(
              title: 'Rate this book',
              prompt: 'Your rating',
              hasExistingRating: hasExisting,
              selectedStars: stars,
              onStarsChanged: (value) => setModalState(() => stars = value),
              onCancel: () => Navigator.of(context).pop(const RatingSheetDismissed()),
              onSave: () {
                if (stars <= 0) {
                  Navigator.of(context).pop(const RatingSheetRemoved());
                } else {
                  Navigator.of(context).pop(RatingSheetSet(stars.toDouble()));
                }
              },
            );
          },
        );
      },
    );

    switch (result) {
      case null:
      case RatingSheetDismissed():
        return;
      case RatingSheetRemoved():
        await _runTrackingMutation(
          mutation: (controller, user) => controller.saveRating(
            username: user,
            media: detail.media,
            tracking: detail.tracking,
            remove: true,
          ),
        );
      case RatingSheetSet(:final score):
        await _runTrackingMutation(
          mutation: (controller, user) => controller.saveRating(
            username: user,
            media: detail.media,
            tracking: detail.tracking,
            score: score,
          ),
        );
    }
  }

  Future<void> _showListsSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }

    Future<void> createList() async {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Create custom list'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'List name'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
      if (name == null || name.trim().isEmpty) {
        return;
      }
      await ref.read(customBookListsControllerProvider).createList(username, name);
      ref.invalidate(customBookListsProvider);
    }

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final listsAsync = ref.watch(customBookListsProvider);
            return GameListsSheet(
              detail: detail,
              listsAsync: listsAsync,
              isBuiltInList: BuiltInBookLists.isBuiltIn,
              itemLabel: 'books',
              onCreateList: createList,
              onToggleList: (list) async {
                await ref.read(customBookListsControllerProvider).toggleItem(
                      username: username,
                      listId: list.id,
                      item: detail.media,
                    );
                ref.invalidate(customBookListsProvider);
              },
              onDone: () => Navigator.pop(context),
            );
          },
        );
      },
    );
  }

  List<String> _bookKeywords(CatalogDetail detail) => detail.keywords;

  Future<void> _refreshMetadataFromAllProviders() async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    setState(() => _isRefreshingMetadata = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.getJson(
        catalogDetailApiPath(_request),
        queryParameters: {
          'refresh': 'true',
          if (username != null && username.isNotEmpty) 'username': username,
        },
      );
      ref.invalidate(catalogDetailProvider(_request));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Book metadata updated from PORBASE, Hardcover, and Open Library.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingMetadata = false);
      }
    }
  }

  Future<void> _openHardcoverResolveSheet(CatalogDetail detail, {required bool isPending}) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to link this book.')),
      );
      return;
    }
    final resolvedId = await showBookHardcoverResolveSheet(
      context: context,
      ref: ref,
      mediaId: widget.mediaId,
      username: username,
      initialQuery: detail.media.title,
      isPending: isPending,
    );
    if (resolvedId == null || !mounted) {
      return;
    }
    ref.invalidate(catalogDetailProvider(_request));
    ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.book));
    ref.invalidate(customBookListsProvider);
    invalidateBooksHomeCaches(ref, username: username);
    if (isPending && resolvedId != widget.mediaId) {
      context.pushReplacement('/books/$resolvedId');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Book details updated from Hardcover.')),
    );
  }

  Future<void> _copyPrimaryLink(CatalogDetail detail) async {
    final primaryUrl = detail.links.isNotEmpty
        ? detail.links.first.url
        : 'https://openlibrary.org/works/${detail.media.externalId}';
    await Clipboard.setData(ClipboardData(text: primaryUrl));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(catalogDetailProvider(_request));
    final theme = Theme.of(context);

    return Scaffold(
      extendBody: true,
      appBar: CulturAppBar(
        additionalActions: [
          IconButton(
            tooltip: 'Edit book',
            onPressed: () => context.push('/books/${widget.mediaId}/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(catalogDetailProvider(_request)),
        ),
        data: (detail) {
          final overview = (detail.overview ?? '').trim();
          final tracking = detail.tracking;
          final scheme = theme.colorScheme;
          final collected = hasTrackingFlag(tracking, kCollectedTrackingFlag);
          final currentPage = bookCurrentPage(tracking);
          final totalPages = bookPageCount(detail.media);
          final seriesKey = bookSeriesKey(detail.media);
          final seriesName = bookSeriesName(detail.media);
          final seriesPosition = bookSeriesPosition(detail.media);
          final authors = detail.cast
              .where(
                (person) =>
                    person.name.trim().isNotEmpty &&
                    (person.role ?? '').trim().toLowerCase() != 'publisher',
              )
              .toList();
          final publishers = detail.bookPublishers;

          final keywords = _bookKeywords(detail);
          final activelyReading = _isActivelyReading(tracking);
          final read = trackingIsWatched(tracking);
          final dropped = trackingIsDropped(tracking);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              BookHeroCarousel(
                detail: detail,
                overlayActions: _heroPriorityPin(detail),
                onShareTap: () => _copyPrimaryLink(detail),
              ),
              if (detail.catalogPending) ...[
                const SizedBox(height: 12),
                GamePendingCatalogBanner(
                  importSource: detail.importSource,
                  catalogProviderLabel: 'Hardcover',
                  onSearchCatalog: () => _openHardcoverResolveSheet(detail, isPending: true),
                ),
              ],
              const SizedBox(height: 16),
              BookActionRow(
                isSaving: _isSaving,
                isInLater: trackingIsInWatchlist(tracking),
                isReading: activelyReading,
                isRead: read,
                isBuy: trackingIsBuy(tracking),
                isOwned: collected,
                isDropped: dropped,
                rating: tracking?.score,
                onLaterTap: () => _runTrackingMutation(
                  mutation: (controller, username) => controller.toggleWatchlist(
                    username: username,
                    media: detail.media,
                    tracking: tracking,
                  ),
                ),
                onReadingTap: () => _onReadingTap(detail),
                onBuyTap: () => _runTrackingMutation(
                  mutation: (controller, username) => controller.toggleBuy(
                    username: username,
                    media: detail.media,
                    tracking: tracking,
                  ),
                ),
                onReadTap: () => _showReadSheet(detail),
                onOwnedTap: () => _runTrackingMutation(
                  mutation: (controller, username) => runCollectedToggle(
                    context: context,
                    controller: controller,
                    username: username,
                    media: detail.media,
                    tracking: tracking,
                  ),
                ),
                onRateTap: () => _showRatingSheet(detail),
                onListsTap: () => _showListsSheet(detail),
              ),
              if (authors.isNotEmpty) ...[
                const SizedBox(height: 16),
                BookAuthorsSection(authors: authors),
              ],
              const SizedBox(height: 16),
              BookReadingProgressCard(
                detail: detail,
                tracking: tracking,
                isSaving: _isSaving,
                onPreviousPage: currentPage <= 0
                    ? null
                    : () => _runTrackingMutation(
                          mutation: (c, u) => c.updateReadingProgress(
                            username: u,
                            media: detail.media,
                            tracking: tracking,
                            currentPage: currentPage - 1,
                          ),
                        ),
                onNextPage: () {
                  final next = currentPage + 1;
                  if (totalPages != null && next > totalPages) {
                    return;
                  }
                  _runTrackingMutation(
                    mutation: (c, u) => c.updateReadingProgress(
                      username: u,
                      media: detail.media,
                      tracking: tracking,
                      currentPage: next,
                    ),
                  );
                },
              ),
              if (publishers.isNotEmpty) ...[
                const SizedBox(height: 16),
                BookPublishersSection(publishers: publishers),
              ],
              if (detail.ratings.isNotEmpty) ...[
                const SizedBox(height: 16),
                GameRatingsRow(ratings: detail.ratings),
              ],
              if (seriesName != null) ...[
                const SizedBox(height: 12),
                GameDetailNavRow(
                  icon: Icons.library_books_outlined,
                  label: 'Book series',
                  subtitle: seriesPosition != null
                      ? '$seriesName · #$seriesPosition'
                      : seriesName,
                  onTap: () {
                    if (seriesKey != null) {
                      context.push(
                        bookSeriesDetailPath(
                          seriesId: seriesKey,
                          name: seriesName,
                        ),
                      );
                      return;
                    }
                    context.push(
                      '/category/books?q=${Uri.encodeComponent('series:"$seriesName"')}',
                    );
                  },
                ),
              ],
              if (detail.genres.isNotEmpty || keywords.isNotEmpty) ...[
                const SizedBox(height: 16),
                GenresTagsCard(
                  genres: detail.genres,
                  keywords: keywords,
                  onGenreTap: (genre) => context.push(
                    '/category/books?genre=${Uri.encodeComponent(genre)}',
                  ),
                  onKeywordTap: (tag) => context.push(
                    '/category/books?genre=${Uri.encodeComponent(tag)}',
                  ),
                ),
              ],
              if (overview.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  overview,
                  maxLines: _showFullOverview ? null : 6,
                  overflow: _showFullOverview ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: CulturCatalogTypography.bodyText(theme, scheme),
                ),
                if (overview.length > 280) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _showFullOverview = !_showFullOverview),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _showFullOverview ? 'Show less' : 'Read more',
                        style: CulturCatalogTypography.linkAction(theme, scheme),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _openHardcoverResolveSheet(
                          detail,
                          isPending: detail.catalogPending,
                        ),
                icon: const Icon(Icons.search, size: 18),
                label: Text(
                  detail.catalogPending ? 'Search Hardcover to link' : 'Search Hardcover to update details',
                ),
              ),
              const SizedBox(height: 16),
              MediaDetailLinksSection(
                links: detail.links,
                isRefreshingMetadata: _isRefreshingMetadata,
                onRefreshMetadata: _isSaving ? null : _refreshMetadataFromAllProviders,
                onOpenLink: (url) async {
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.book,
      ),
    );
  }
}
