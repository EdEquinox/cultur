import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/providers/person_providers.dart';
import 'package:yamtrack/src/utils/musicbrainz_person_utils.dart';

/// Followed music artists from `/backend/follows` (`entityKind=music_artist`).
class FollowedMusicArtistsData {
  const FollowedMusicArtistsData({required this.people});

  final List<MovieDetailPerson> people;

  Set<String> get artistMbids {
    final ids = <String>{};
    for (final person in people) {
      final rawId = parseMusicBrainzArtistPersonId(person.personId ?? '');
      if (rawId != null) {
        ids.add(compactArtistMbid(rawId));
      }
    }
    return ids;
  }
}

final followedMusicArtistsProvider = FutureProvider.autoDispose
    .family<FollowedMusicArtistsData, String>((ref, username) async {
  if (username.isEmpty) {
    return const FollowedMusicArtistsData(people: []);
  }
  final rows = await ref.read(userFollowsControllerProvider).loadMusicArtists(username);
  final people = rows
      .map(
        (row) => MovieDetailPerson(
          personId: row.routePersonId,
          name: row.name,
          imageUrl: row.imageUrl,
        ),
      )
      .toList();
  people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return FollowedMusicArtistsData(people: people);
});

/// Artist MBIDs the user follows (compact, for Follow button state).
final followedMusicArtistIdsProvider = FutureProvider.autoDispose
    .family<Set<String>, String>((ref, username) async {
  final data = await ref.watch(followedMusicArtistsProvider(username).future);
  return data.artistMbids;
});
