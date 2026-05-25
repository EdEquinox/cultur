import 'package:flutter/material.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/widgets/cast_grid_page_body.dart';

import 'package:yamtrack/src/models/tv/series_detail.dart';
import 'package:yamtrack/src/providers/tv_catalog_providers.dart';

/// Full merged cast + guest list for a TV **season** or **episode** (not whole-series cast).
class TvContextCastListPage extends ConsumerWidget {
  const TvContextCastListPage({
    required this.mediaId,
    required this.seasonNumber,
    this.episodeNumber,
    super.key,
  });

  final String mediaId;
  final int seasonNumber;
  /// When set, lists this episode’s credits (cast + guests from catalog).
  final int? episodeNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final ep = episodeNumber;

    if (ep != null) {
      final req = TvEpisodeDetailCatalogRequest(
        mediaId: mediaId,
        seasonNumber: seasonNumber,
        episodeNumber: ep,
        username: username,
      );
      final async = ref.watch(tvEpisodeDetailCatalogProvider(req));
      return Scaffold(
        appBar: const CulturAppBar(),
        extendBody: true,
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(tvEpisodeDetailCatalogProvider(req)),
          ),
          data: (detail) => CastGridPageBody(
            cast: detail.mergedCastAndGuests(),
            emptyTitle: 'No cast listed',
            emptyMessage: 'There is no cast or guest star information for this episode.',
          ),
        ),
      );
    }

    final seasonReq = TvSeasonDetailCatalogRequest(
      mediaId: mediaId,
      seasonNumber: seasonNumber,
      username: username,
    );
    final seasonAsync = ref.watch(tvSeasonDetailCatalogProvider(seasonReq));
    return Scaffold(
      appBar: const CulturAppBar(),
      extendBody: true,
      body: seasonAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(tvSeasonDetailCatalogProvider(seasonReq)),
        ),
        data: (detail) {
          final people = mergeCreditPeopleLists(
            detail.cast,
            detail.distinctGuestStarsAcrossEpisodes(),
          );
          return CastGridPageBody(
            cast: people,
            emptyTitle: 'No cast listed',
            emptyMessage: 'There is no cast or guest star information for this season.',
          );
        },
      ),
    );
  }
}
