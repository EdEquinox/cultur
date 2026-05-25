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

class BookSeriesDetailPage extends ConsumerStatefulWidget {
  const BookSeriesDetailPage({
    required this.seriesId,
    this.initialName,
    super.key,
  });

  final String seriesId;
  final String? initialName;

  @override
  ConsumerState<BookSeriesDetailPage> createState() => _BookSeriesDetailPageState();
}

class _BookSeriesDetailPageState extends ConsumerState<BookSeriesDetailPage> {
  int _tabIndex = 0;

  BookSeriesDetailRequest get _request => BookSeriesDetailRequest(
        seriesId: widget.seriesId,
        seriesName: widget.initialName,
      );

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

  int _readCount(GameCompanyCatalogDetail series, Set<String> readIds) {
    var n = 0;
    for (final entry in series.catalog) {
      if (readIds.contains(entry.media.id)) {
        n++;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final asyncSeries = ref.watch(bookSeriesCatalogDetailProvider(_request));
    final digestAsync = ref.watch(userBookTrackingDigestProvider);
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
      body: asyncSeries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(bookSeriesCatalogDetailProvider(_request)),
        ),
        data: (series) {
          final readCount = _readCount(series, readIds);
          final displayName = series.name.isNotEmpty
              ? series.name
              : (widget.initialName?.trim().isNotEmpty == true
                  ? widget.initialName!.trim()
                  : 'Series');

          final tabBody = switch (_tabIndex) {
            1 => _SeriesCatalogTab(
                items: series.catalog,
                digest: switch (digestAsync) {
                  AsyncData(:final value) => value,
                  _ => const UserBookTrackingDigest(readIds: {}, byMediaId: {}),
                },
                onOpenItem: _openBook,
              ),
            _ => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (series.popularCatalog.isNotEmpty) ...[
                    Text(
                      'In this series',
                      style: CulturCatalogTypography.sectionHeading(Theme.of(context)),
                    ),
                    const SizedBox(height: 12),
                    for (final item in series.popularCatalog.take(8)) ...[
                      CulturCatalogListRow(
                        item: item.media,
                        metaParts: item.roles,
                        score: digestAsync.asData?.value.byMediaId[item.media.id]?.score,
                        onTap: () => _openBook(item),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                  if (series.links.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    MediaDetailLinksSection(
                      links: series.links,
                      onOpenLink: _openUrl,
                    ),
                  ],
                ],
              ),
          };

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                ref.refresh(bookSeriesCatalogDetailProvider(_request).future),
                ref.refresh(userBookTrackingDigestProvider.future),
              ]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _SeriesHeader(
                  displayName: displayName,
                  bookCount: series.catalog.length,
                  readCount: readCount,
                  isLoggedIn: isLoggedIn,
                  onReadTap: !isLoggedIn
                      ? null
                      : readCount == 0
                      ? null
                      : () => setState(() => _tabIndex = 1),
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

class _SeriesHeader extends StatelessWidget {
  const _SeriesHeader({
    required this.displayName,
    required this.bookCount,
    required this.readCount,
    required this.isLoggedIn,
    required this.onReadTap,
  });

  final String displayName;
  final int bookCount;
  final int readCount;
  final bool isLoggedIn;
  final VoidCallback? onReadTap;

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
              child: Icon(Icons.library_books_outlined, size: 40, color: scheme.onSurfaceVariant),
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
                '$bookCount books',
                style: CulturCatalogTypography.profileSubtitle(theme, scheme),
              ),
              const SizedBox(height: 12),
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
            ],
          ),
        ),
      ],
    );
  }
}

class _SeriesCatalogTab extends StatelessWidget {
  const _SeriesCatalogTab({
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
          'No books in this series yet.',
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
            metaParts: items[i].roles,
            score: digest.byMediaId[items[i].media.id]?.score,
            onTap: () => onOpenItem(items[i]),
          ),
        ],
      ],
    );
  }
}
