import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/models/games/stash_game_event_detail.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/screens/helpers/empty_state.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/media/games/events/event_game_poster_card.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/stash_event_release_card.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class GameEventDetailPage extends ConsumerWidget {
  const GameEventDetailPage({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(stashGameEventDetailProvider(slug));

    return Scaffold(
      appBar: const CulturAppBar(),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(stashGameEventDetailProvider(slug)),
        ),
        data: (detail) {
          final event = detail.event;
          final items = detail.items;
          final when = releaseDayLabel(event.startsAt.toLocal());
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              StashEventReleaseCard(
                event: event,
                width: double.infinity,
                onTap: () => _openUrl(event.stashUrl),
              ),
              const SizedBox(height: 8),
              Text(
                when,
                style: CulturCatalogTypography.listMeta(theme, scheme),
              ),
              const SizedBox(height: 16),
              Text(
                'Games showcased',
                style: CulturCatalogTypography.sectionHeading(theme),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const EmptyState(
                  title: 'No games listed',
                  message: 'IGDB has no games linked to this event yet.',
                  icon: Icons.videogame_asset_off_outlined,
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 6,
                    childAspectRatio: EventGamePosterCard.gridChildAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return EventGamePosterCard(
                      item: item,
                      onTap: () => _onGameTap(context, item),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  void _onGameTap(BuildContext context, StashEventGameItem item) {
    final mediaId = item.mediaId;
    if (mediaId == null || mediaId.isEmpty) {
      return;
    }
    context.push('/games/$mediaId');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
