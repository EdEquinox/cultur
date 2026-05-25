import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';

import '../../../navbar/bar.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';

class SeriesSeasonsListPage extends ConsumerWidget {
  const SeriesSeasonsListPage({required this.mediaId, super.key});

  final String mediaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tvSeasonListCatalogProvider(mediaId));

    return Scaffold(
      appBar: const CulturAppBar(),
      extendBody: true,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(tvSeasonListCatalogProvider(mediaId)),
        ),
        data: (data) {
          if (data.items.isEmpty) {
            return const Center(child: Text('No seasons listed for this series.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            itemCount: data.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final s = data.items[index];
              final subtitleParts = <String>[
                '${s.episodeCount} episode${s.episodeCount == 1 ? '' : 's'}',
                if (s.airDate != null && s.airDate!.trim().isNotEmpty) s.airDate!,
              ];
              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                leading: _SeasonTileLeading(url: s.posterUrl),
                title: Text(s.name),
                subtitle: Text(subtitleParts.join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/tv/$mediaId/seasons/${s.seasonNumber}'),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.tv,
      ),
    );
  }
}

class _SeasonTileLeading extends StatelessWidget {
  const _SeasonTileLeading({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final size = 48.0;
    if (url != null && url!.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url!,
          width: size,
          height: size * 1.45,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _placeholder(context, size),
        ),
      );
    }
    return _placeholder(context, size);
  }

  Widget _placeholder(BuildContext context, double size) {
    return Container(
      width: size,
      height: size * 1.2,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.movie_filter_outlined, color: Theme.of(context).colorScheme.outline),
    );
  }
}
