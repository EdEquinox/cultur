import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/screens/home/widgets/upcoming_winding_timeline.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

/// Expanded upcoming shelf: serpentine timeline with release-day nodes and grid cards.
class UpcomingShelfList extends ConsumerStatefulWidget {
  const UpcomingShelfList({
    required this.initialItems,
    required this.onItemTap,
    super.key,
    this.paginateMovies = false,
    this.padding = const EdgeInsets.fromLTRB(0, 12, 0, 24),
    this.initialVisibleCount = 12,
    this.loadMoreBatchSize = 12,
  });

  final List<CatalogItem> initialItems;
  final ValueChanged<CatalogItem> onItemTap;
  final bool paginateMovies;
  final EdgeInsetsGeometry padding;
  final int initialVisibleCount;
  final int loadMoreBatchSize;

  @override
  ConsumerState<UpcomingShelfList> createState() => _UpcomingShelfListState();
}

class _UpcomingShelfListState extends ConsumerState<UpcomingShelfList> {
  static const int _moviesPageSizeHint = 18;

  final ScrollController _scrollController = ScrollController();
  final List<CatalogItem> _items = [];
  final Set<String> _seenIds = {};

  int _visibleCount = 0;
  int _moviePage = 1;
  bool _loadingMore = false;
  bool _moviePaginationExhausted = false;

  @override
  void initState() {
    super.initState();
    _resetFromInitial(widget.initialItems);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfShort());
  }

  @override
  void didUpdateWidget(UpcomingShelfList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSig = oldWidget.initialItems.map((e) => e.id).join('|');
    final newSig = widget.initialItems.map((e) => e.id).join('|');
    if (oldSig != newSig) {
      _resetFromInitial(widget.initialItems);
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfShort());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  bool get _canFetchMoreMovies =>
      widget.paginateMovies && !_moviePaginationExhausted;

  bool get _hasMoreToShow => _visibleCount < _items.length || _canFetchMoreMovies;

  void _resetFromInitial(List<CatalogItem> initial) {
    _items
      ..clear()
      ..addAll(initial.where(catalogItemIsUpcomingRelease));
    _seenIds
      ..clear()
      ..addAll(_items.map((e) => e.id));
    _visibleCount = widget.initialVisibleCount.clamp(0, _items.length);
    _moviePage = 1;
    _loadingMore = false;
    _moviePaginationExhausted = false;
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore) {
      return;
    }
    final metrics = _scrollController.position;
    if (metrics.maxScrollExtent > 0 &&
        metrics.pixels < metrics.maxScrollExtent - 200) {
      return;
    }
    _loadMore();
  }

  void _prefetchIfShort() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMoreToShow) {
      return;
    }
    if (_scrollController.position.maxScrollExtent > 200) {
      return;
    }
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore) {
      return;
    }

    if (_visibleCount < _items.length) {
      setState(() {
        _visibleCount = (_visibleCount + widget.loadMoreBatchSize)
            .clamp(0, _items.length);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfShort());
      return;
    }

    if (!_canFetchMoreMovies) {
      return;
    }

    setState(() => _loadingMore = true);
    var nextPage = _moviePage + 1;
    var attempts = 0;
    try {
      while (attempts < 4 && mounted) {
        final pageItems =
            await ref.read(upcomingMoviesPageProvider(nextPage).future);
        attempts += 1;
        _moviePage = nextPage;

        final added = <CatalogItem>[];
        for (final item in pageItems) {
          if (_seenIds.add(item.id)) {
            _items.add(item);
            added.add(item);
          }
        }

        if (pageItems.length < _moviesPageSizeHint) {
          _moviePaginationExhausted = true;
        }

        if (added.isNotEmpty) {
          setState(() {
            _visibleCount = (_visibleCount + widget.loadMoreBatchSize)
                .clamp(0, _items.length);
            _loadingMore = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfShort());
          return;
        }

        if (pageItems.isEmpty || _moviePaginationExhausted) {
          break;
        }
        nextPage += 1;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _moviePaginationExhausted = true;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingMore = false);
      showApiErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _items.take(_visibleCount).toList();
    final groups = groupCatalogItemsByReleaseDay(upcoming);

    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    final showFooter = _hasMoreToShow;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis != Axis.vertical) {
          return false;
        }
        if (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification) {
          final m = notification.metrics;
          if (m.maxScrollExtent <= 0 || m.pixels >= m.maxScrollExtent - 200) {
            _loadMore();
          }
        }
        return false;
      },
      child: ListView(
        controller: _scrollController,
        padding: widget.padding,
        children: [
          UpcomingWindingTimeline(
            dayGroups: groups,
            onItemTap: widget.onItemTap,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            footer: showFooter
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: _loadingMore
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Icon(Icons.more_horiz),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
