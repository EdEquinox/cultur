import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/providers/catalog_browse_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/home/widgets/latest_release_card.dart';
import 'package:yamtrack/src/screens/home/widgets/shelf_heading.dart';
import 'package:yamtrack/src/screens/home/widgets/upcoming_poster_card.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

/// Home upcoming: horizontal timeline grouped by release day + selected card.
class UpcomingTimelineSection extends ConsumerStatefulWidget {
  const UpcomingTimelineSection({
    super.key,
    required this.title,
    required this.icon,
    required this.state,
    required this.emptyMessage,
    this.onSeeAll,
    this.paginateMovies = false,
    this.initialItemCount = 6,
    this.loadMoreBatchSize = 6,
  });

  final String title;
  final IconData icon;
  final AsyncValue<CatalogListData> state;
  final String emptyMessage;
  final VoidCallback? onSeeAll;
  final bool paginateMovies;
  final int initialItemCount;
  final int loadMoreBatchSize;

  static const double _stripHeight = 186;
  static const int _moviesPageSizeHint = 18;

  @override
  ConsumerState<UpcomingTimelineSection> createState() =>
      UpcomingTimelineSectionState();
}

class UpcomingTimelineSectionState extends ConsumerState<UpcomingTimelineSection> {
  final ScrollController _timelineScrollController = ScrollController();
  final List<CatalogItem> _items = [];
  final Set<String> _seenIds = {};

  late int _visibleItemCount;
  int _selectedIndex = 0;
  String? _itemsSignature;
  int _moviePage = 1;
  bool _loadingMore = false;
  bool _moviePaginationExhausted = false;

  @override
  void initState() {
    super.initState();
    _visibleItemCount = widget.initialItemCount;
    _timelineScrollController.addListener(_onTimelineScroll);
  }

  @override
  void didUpdateWidget(UpcomingTimelineSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final seed = widget.state.asData?.value.items;
    if (seed == null) {
      return;
    }
    final upcoming = seed.where(catalogItemIsUpcomingRelease).toList();
    _seedIfNeeded(upcoming);
  }

  void _applySeed(List<CatalogItem> upcoming) {
    _itemsSignature = upcoming.map((e) => e.id).join('|');
    _items
      ..clear()
      ..addAll(upcoming);
    _seenIds
      ..clear()
      ..addAll(_items.map((e) => e.id));
    _moviePage = 1;
    _moviePaginationExhausted = false;
    _loadingMore = false;
    _visibleItemCount = widget.initialItemCount.clamp(0, _items.length);
    _selectedIndex = 0;
  }

