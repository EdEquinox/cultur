import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/providers/movie_detail_providers.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/widgets/cast_grid_page_body.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';

class MovieCastListPage extends ConsumerWidget {
  const MovieCastListPage({required this.mediaId, this.isTv = false, super.key});

  final String mediaId;
  final bool isTv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final request = MovieDetailRequest(mediaId: mediaId, username: username, isTv: isTv);
    final detailAsync = ref.watch(movieDetailProvider(request));

    return Scaffold(
      appBar: const CulturAppBar(),
      extendBody: true,
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(movieDetailProvider(request)),
        ),
        data: (detail) => CastGridPageBody(
          cast: detail.cast,
          emptyTitle: 'No cast listed',
          emptyMessage: 'There is no cast information for this title.',
        ),
      ),
    );
  }
}
