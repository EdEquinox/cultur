import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/user_follows_remote_controller.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/models/person/favorite_people.dart';
import 'package:yamtrack/src/models/person/person_catalog_detail.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/utils/musicbrainz_person_utils.dart';
import 'package:yamtrack/src/utils/person_route_utils.dart';

export 'package:yamtrack/src/models/person/favorite_people.dart';

/// Music artist pages can include a large discography; allow extra time vs TMDB people.
const _musicArtistDetailReceiveTimeout = Duration(seconds: 45);

final personCatalogDetailProvider = FutureProvider.autoDispose
    .family<PersonCatalogDetail, String>((ref, personId) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        personCatalogApiPath(personId),
        receiveTimeout: isMusicBrainzArtistPersonId(personId)
            ? _musicArtistDetailReceiveTimeout
            : null,
      );
      return PersonCatalogDetail.fromJson(payload);
    });

class UserMovieTrackingDigest {
  const UserMovieTrackingDigest({
    required this.watchedIds,
    required this.watchlistIds,
    required this.byMediaId,
  });

  final Set<String> watchedIds;
  final Set<String> watchlistIds;
  final Map<String, TrackingItem> byMediaId;
}

final userMovieTrackingDigestProvider =
    FutureProvider.autoDispose<UserMovieTrackingDigest>((ref) async {
  final authState = ref.watch(authControllerProvider).asData?.value;
  final username = authState?.session?.username;
  if (username == null || username.isEmpty) {
    return const UserMovieTrackingDigest(
      watchedIds: {},
      watchlistIds: {},
      byMediaId: {},
    );
  }
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson(
    '/backend/tracking',
    queryParameters: {
      'username': username,
      'mediaType': 'movie',
      'limit': 500,
    },
  );
  final list = TrackingListData.fromJson(payload);
  final watched = <String>{};
  final watchlist = <String>{};
  final byId = <String, TrackingItem>{};
  for (final entry in list.items) {
    byId[entry.media.id] = entry;
    if (trackingIsWatched(entry)) {
      watched.add(entry.media.id);
    }
    if (trackingIsInWatchlist(entry)) {
      watchlist.add(entry.media.id);
    }
  }
  return UserMovieTrackingDigest(
    watchedIds: watched,
    watchlistIds: watchlist,
    byMediaId: byId,
  );
});

final userFollowsControllerProvider = Provider<UserFollowsRemoteController>((ref) {
  return UserFollowsRemoteController(
    api: ref.read(apiClientProvider),
    storage: ref.read(sessionStorageProvider),
  );
});

final favoritePeopleControllerProvider = Provider<UserFollowsRemoteController>((ref) {
  return ref.read(userFollowsControllerProvider);
});

final favoritePeopleProvider = FutureProvider.autoDispose<FavoritePeopleData>((ref) async {
  final username = ref.watch(authControllerProvider).asData?.value.session?.username;
  if (username == null || username.isEmpty) {
    return const FavoritePeopleData(people: []);
  }
  return ref.read(favoritePeopleControllerProvider).loadFavoritePeople(username);
});
