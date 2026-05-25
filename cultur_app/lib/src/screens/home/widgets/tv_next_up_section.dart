import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/home/widgets/shelf_heading.dart';
import 'package:yamtrack/src/screens/home/widgets/tv_next_up_episode_row.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

/// TV home "Next up" — horizontal episode rows with watched control (detail-style).
class TvNextUpSection extends ConsumerWidget {
  const TvNextUpSection({
    super.key,
    required this.title,
    required this.icon,
    required this.state,
    required this.emptyMessage,
    required this.username,
    this.onSeeAll,
  });

  final String title;
  final IconData icon;
  final AsyncValue<CatalogListData> state;
  final String emptyMessage;
  final String username;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeading(title: title, icon: icon, onSeeAll: onSeeAll),
        const SizedBox(height: 12),
        state.when(
          loading: () => const SizedBox(
            height: 112,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => SizedBox(
            height: 112,
            child: ErrorState(error: error),
          ),
          data: (data) {
            final all = catalogContinueWatchingSortedNewestFirst(data);
            final preview = all.take(5).toList();
            if (preview.isEmpty) {
              return SizedBox(
                height: 140,
                child: EmptyState(
                  title: title,
                  message: emptyMessage,
                  icon: icon,
                ),
              );
            }

            return SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: preview.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return TvNextUpEpisodeRow(
                    item: preview[index],
                    username: username,
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
