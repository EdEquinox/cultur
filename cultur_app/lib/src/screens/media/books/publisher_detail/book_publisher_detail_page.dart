import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/models/games/game_company_catalog_detail.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/publisher_providers.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/screens/widgets/media_detail_links_section.dart';
import 'package:yamtrack/src/screens/widgets/movie_tab_bar.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class BookPublisherDetailPage extends ConsumerStatefulWidget {
  const BookPublisherDetailPage({
    required this.publisherId,
    this.initialName,
    super.key,
  });

  final String publisherId;
  final String? initialName;

  @override
  ConsumerState<BookPublisherDetailPage> createState() => _BookPublisherDetailPageState();
}

class _BookPublisherDetailPageState extends ConsumerState<BookPublisherDetailPage> {
  int _tabIndex = 0;

  BookPublisherDetailRequest get _request =>
      BookPublisherDetailRequest(publisherId: widget.publisherId);

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openBook(GameCompanyCatalogItem item) {
    context.push('/books/${item.media.id}');
  }

  int _readCount(GameCompanyCatalogDetail publisher, Set<String> readIds) {
    var n = 0;
    for (final entry in publisher.catalog) {
      if (readIds.contains(entry.media.id)) {
        n++;
      }
    }
    return n;
  }

  Future<void> _toggleFavorite({
    required String username,
    required GameCompanyCatalogDetail publisher,
  }) async {
    await ref.read(favoritePublishersControllerProvider).toggleFavoritePublisher(
          username: username,
          publisherId: publisher.companyId,
          name: publisher.name,
        );
    ref.invalidate(favoritePublishersProvider);
  }

  void _requireSessionSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final asyncPublisher = ref.watch(bookPublisherCatalogDetailProvider(_request));
    final digestAsync = ref.watch(userBookTrackingDigestProvider);
    final favoritesAsync = ref.watch(favoritePublishersProvider);
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final isLoggedIn = username != null && username.isNotEmpty;
    final readIds = switch (digestAsync) {
      AsyncData(:final value) => value.readIds,
      _ => <String>{},
    };

    return Scaffold(
      appBar: const CulturAppBar(),
      extendBody: true,
      body: asyncPublisher.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(bookPublisherCatalogDetailProvider(_request)),
        ),
        data: (publisher) {
          final readCount = _readCount(publisher, readIds);
          final favoriteData = switch (favoritesAsync) {
            AsyncData(:final value) => value,
            _ => const FavoritePublishersData(publishers: []),
          };
          final isFavorite = favoriteData.publishers.any(
            (p) => p.publisherId == publisher.companyId,
          );
          final displayName = publisher.name.isNotEmpty
              ? publisher.name
              : (widget.initialName?.trim().isNotEmpty == true
                  ? widget.initialName!.trim()
                  : 'Publisher');

          final tabBody = switch (_tabIndex) {
            1 => _PublisherCatalogTab(
                items: publisher.catalog,
                digest: switch (digestAsync) {
                  AsyncData(:final value) => value,
                  _ => const UserBookTrackingDigest(readIds: {}, byMediaId: {}),
                },
                onOpenItem: _openBook,
              ),
            _ => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (publisher.popularCatalog.isNotEmpty) ...[
                    Text(
                      'Popular titles',
                      style: CulturCatalogTypography.sectionHeading(Theme.of(context)),
                    ),
                    const SizedBox(height: 12),
                    for (final item in publisher.popularCatalog.take(8)) ...[
                      CulturCatalogListRow(
                        item: item.media,
                        score: digestAsync.asData?.value.byMediaId[item.media.id]?.score,
                        onTap: () => _openBook(item),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                  if (publisher.links.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    MediaDetailLinksSection(
                      links: publisher.links,
                      onOpenLink: _openUrl,
                    ),
                  ],
                ],
              ),
          };

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                ref.refresh(bookPublisherCatalogDetailProvider(_request).future),
                ref.refresh(userBookTrackingDigestProvider.future),
                if (isLoggedIn) ref.refresh(favoritePublishersProvider.future),
              ]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _PublisherHeader(
                  displayName: displayName,
                  readCount: readCount,
                  isLoggedIn: isLoggedIn,
                  isFavorite: isFavorite,
                  onReadTap: !isLoggedIn
                      ? null
                      : readCount == 0
                      ? null
                      : () => setState(() => _tabIndex = 1),
                  onFavoriteTap: !isLoggedIn
                      ? () => _requireSessionSnack(
                            'Sign in to add publishers to your favorites list.',
                          )
                      : () async {
                          await _toggleFavorite(username: username, publisher: publisher);
                        },
                ),
                const SizedBox(height: 20),
                MovieTabBar(
                  selectedIndex: _tabIndex,
                  onSelected: (index) => setState(() => _tabIndex = index),
                  tabs: const ['Details', 'Catalog'],
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey(_tabIndex),
                    child: tabBody,
                  ),
                ),
              ],
            ),
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

class _PublisherHeader extends StatelessWidget {
  const _PublisherHeader({
    required this.displayName,
    required this.readCount,
    required this.isLoggedIn,
    required this.isFavorite,
    required this.onReadTap,
    required this.onFavoriteTap,
  });

  final String displayName;
  final int readCount;
  final bool isLoggedIn;
  final bool isFavorite;
  final VoidCallback? onReadTap;
  final VoidCallback onFavoriteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.culturTokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: tokens.borderRadiusTight,
          child: SizedBox(
            width: 108,
            height: 108,
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Icon(Icons.auto_stories_outlined, size: 40, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: CulturCatalogTypography.profileTitle(theme),
              ),
              const SizedBox(height: 4),
              Text(
                'Publisher',
                style: CulturCatalogTypography.profileSubtitle(theme, scheme),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: onReadTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary.withValues(alpha: 0.42),
                      foregroundColor: scheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: tokens.borderRadiusTight,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 18,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isLoggedIn ? '$readCount' : '—',
                          style: CulturCatalogTypography.actionCount(theme),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'read',
                          style: CulturCatalogTypography.actionLabel(theme, scheme),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onFavoriteTap,
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                    ),
                    label: Text(isFavorite ? 'Favorited' : 'Favorite'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: tokens.borderRadiusTight,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublisherCatalogTab extends StatelessWidget {
  const _PublisherCatalogTab({
    required this.items,
    required this.digest,
    required this.onOpenItem,
  });

  final List<GameCompanyCatalogItem> items;
  final UserBookTrackingDigest digest;
  final ValueChanged<GameCompanyCatalogItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No books in this catalog yet.',
          style: CulturCatalogTypography.emptyState(theme, theme.colorScheme),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          CulturCatalogListRow(
            item: items[i].media,
            score: digest.byMediaId[items[i].media.id]?.score,
            onTap: () => onOpenItem(items[i]),
          ),
        ],
      ],
    );
  }
}
