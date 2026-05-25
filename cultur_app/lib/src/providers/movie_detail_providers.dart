import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/providers/catalog_detail_providers.dart';

export 'package:yamtrack/src/providers/catalog_detail_providers.dart'
    show CatalogDetailKind, CatalogDetailRequest, catalogDetailProvider, catalogDetailApiPath;

@immutable
class MovieDetailRequest {
  const MovieDetailRequest({
    required this.mediaId,
    required this.username,
    this.isTv = false,
    this.isGame = false,
  });

  final String mediaId;
  final String? username;
  final bool isTv;
  final bool isGame;

  CatalogDetailRequest get catalogRequest {
    final kind = isGame
        ? CatalogDetailKind.game
        : isTv
        ? CatalogDetailKind.tv
        : CatalogDetailKind.movie;
    return CatalogDetailRequest(
      mediaId: mediaId,
      username: username,
      kind: kind,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MovieDetailRequest &&
        other.mediaId == mediaId &&
        other.username == username &&
        other.isTv == isTv &&
        other.isGame == isGame;
  }

  @override
  int get hashCode => Object.hash(mediaId, username, isTv, isGame);
}

final movieDetailProvider = FutureProvider.autoDispose
    .family<CatalogDetail, MovieDetailRequest>((ref, request) {
      return ref.watch(catalogDetailProvider(request.catalogRequest).future);
    });
