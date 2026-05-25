import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/games/stash_game_event.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/stash_event_release_card.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

/// Full events shelf grouped by release day.
class StashEventsShelfList extends StatefulWidget {
  const StashEventsShelfList({
    super.key,
    required this.events,
    required this.onEventTap,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
    this.initialVisibleCount = 24,
    this.loadMoreBatchSize = 12,
  });

  final List<StashGameEvent> events;
  final ValueChanged<StashGameEvent>? onEventTap;
  final EdgeInsetsGeometry padding;
  final int initialVisibleCount;
  final int loadMoreBatchSize;

  @override
  State<StashEventsShelfList> createState() => _StashEventsShelfListState();
}

class _StashEventsShelfListState extends State<StashEventsShelfList> {
  final ScrollController _scrollController = ScrollController();
  late int _visibleCount;

  @override
  void initState() {
    super.initState();
    _visibleCount = widget.initialVisibleCount.clamp(0, widget.events.length);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(StashEventsShelfList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events.length != widget.events.length) {
      _visibleCount = widget.initialVisibleCount.clamp(0, widget.events.length);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasMore => _visibleCount < widget.events.length;

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore) {
      return;
    }
    final metrics = _scrollController.position;
    if (metrics.maxScrollExtent > 0 &&
        metrics.pixels < metrics.maxScrollExtent - 200) {
      return;
    }
    _loadMore();
  }

  void _loadMore() {
    if (!_hasMore) {
      return;
    }
    setState(() {
      _visibleCount = (_visibleCount + widget.loadMoreBatchSize)
          .clamp(0, widget.events.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.events.take(_visibleCount).toList();
    final groups = groupStashEventsByDay(visible);
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      if (g > 0) {
        children.add(const SizedBox(height: 24));
      }
      children.add(_ReleaseDayHeader(label: releaseDayLabel(group.day)));
      children.add(const SizedBox(height: 12));
      for (final event in group.items) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StashEventReleaseCard(
              event: event,
              width: double.infinity,
              onTap: () {
                if (widget.onEventTap != null) {
                  widget.onEventTap!(event);
                } else {
                  context.push('/games/events/${event.slug}');
                }
              },
            ),
          ),
        );
      }
    }

    if (_hasMore) {
      children.add(const SizedBox(height: 16));
      children.add(
        const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(Icons.more_horiz),
          ),
        ),
      );
    }

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
        children: children,
      ),
    );
  }
}

class _ReleaseDayHeader extends StatelessWidget {
  const _ReleaseDayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: lineColor),
      ],
    );
  }
}
