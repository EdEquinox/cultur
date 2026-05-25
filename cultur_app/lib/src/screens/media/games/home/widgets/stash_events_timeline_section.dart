import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/games/stash_game_event.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/home/widgets/shelf_heading.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/stash_event_poster_card.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/stash_event_release_card.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

/// Past Stash.games industry events timeline (matches other category timelines).
class StashEventsTimelineSection extends ConsumerStatefulWidget {
  const StashEventsTimelineSection({super.key});

  static const double _stripHeight = 186;
  static const int _initialItemCount = 6;
  static const int _loadMoreBatchSize = 6;

  @override
  ConsumerState<StashEventsTimelineSection> createState() =>
      _StashEventsTimelineSectionState();
}

class _StashEventsTimelineSectionState
    extends ConsumerState<StashEventsTimelineSection> {
  final ScrollController _timelineScrollController = ScrollController();
  final List<StashGameEvent> _items = [];

  late int _visibleItemCount;
  int _selectedIndex = 0;
  String? _itemsSignature;

  @override
  void initState() {
    super.initState();
    _visibleItemCount = StashEventsTimelineSection._initialItemCount;
    _timelineScrollController.addListener(_onTimelineScroll);
  }

  @override
  void dispose() {
    _timelineScrollController.removeListener(_onTimelineScroll);
    _timelineScrollController.dispose();
    super.dispose();
  }

  bool get _hasMoreToShow => _visibleItemCount < _items.length;

  void _onTimelineScroll() {
    if (!_timelineScrollController.hasClients) {
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

  void _loadMore() {
    if (!_hasMoreToShow) {
      return;
    }
    setState(() {
      _visibleItemCount = (_visibleItemCount + StashEventsTimelineSection._loadMoreBatchSize)
          .clamp(0, _items.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchIfContentFits());
  }

  void _applySeed(List<StashGameEvent> events) {
    _itemsSignature = events.map((e) => e.slug).join('|');
    _items
      ..clear()
      ..addAll(events);
    _visibleItemCount = StashEventsTimelineSection._initialItemCount.clamp(0, _items.length);
    _selectedIndex = 0;
  }

  void _seedIfNeeded(List<StashGameEvent> events) {
    if (events.isEmpty) {
      return;
    }
    final signature = events.map((e) => e.slug).join('|');
    if (signature == _itemsSignature) {
      return;
    }
    setState(() => _applySeed(events));
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

  void _openEvent(StashGameEvent event) {
    context.push('/games/events/${event.slug}');
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(stashGameEventsProvider(StashEventsWindow.previous));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeading(
          title: 'Events',
          icon: Icons.event_outlined,
          onSeeAll: () => context.push('/shelves/games/events'),
        ),
        const SizedBox(height: 12),
        eventsAsync.when(
          loading: () => const SizedBox(
            height: 360,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => SizedBox(
            height: 180,
            child: ErrorState(
              error: error,
              onRetry: () => ref.invalidate(
                stashGameEventsProvider(StashEventsWindow.previous),
              ),
            ),
          ),
          data: (data) {
            final events = data.items;
            if (_itemsSignature == null && events.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                _seedIfNeeded(events);
              });
            }

            final source = _items.isNotEmpty ? _items : events;
            if (source.isEmpty) {
              return const SizedBox(
                height: 140,
                child: EmptyState(
                  title: 'Events',
                  message: 'No past industry events to show right now.',
                  icon: Icons.event_busy_outlined,
                ),
              );
            }

            final visibleCount = _visibleItemCount.clamp(0, source.length);
            final segments = _buildPreviewSegments(source, visibleCount);
            if (segments.isEmpty) {
              return const SizedBox(
                height: 140,
                child: EmptyState(
                  title: 'Events',
                  message: 'No past industry events to show right now.',
                  icon: Icons.event_busy_outlined,
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
                  height: StashEventsTimelineSection._stripHeight,
                  child: ListView.separated(
                    controller: _timelineScrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: segments.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(width: 20),
                    itemBuilder: (context, index) {
                      if (hasMore && index == segments.length) {
                        return const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: Icon(Icons.more_horiz),
                            ),
                          ),
                        );
                      }
                      final segment = segments[index];
                      return _StashEventsDayGroup(
                        dayLabel: releaseDayLabel(segment.day),
                        events: segment.items,
                        startIndex: segment.startIndex,
                        selectedIndex: safeIndex,
                        onSelect: (globalIndex) {
                          setState(() => _selectedIndex = globalIndex);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                StashEventReleaseCard(
                  event: selected,
                  width: double.infinity,
                  onTap: () => _openEvent(selected),
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
  final List<StashGameEvent> items;
  final int startIndex;
}

List<_PreviewSegment> _buildPreviewSegments(List<StashGameEvent> items, int maxCount) {
  final groups = groupStashEventsByDay(items);
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

class _StashEventsDayGroup extends StatelessWidget {
  const _StashEventsDayGroup({
    required this.dayLabel,
    required this.events,
    required this.startIndex,
    required this.selectedIndex,
    required this.onSelect,
  });

  final String dayLabel;
  final List<StashGameEvent> events;
  final int startIndex;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.55);
    final postersWidth = events.length * StashEventPosterCard.width +
        (events.length > 1 ? (events.length - 1) * 12 : 0);

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
            for (var i = 0; i < events.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              StashEventPosterCard(
                event: events[i],
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
