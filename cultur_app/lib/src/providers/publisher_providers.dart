import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/user_follows_remote_controller.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/providers/person_providers.dart';
import 'package:yamtrack/src/models/books/favorite_publishers.dart';
import 'package:yamtrack/src/models/games/game_company_catalog_detail.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

export 'package:yamtrack/src/models/books/favorite_publishers.dart';

class BookSeriesDetailRequest {
  const BookSeriesDetailRequest({
    required this.seriesId,
    this.seriesName,
  });

  final String seriesId;
  final String? seriesName;

  @override
  bool operator ==(Object other) {
    return other is BookSeriesDetailRequest &&
        other.seriesId == seriesId &&
        other.seriesName == seriesName;
  }

  @override
  int get hashCode => Object.hash(seriesId, seriesName);
}

final bookSeriesCatalogDetailProvider = FutureProvider.autoDispose
    .family<GameCompanyCatalogDetail, BookSeriesDetailRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/books/series/${Uri.encodeComponent(request.seriesId)}',
        queryParameters: {
          if (request.seriesName != null && request.seriesName!.trim().isNotEmpty)
            'series_name': request.seriesName!.trim(),
        },
      );
      return GameCompanyCatalogDetail.fromJson(payload);
    });

class BookPublisherDetailRequest {
  const BookPublisherDetailRequest({required this.publisherId});

  final String publisherId;

  @override
  bool operator ==(Object other) {
    return other is BookPublisherDetailRequest &&
        other.publisherId == publisherId;
  }

  @override
  int get hashCode => publisherId.hashCode;
}

final bookPublisherCatalogDetailProvider = FutureProvider.autoDispose
    .family<GameCompanyCatalogDetail, BookPublisherDetailRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/books/publishers/${Uri.encodeComponent(request.publisherId)}',
      );
      return GameCompanyCatalogDetail.fromJson(payload);
    });

class UserBookTrackingDigest {
  const UserBookTrackingDigest({
    required this.readIds,
    required this.byMediaId,
  });

  final Set<String> readIds;
  final Map<String, TrackingItem> byMediaId;
}

final userBookTrackingDigestProvider =
    FutureProvider.autoDispose<UserBookTrackingDigest>((ref) async {
  final authState = ref.watch(authControllerProvider).asData?.value;
  final username = authState?.session?.username;
  if (username == null || username.isEmpty) {
    return const UserBookTrackingDigest(readIds: {}, byMediaId: {});
  }
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson(
    '/backend/tracking',
    queryParameters: {
      'username': username,
      'mediaType': 'book',
      'limit': 500,
    },
  );
  final list = TrackingListData.fromJson(payload);
  final read = <String>{};
  final byId = <String, TrackingItem>{};
  for (final entry in list.items) {
    byId[entry.media.id] = entry;
    if (trackingIsWatched(entry)) {
      read.add(entry.media.id);
    }
  }
  return UserBookTrackingDigest(readIds: read, byMediaId: byId);
});

final favoritePublishersControllerProvider = Provider<UserFollowsRemoteController>((ref) {
  return ref.read(userFollowsControllerProvider);
});

final favoritePublishersProvider = FutureProvider.autoDispose<FavoritePublishersData>((ref) async {
  final username = ref.watch(authControllerProvider).asData?.value.session?.username;
  if (username == null || username.isEmpty) {
    return const FavoritePublishersData(publishers: []);
  }
  return ref.read(favoritePublishersControllerProvider).loadFavoritePublishers(username);
});
