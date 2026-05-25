import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/providers/next_to_watch_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/home/widgets/next_to_watch_poster_card.dart';
import 'package:yamtrack/src/screens/home/widgets/shelf_heading.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

class NextToWatchShelfSection extends StatelessWidget {
  const NextToWatchShelfSection({
    super.key,
    required this.title,
    required this.state,
    required this.username,
    required this.emptyMessage,
    this.onSeeAll,
  });

  final String title;
  final AsyncValue<List<NextToWatchShelfItem>> state;
  final String username;
  final String emptyMessage;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeading(
          title: title,
          icon: Icons.play_circle_outline,
          onSeeAll: onSeeAll,
        ),
        const SizedBox(height: 12),
        state.when(
          loading: () => const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => SizedBox(
            height: 180,
            child: ErrorState(error: error),
          ),
          data: (items) {
            const cap = 5;
            final row = items.length > cap ? items.sublist(0, cap) : items;
            if (row.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: EmptyState(
                  title: 'Nothing queued yet',
                  message: emptyMessage.isNotEmpty
                      ? emptyMessage
                      : 'Pin series to priority or add them to your watchlist — they will show here.',
                  icon: Icons.schedule_outlined,
                ),
              );
            }

            return SizedBox(
              height: NextToWatchPosterCard.cardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: row.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final entry = row[index];
                  return Align(
                    alignment: Alignment.topCenter,
                    child: NextToWatchPosterCard(
                      item: entry,
                      username: username,
                      onTap: () => context.push(catalogItemDetailPath(entry.media)),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
