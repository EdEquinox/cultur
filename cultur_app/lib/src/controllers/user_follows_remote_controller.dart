import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/books/book_publisher_link.dart';
import 'package:yamtrack/src/models/books/favorite_publishers.dart';
import 'package:yamtrack/src/models/games/favorite_companies.dart';
import 'package:yamtrack/src/models/games/game_company_link.dart';
import 'package:yamtrack/src/models/movie/movie_detail_person.dart';
import 'package:yamtrack/src/models/person/favorite_people.dart';
import 'package:yamtrack/src/models/person/user_follow_entry.dart';
import 'package:yamtrack/src/services/follows_api.dart';
import 'package:yamtrack/src/utils/follow_entity_utils.dart';
import 'package:yamtrack/src/utils/musicbrainz_person_utils.dart';
import 'package:yamtrack/src/utils/stored_json_lists.dart';

/// Remote-backed unified follows (`/backend/follows`).
class UserFollowsRemoteController {
  UserFollowsRemoteController({
    required ApiClient api,
    required SessionStorage storage,
  })  : _api = FollowsApi(api),
        _storage = storage;

  final FollowsApi _api;
  final SessionStorage _storage;

  Future<List<UserFollowEntry>> listAll(String username) async {
    await _migrateLocalIfNeeded(username);
    return _api.listFollows(username: username);
  }

  Future<FavoritePeopleData> loadFavoritePeople(String username) async {
    final rows = await listAll(username);
    final people = rows
        .where((row) => row.entityKind == 'person' || row.entityKind == 'music_artist')
        .map(
          (row) => MovieDetailPerson(
            personId: row.routePersonId,
            name: row.name,
            imageUrl: row.imageUrl,
          ),
        )
        .toList();
    people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return FavoritePeopleData(people: people);
  }

  Future<FavoriteCompaniesData> loadFavoriteCompanies(String username) async {
    await _migrateLocalIfNeeded(username);
    final rows = await _api.listFollows(username: username, entityKind: 'company');
    final companies = rows
        .map(
          (row) => GameCompanyLink(
            companyId: row.routePersonId,
            name: row.name,
            imageUrl: row.imageUrl,
            role: row.companyRole ?? 'publisher',
          ),
        )
        .toList();
    return FavoriteCompaniesData(companies: companies);
  }

  Future<FavoritePublishersData> loadFavoritePublishers(String username) async {
    await _migrateLocalIfNeeded(username);
    final rows = await _api.listFollows(username: username, entityKind: 'publisher');
    final publishers = rows
        .map(
          (row) => BookPublisherLink(
            publisherId: row.routePersonId,
            name: row.name,
          ),
        )
        .toList();
    return FavoritePublishersData(publishers: publishers);
  }

  Future<List<UserFollowEntry>> loadMusicArtists(String username) async {
    return _api.listFollows(username: username, entityKind: 'music_artist');
  }

  Future<void> toggleFavoritePerson({
    required String username,
    required String routePersonId,
    required String name,
    String? imageUrl,
    String? companyRole,
  }) async {
    final rows = await listAll(username);
    final existing = rows.where((row) => row.routePersonId == routePersonId).toList();
    if (existing.isNotEmpty) {
      await _api.unfollow(
        username: username,
        routeOrServerPersonId: existing.first.serverPersonId,
      );
      return;
    }
    final payload = followPayloadFromRouteId(
      routePersonId: routePersonId,
      companyRole: companyRole,
    );
    await _api.follow(
      username: username,
      entityKind: payload.entityKind,
      sourceCode: payload.sourceCode,
      externalId: payload.externalId,
      name: name,
      imageUrl: imageUrl,
    );
  }

  Future<void> toggleFavoriteCompany({
    required String username,
    required String companyId,
    required String name,
    required String role,
    String? imageUrl,
  }) async {
    final rows = await _api.listFollows(username: username, entityKind: 'company');
    final existing = rows.where((row) => row.routePersonId == companyId).toList();
    if (existing.isNotEmpty) {
      await _api.unfollow(
        username: username,
        routeOrServerPersonId: existing.first.serverPersonId,
      );
      return;
    }
    await _api.follow(
      username: username,
      entityKind: 'company',
      sourceCode: 'igdb',
      externalId: companyId,
      name: name,
      imageUrl: imageUrl,
    );
  }

  Future<void> toggleFavoritePublisher({
    required String username,
    required String publisherId,
    required String name,
  }) async {
    final rows = await _api.listFollows(username: username, entityKind: 'publisher');
    final existing = rows.where((row) => row.routePersonId == publisherId).toList();
    if (existing.isNotEmpty) {
      await _api.unfollow(
        username: username,
        routeOrServerPersonId: existing.first.serverPersonId,
      );
      return;
    }
    await _api.follow(
      username: username,
      entityKind: 'publisher',
      sourceCode: 'manual',
      externalId: publisherId,
      name: name,
    );
  }

  Future<void> toggleMusicArtist({
    required String username,
    required String artistMbid,
    required String name,
    String? imageUrl,
  }) async {
    final routeId = musicArtistPersonId(artistMbid);
    await toggleFavoritePerson(
      username: username,
      routePersonId: routeId,
      name: name,
      imageUrl: imageUrl,
    );
  }

  Future<void> _migrateLocalIfNeeded(String username) async {
    await _migrateFavoritePeople(username);
    await _migrateFavoriteCompanies(username);
    await _migrateFavoritePublishers(username);
  }

  Future<void> _migrateFavoritePeople(String username) async {
    final key = StorageKeys.favoritePeople(username);
    final raw = await _storage.read(key: key);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    final people = decodeStoredJsonList(
      raw,
      (json) => MovieDetailPerson(
        personId: json['personId']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        imageUrl: json['imageUrl']?.toString(),
      ),
      compare: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    for (final person in people) {
      final personId = person.personId?.trim() ?? '';
      if (personId.isEmpty || person.name.isEmpty) {
        continue;
      }
      if (isMusicArtistPersonId(personId)) {
        continue;
      }
      final payload = followPayloadFromRouteId(routePersonId: personId);
      await _api.follow(
        username: username,
        entityKind: payload.entityKind,
        sourceCode: payload.sourceCode,
        externalId: payload.externalId,
        name: person.name,
        imageUrl: person.imageUrl,
      );
    }
    await _storage.delete(key: key);
  }

  Future<void> _migrateFavoriteCompanies(String username) async {
    final key = StorageKeys.favoriteCompanies(username);
    final raw = await _storage.read(key: key);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    final companies = decodeStoredJsonList(raw, GameCompanyLink.fromJson);
    for (final company in companies) {
      if (!company.isValid) {
        continue;
      }
      await _api.follow(
        username: username,
        entityKind: 'company',
        sourceCode: 'igdb',
        externalId: company.companyId,
        name: company.name,
        imageUrl: company.imageUrl,
      );
    }
    await _storage.delete(key: key);
  }

  Future<void> _migrateFavoritePublishers(String username) async {
    final key = StorageKeys.favoritePublishers(username);
    final raw = await _storage.read(key: key);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    final publishers = decodeStoredJsonList(raw, BookPublisherLink.fromJson);
    for (final publisher in publishers) {
      if (!publisher.isValid) {
        continue;
      }
      await _api.follow(
        username: username,
        entityKind: 'publisher',
        sourceCode: 'manual',
        externalId: publisher.publisherId,
        name: publisher.name,
      );
    }
    await _storage.delete(key: key);
  }
}
