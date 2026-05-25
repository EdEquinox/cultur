import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/boardgame_custom_lists_controller.dart';
import 'package:yamtrack/src/controllers/book_custom_lists_controller.dart';
import 'package:yamtrack/src/controllers/custom_lists_controller.dart';
import 'package:yamtrack/src/controllers/game_custom_lists_controller.dart';
import 'package:yamtrack/src/controllers/music_custom_lists_controller.dart';
import 'package:yamtrack/src/controllers/tv_custom_lists_controller.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/lists/custom_movie_lists_data.dart';
import 'package:yamtrack/src/models/lists/tv_custom_lists_data.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';

final customListsControllerProvider = Provider<CustomListsController>((ref) {
  return CustomListsController(
    ref.read(apiClientProvider),
    ref.read(sessionStorageProvider),
  );
});

final customMovieListsProvider = FutureProvider.autoDispose<CustomMovieListsData>((
  ref,
) async {
  final username = ref.watch(authControllerProvider).asData?.value.session?.username;
  if (username == null || username.isEmpty) {
    return const CustomMovieListsData(lists: []);
  }
  final tracking =
      await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.movie).future);
  return ref.read(customListsControllerProvider).load(
        username,
        movieTracking: tracking.items,
      );
});

final customTvListsControllerProvider = Provider<TvCustomListsController>((ref) {
  return TvCustomListsController(
    ref.read(apiClientProvider),
    ref.read(sessionStorageProvider),
  );
});

final customTvListsProvider = FutureProvider.autoDispose<TvCustomListsData>((ref) async {
  final username = ref.watch(authControllerProvider).asData?.value.session?.username;
  if (username == null || username.isEmpty) {
    return const TvCustomListsData(lists: []);
  }
  final tracking = await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.tv).future);
  return ref.read(customTvListsControllerProvider).load(
        username,
        tvTracking: tracking.items,
      );
});

final customGameListsControllerProvider = Provider<GameCustomListsController>((ref) {
  return GameCustomListsController(
    ref.read(apiClientProvider),
    ref.read(sessionStorageProvider),
  );
});

final customGameListsProvider = FutureProvider.autoDispose<CustomMovieListsData>((ref) async {
  final username = ref.watch(authControllerProvider).asData?.value.session?.username;
  if (username == null || username.isEmpty) {
    return const CustomMovieListsData(lists: []);
  }
  final tracking = await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.game).future);
  return ref.read(customGameListsControllerProvider).load(
        username,
        gameTracking: tracking.items,
      );
});

final customBoardgameListsControllerProvider =
    Provider<BoardgameCustomListsController>((ref) {
  return BoardgameCustomListsController(
    ref.read(apiClientProvider),
    ref.read(sessionStorageProvider),
  );
});

final customBoardgameListsProvider = FutureProvider.autoDispose<CustomMovieListsData>((ref) async {
  final username = ref.watch(authControllerProvider).asData?.value.session?.username;
  if (username == null || username.isEmpty) {
    return const CustomMovieListsData(lists: []);
  }
  final tracking =
      await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.boardgame).future);
  return ref.read(customBoardgameListsControllerProvider).load(
        username,
        boardgameTracking: tracking.items,
      );
});

final customBookListsControllerProvider = Provider<BookCustomListsController>((ref) {
  return BookCustomListsController(
    ref.read(apiClientProvider),
    ref.read(sessionStorageProvider),
  );
});

final customBookListsProvider = FutureProvider.autoDispose<CustomMovieListsData>((ref) async {
  final username = ref.watch(authControllerProvider).asData?.value.session?.username;
  if (username == null || username.isEmpty) {
    return const CustomMovieListsData(lists: []);
  }
  final tracking = await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.book).future);
  return ref.read(customBookListsControllerProvider).load(
        username,
        bookTracking: tracking.items,
      );
});

final customMusicListsControllerProvider = Provider<MusicCustomListsController>((ref) {
  return MusicCustomListsController(
    ref.read(apiClientProvider),
    ref.read(sessionStorageProvider),
  );
});

final customMusicListsProvider = FutureProvider.autoDispose<CustomMovieListsData>((ref) async {
  final username = ref.watch(authControllerProvider).asData?.value.session?.username;
  if (username == null || username.isEmpty) {
    return const CustomMovieListsData(lists: []);
  }
  final tracking = await ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.music).future);
  return ref.read(customMusicListsControllerProvider).load(
        username,
        musicTracking: tracking.items,
      );
});
