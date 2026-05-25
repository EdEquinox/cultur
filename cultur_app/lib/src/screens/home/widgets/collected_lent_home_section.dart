import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/collected_lent_providers.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/collections/widgets/collected_lent_grid_card.dart';
import 'package:yamtrack/src/screens/home/widgets/shelf_heading.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

/// Lent-out collected titles on the category catalog home (grid, hidden when empty).
class CollectedLentHomeSection extends ConsumerWidget {
  const CollectedLentHomeSection({
    required this.mediaScope,
    super.key,
  });

  final LibraryMediaScope mediaScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lentAsync = ref.watch(collectedLentForScopeProvider(mediaScope));

    return lentAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShelfHeading(
              title: 'Lent out',
              icon: Icons.outbound_outlined,
              onSeeAll: () => context.push(mediaScope.path('owned')),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 6,
                childAspectRatio: CollectedLentGridCard.gridChildAspectRatio,
              ),
              itemBuilder: (context, index) {
                final row = items[index];
                final media = row.tracking.media;
                return CollectedLentGridCard(
                  media: media,
                  lent: row.lent,
                  onTap: () => context.push(catalogItemDetailPath(media)),
                  onLongPress: () => _markReturned(context, ref, row.tracking),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _markReturned(
    BuildContext context,
    WidgetRef ref,
    TrackingItem tracking,
  ) async {
    try {
      final message = await ref.read(trackingMutationControllerProvider).clearCollectedLent(
            username: tracking.username,
            media: tracking.media,
            tracking: tracking,
          );
      ref.invalidate(libraryTrackingForScopeProvider(mediaScope));
      if (mediaScope == LibraryMediaScope.game) {
        final username = tracking.username.trim();
        if (username.isNotEmpty) {
          invalidateGamesHomeCaches(ref, username: username);
        }
      }
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (context.mounted) {
        showApiErrorSnackBar(context, error);
      }
    }
  }
}
