import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/models/movie/movie_home_shelf_data.dart';
import 'package:yamtrack/src/models/tv/tv_shows_home_shelf_data.dart';

final movieHomeShelvesProvider = FutureProvider.autoDispose<MovieHomeShelfData>((ref) async {
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson('/catalog/movies/home');
  return MovieHomeShelfData.fromJson(payload);
});

final tvHomeShelvesProvider = FutureProvider.autoDispose
    .family<TvShowsHomeShelfData, String>((ref, username) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/tv/home',
        queryParameters: {
          if (username.isNotEmpty) 'username': username,
        },
      );
      return TvShowsHomeShelfData.fromJson(payload);
    });

AsyncValue<CatalogListData> movieHomeShelfNowPlaying(AsyncValue<MovieHomeShelfData> home) {
  return home.when(
    data: (d) => AsyncData(d.nowPlaying),
    loading: () => const AsyncLoading<CatalogListData>(),
    error: (e, st) => AsyncValue.error(e, st),
  );
}

AsyncValue<CatalogListData> movieHomeShelfUpcoming(AsyncValue<MovieHomeShelfData> home) {
  return home.when(
    data: (d) => AsyncData(d.upcoming),
    loading: () => const AsyncLoading<CatalogListData>(),
    error: (e, st) => AsyncValue.error(e, st),
  );
}

AsyncValue<CatalogListData> tvHomeShelfNextUp(AsyncValue<TvShowsHomeShelfData> home) {
  return home.when(
    data: (d) => AsyncData(d.nextUp),
    loading: () => const AsyncLoading<CatalogListData>(),
    error: (e, st) => AsyncValue.error(e, st),
  );
}

AsyncValue<CatalogListData> tvHomeShelfUpcomingEpisodes(AsyncValue<TvShowsHomeShelfData> home) {
  return home.when(
    data: (d) => AsyncData(d.upcomingEpisodes),
    loading: () => const AsyncLoading<CatalogListData>(),
    error: (e, st) => AsyncValue.error(e, st),
  );
}
