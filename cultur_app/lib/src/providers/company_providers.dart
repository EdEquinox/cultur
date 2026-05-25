import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/user_follows_remote_controller.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/providers/person_providers.dart';
import 'package:yamtrack/src/models/games/favorite_companies.dart';
import 'package:yamtrack/src/models/games/game_company_catalog_detail.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

export 'package:yamtrack/src/models/games/favorite_companies.dart';

class GameCompanyDetailRequest {
  const GameCompanyDetailRequest({
    required this.companyId,
    this.role = 'publisher',
  });

  final String companyId;
  final String role;

  @override
  bool operator ==(Object other) {
    return other is GameCompanyDetailRequest &&
        other.companyId == companyId &&
        other.role == role;
  }

  @override
  int get hashCode => Object.hash(companyId, role);
}

final gameCompanyCatalogDetailProvider = FutureProvider.autoDispose
    .family<GameCompanyCatalogDetail, GameCompanyDetailRequest>((ref, request) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/catalog/games/companies/${request.companyId}',
        queryParameters: {
          if (request.role.trim().isNotEmpty) 'company_role': request.role.trim(),
        },
      );
      return GameCompanyCatalogDetail.fromJson(payload);
    });

class UserGameTrackingDigest {
  const UserGameTrackingDigest({
    required this.watchedIds,
    required this.byMediaId,
  });

  final Set<String> watchedIds;
  final Map<String, TrackingItem> byMediaId;
}

final userGameTrackingDigestProvider =
    FutureProvider.autoDispose<UserGameTrackingDigest>((ref) async {
  final authState = ref.watch(authControllerProvider).asData?.value;
  final username = authState?.session?.username;
  if (username == null || username.isEmpty) {
    return const UserGameTrackingDigest(watchedIds: {}, byMediaId: {});
  }
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson(
    '/backend/tracking',
    queryParameters: {
      'username': username,
      'mediaType': 'game',
      'limit': 500,
    },
  );
  final list = TrackingListData.fromJson(payload);
  final watched = <String>{};
  final byId = <String, TrackingItem>{};
  for (final entry in list.items) {
    byId[entry.media.id] = entry;
    if (trackingIsWatched(entry)) {
      watched.add(entry.media.id);
    }
  }
  return UserGameTrackingDigest(watchedIds: watched, byMediaId: byId);
});

final favoriteCompaniesControllerProvider = Provider<UserFollowsRemoteController>((ref) {
  return ref.read(userFollowsControllerProvider);
});

final favoriteCompaniesProvider = FutureProvider.autoDispose<FavoriteCompaniesData>((ref) async {
  final username = ref.watch(authControllerProvider).asData?.value.session?.username;
  if (username == null || username.isEmpty) {
    return const FavoriteCompaniesData(companies: []);
  }
  return ref.read(favoriteCompaniesControllerProvider).loadFavoriteCompanies(username);
});
