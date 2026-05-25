import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';

enum CatalogDetailKind { movie, tv, game, boardgame, book, music }

@immutable
class CatalogDetailRequest {
  const CatalogDetailRequest({
    required this.mediaId,
    required this.username,
    this.kind = CatalogDetailKind.movie,
  });

  final String mediaId;
  final String? username;
  final CatalogDetailKind kind;

  @override
  bool operator ==(Object other) {
    return other is CatalogDetailRequest &&
        other.mediaId == mediaId &&
        other.username == username &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(mediaId, username, kind);
}

String catalogDetailApiPath(CatalogDetailRequest request) {
  return switch (request.kind) {
    CatalogDetailKind.game => '/catalog/games/${request.mediaId}',
    CatalogDetailKind.boardgame => '/catalog/boardgames/${request.mediaId}',
    CatalogDetailKind.book => '/catalog/books/${request.mediaId}',
    CatalogDetailKind.music => '/catalog/music/${request.mediaId}',
    CatalogDetailKind.tv => '/catalog/tv/${request.mediaId}',
    CatalogDetailKind.movie => '/catalog/movies/${request.mediaId}',
  };
}

final catalogDetailProvider = FutureProvider.autoDispose
    .family<CatalogDetail, CatalogDetailRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        catalogDetailApiPath(request),
        queryParameters: {
          if (request.username != null && request.username!.isNotEmpty)
            'username': request.username,
        },
        receiveTimeout: request.kind == CatalogDetailKind.music
            ? const Duration(seconds: 45)
            : null,
      );
      return CatalogDetail.fromJson(payload);
    });
