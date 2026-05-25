import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/catalog/catalog_list_data.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

@immutable
class CatalogBrowseRequest {
  const CatalogBrowseRequest({
    required this.section,
    required this.query,
    this.genre = '',
    this.keyword = '',
    this.companyId = '',
    this.companyRole = '',
    this.franchiseId = '',
    this.collectionId = '',
    this.platform = '',
    this.gameMode = '',
    this.playerPerspective = '',
    this.gameType = '',
    this.igdbGenre = '',
    this.bookLanguage = '',
    this.publishYear = '',
    this.bookSources = '',
  });

  final String section;
  final String query;
  final String genre;
  final String keyword;
  final String companyId;
  final String companyRole;
  final String franchiseId;
  final String collectionId;
  final String platform;
  final String gameMode;
  final String playerPerspective;
  final String gameType;
  /// IGDB genre ids (comma-separated); distinct from TMDB [genre] on movies/TV.
  final String igdbGenre;
  /// Open Library language code (e.g. eng).
  final String bookLanguage;
  /// Four-digit first publish year filter (books).
  final String publishYear;
  /// Catalog provider: hardcover | openlibrary | porbase (empty = Hardcover).
  final String bookSources;

  @override
  bool operator ==(Object other) {
    return other is CatalogBrowseRequest &&
        other.section == section &&
        other.query == query &&
        other.genre == genre &&
        other.keyword == keyword &&
        other.companyId == companyId &&
        other.companyRole == companyRole &&
        other.franchiseId == franchiseId &&
        other.collectionId == collectionId &&
        other.platform == platform &&
        other.gameMode == gameMode &&
        other.playerPerspective == playerPerspective &&
        other.gameType == gameType &&
        other.igdbGenre == igdbGenre &&
        other.bookLanguage == bookLanguage &&
        other.publishYear == publishYear &&
        other.bookSources == bookSources;
  }

  @override
  int get hashCode => Object.hash(
        section,
        query,
        genre,
        keyword,
        companyId,
        companyRole,
        franchiseId,
        collectionId,
        platform,
        gameMode,
        playerPerspective,
        gameType,
        igdbGenre,
        bookLanguage,
        publishYear,
        bookSources,
      );
}

final moviesProvider = FutureProvider.autoDispose
    .family<CatalogListData, CatalogBrowseRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/movies',
        queryParameters: {
          'section': request.section,
          if (request.query.isNotEmpty) 'q': request.query,
          if (request.genre.isNotEmpty) 'genre': request.genre,
          if (request.keyword.isNotEmpty) 'keyword': request.keyword,
        },
      );
      return CatalogListData.fromJson(payload);
    });

/// TMDB upcoming movies for a single catalog page (shelf infinite scroll).
final upcomingMoviesPageProvider = FutureProvider.autoDispose
    .family<List<CatalogItem>, int>((ref, page) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/movies',
        queryParameters: {
          'section': 'upcoming',
          'page': '$page',
        },
      );
      final data = CatalogListData.fromJson(payload);
      return data.items.where(catalogItemIsUpcomingCatalogSlice).toList();
    });

final tvShowsProvider = FutureProvider.autoDispose
    .family<CatalogListData, CatalogBrowseRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/tv',
        queryParameters: {
          'section': request.section,
          if (request.query.isNotEmpty) 'q': request.query,
          if (request.genre.isNotEmpty) 'genre': request.genre,
          if (request.keyword.isNotEmpty) 'keyword': request.keyword,
        },
      );
      return CatalogListData.fromJson(payload);
    });

final gamesProvider = FutureProvider.autoDispose
    .family<CatalogListData, CatalogBrowseRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/games',
        queryParameters: {
          'section': request.section,
          if (request.query.isNotEmpty) 'q': request.query,
          if (request.companyId.isNotEmpty) 'company_id': request.companyId,
          if (request.companyRole.isNotEmpty) 'company_role': request.companyRole,
          if (request.franchiseId.isNotEmpty) 'franchise_id': request.franchiseId,
          if (request.collectionId.isNotEmpty) 'collection_id': request.collectionId,
          if (request.platform.isNotEmpty) 'platform': request.platform,
          if (request.igdbGenre.isNotEmpty) 'genre': request.igdbGenre,
          if (request.gameMode.isNotEmpty) 'game_mode': request.gameMode,
          if (request.playerPerspective.isNotEmpty) 'player_perspective': request.playerPerspective,
          if (request.gameType.isNotEmpty) 'game_type': request.gameType,
          'page': '1',
        },
      );
      return CatalogListData.fromJson(payload);
    });

final boardgamesProvider = FutureProvider.autoDispose
    .family<CatalogListData, CatalogBrowseRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/boardgames',
        queryParameters: {
          'section': request.section,
          if (request.query.isNotEmpty) 'q': request.query,
          'page': '1',
        },
      );
      return CatalogListData.fromJson(payload);
    });

final booksProvider = FutureProvider.autoDispose
    .family<CatalogListData, CatalogBrowseRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final isPopularHome =
          request.section == 'popular' && request.query.trim().isEmpty;
      final payload = await client.getJson(
        '/catalog/books',
        queryParameters: {
          'section': request.section,
          if (request.query.isNotEmpty) 'q': request.query,
          if (request.bookLanguage.isNotEmpty) 'language': request.bookLanguage,
          if (request.publishYear.isNotEmpty) 'year': request.publishYear,
          if (request.genre.isNotEmpty) 'genre': request.genre,
          if (request.bookSources.isNotEmpty) 'sources': request.bookSources,
          'page': '1',
          if (isPopularHome) 'limit': '12',
        },
      );
      return CatalogListData.fromJson(payload);
    });

final albumsSearchProvider = FutureProvider.autoDispose
    .family<CatalogListData, CatalogBrowseRequest>((ref, request) async {
      return ref.watch(albumsCatalogProvider(request).future);
    });

final albumsCatalogProvider = FutureProvider.autoDispose
    .family<CatalogListData, CatalogBrowseRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final section = request.section.trim().isEmpty ? 'search' : request.section;
      if (section == 'search' && request.query.trim().isEmpty) {
        return const CatalogListData(items: []);
      }
      final payload = await client.getJson(
        '/catalog/music',
        queryParameters: {
          'section': section,
          if (request.query.trim().isNotEmpty) 'q': request.query.trim(),
          'page': '1',
        },
      );
      return CatalogListData.fromJson(payload);
    });
