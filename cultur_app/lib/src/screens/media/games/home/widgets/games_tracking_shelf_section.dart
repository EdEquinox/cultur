import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/games/game_home_shelf_item.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/home/widgets/shelf_heading.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/game_home_poster_card.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

class GamesTrackingShelfSection extends StatelessWidget {
  const GamesTrackingShelfSection({
    super.key,
    required this.title,
    required this.icon,
    required this.state,
    required this.emptyMessage,
    this.onSeeAll,
    this.badgeForItem,
  });

  final String title;
  final IconData icon;
  final AsyncValue<List<GameHomeShelfItem>> state;
  final String emptyMessage;
  final VoidCallback? onSeeAll;
  final ({IconData icon, String tooltip})? Function(GameHomeShelfItem item)? badgeForItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeading(title: title, icon: icon, onSeeAll: onSeeAll),
        const SizedBox(height: 12),
        state.when(
          loading: () => SizedBox(
            height: GameHomePosterCard.cardHeight,
            child: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => SizedBox(
            height: 180,
            child: ErrorState(error: error),
          ),
          data: (items) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: EmptyState(
                  title: 'Nothing here',
                  message: emptyMessage,
                  icon: icon,
                ),
              );
            }
            return SizedBox(
              height: GameHomePosterCard.cardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final badge = badgeForItem?.call(item);
                  return GameHomePosterCard(
                    item: item,
                    badgeIcon: badge?.icon,
                    badgeTooltip: badge?.tooltip,
                    onTap: () => context.push(catalogItemDetailPath(item.media)),
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