  void _afterSeed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_timelineScrollController.hasClients) {
        _timelineScrollController.jumpTo(0);
      }
      _prefetchIfContentFits();
    });
  }

  void _seedIfNeeded(List<CatalogItem> upcoming) {
    if (upcoming.isEmpty) {
      return;
    }
    final signature = upcoming.map((e) => e.id).join('|');
    if (signature == _itemsSignature) {
      return;
    }
    setState(() => _applySeed(upcoming));
    _afterSeed();
  }

  @override
  void dispose() {
    _timelineScrollController.removeListener(_onTimelineScroll);
    _timelineScrollController.dispose();
    super.dispose();
  }

  bool get _canFetchMoreMovies =>
      widget.paginateMovies && !_moviePaginationExhausted;

  bool get _hasMoreToShow =>
      _visibleItemCount < _items.length || _canFetchMoreMovies;

  void _onTimelineScroll() {
    if (!_timelineScrollController.hasClients || _loadingMore) {
      return;
    }
    final metrics = _timelineScrollController.position;
    if (metrics.maxScrollExtent > 0 &&
        metrics.pixels < metrics.maxScrollExtent - 80) {
      return;
    }
    _loadMore();
  }

  void _prefetchIfContentFits() {
    if (!_hasMoreToShow || !_timelineScrollController.hasClients) {
      return;
    }
    if (_timelineScrollController.position.maxScrollExtent > 0) {
      return;
    }
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore) {
      return;
    }

    if (_visibleItemCount < _items.length) {
      setState(() {
        _visibleItemCount = (_visibleItemCount + widget.loadMoreBatchSize)
            .clamp(0, _items.length);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfContentFits());
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

        if (pageItems.length < UpcomingTimelineSection._moviesPageSizeHint) {
          _moviePaginationExhausted = true;
        }

        if (added.isNotEmpty) {
          setState(() {
            _visibleItemCount = (_visibleItemCount + widget.loadMoreBatchSize)
                .clamp(0, _items.length);
            _loadingMore = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfContentFits());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeading(title: widget.title, icon: widget.icon, onSeeAll: widget.onSeeAll),
        const SizedBox(height: 12),
        widget.state.when(
          loading: () => const SizedBox(
            height: 360,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => SizedBox(
            height: 180,
            child: ErrorState(error: error),
          ),
          data: (data) {
            final upcoming = data.items.where(catalogItemIsUpcomingRelease).toList();
            if (_itemsSignature == null && upcoming.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                _seedIfNeeded(upcoming);
              });
            }

            final source = _items.isNotEmpty ? _items : upcoming;
            if (source.isEmpty) {
              return SizedBox(
                height: 140,
                child: EmptyState(
                  title: widget.title,
                  message: widget.emptyMessage,
                  icon: widget.icon,
                ),
              );
            }

            final visibleCount = _visibleItemCount.clamp(0, source.length);
            final segments = _buildPreviewSegments(source, visibleCount);
            if (segments.isEmpty) {
              return SizedBox(
                height: 140,
                child: EmptyState(
                  title: widget.title,
                  message: widget.emptyMessage,
                  icon: widget.icon,
                ),
              );
            }

            final flatItems = [
              for (final segment in segments) ...segment.items,
            ];
            final safeIndex = _selectedIndex.clamp(0, flatItems.length - 1);
            final selected = flatItems[safeIndex];
            final hasMore = _hasMoreToShow;

            return Column(
              children: [
                SizedBox(
                  height: UpcomingTimelineSection._stripHeight,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.axis != Axis.horizontal) {
                        return false;
                      }
                      if (notification is ScrollUpdateNotification ||
                          notification is ScrollEndNotification) {
                        final m = notification.metrics;
                        if (m.maxScrollExtent <= 0 ||
                            m.pixels >= m.maxScrollExtent - 80) {
                          _loadMore();
                        }
                      }
                      return false;
                    },
                    child: ListView.separated(
                      controller: _timelineScrollController,
                      scrollDirection: Axis.horizontal,
                      itemCount: segments.length + (hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(width: 20),
                      itemBuilder: (context, index) {
                        if (hasMore && index == segments.length) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: _loadingMore
                                    ? const CircularProgressIndicator(strokeWidth: 2)
                                    : const Icon(Icons.more_horiz),
                              ),
                            ),
                          );
                        }
                        final segment = segments[index];
                        return _HorizontalDayGroup(
                          dayLabel: releaseDayLabel(segment.day),
                          items: segment.items,
                          startIndex: segment.startIndex,
                          selectedIndex: safeIndex,
                          onSelect: (globalIndex) {
                            setState(() => _selectedIndex = globalIndex);
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                LatestReleaseCard(
                  item: selected,
                  width: double.infinity,
                  showReleaseDate: false,
                  onTap: () => context.push(catalogItemDetailPath(selected)),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PreviewSegment {
  const _PreviewSegment({
    required this.day,
    required this.items,
    required this.startIndex,
  });

  final DateTime day;
  final List<CatalogItem> items;
  final int startIndex;
}

List<_PreviewSegment> _buildPreviewSegments(List<CatalogItem> items, int maxCount) {
  final groups = groupCatalogItemsByReleaseDay(items);
  var remaining = maxCount;
  final segments = <_PreviewSegment>[];
  var startIndex = 0;

  for (final group in groups) {
    if (remaining <= 0) {
      break;
    }
    final take = group.items.take(remaining).toList();
    if (take.isEmpty) {
      continue;
    }
    remaining -= take.length;
    segments.add(
      _PreviewSegment(day: group.day, items: take, startIndex: startIndex),
    );
    startIndex += take.length;
  }

  return segments;
}

class _HorizontalDayGroup extends StatelessWidget {
  const _HorizontalDayGroup({
    required this.dayLabel,
    required this.items,
    required this.startIndex,
    required this.selectedIndex,
    required this.onSelect,
  });

  final String dayLabel;
  final List<CatalogItem> items;
  final int startIndex;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.55);
    final postersWidth = items.length * UpcomingPosterCard.width +
        (items.length > 1 ? (items.length - 1) * 12 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dayLabel,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: postersWidth,
          height: 1,
          color: lineColor,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              UpcomingPosterCard(
                item: items[i],
                isSelected: startIndex + i == selectedIndex,
                onTap: () => onSelect(startIndex + i),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
