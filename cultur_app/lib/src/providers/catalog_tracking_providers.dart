import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';

final movieSearchTrackingProvider = FutureProvider.autoDispose
    .family<Map<String, TrackingItem>, String>((ref, username) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/backend/tracking',
        queryParameters: {
          'username': username,
          'mediaType': 'movie',
          'limit': 200,
        },
      );
      final items = TrackingListData.fromJson(payload).items;
      return {for (final item in items) item.media.id: item};
    });

final tvSearchTrackingProvider = FutureProvider.autoDispose
    .family<Map<String, TrackingItem>, String>((ref, username) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/backend/tracking',
        queryParameters: {
          'username': username,
          'mediaType': 'tv',
          'limit': 200,
        },
      );
      final items = TrackingListData.fromJson(payload).items;
      return {for (final item in items) item.media.id: item};
    });

final gameSearchTrackingProvider = FutureProvider.autoDispose
    .family<Map<String, TrackingItem>, String>((ref, username) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/backend/tracking',
        queryParameters: {
          'username': username,
          'mediaType': 'game',
          'limit': 200,
        },
      );
      final items = TrackingListData.fromJson(payload).items;
      return {for (final item in items) item.media.id: item};
    });

final bookSearchTrackingProvider = FutureProvider.autoDispose
    .family<Map<String, TrackingItem>, String>((ref, username) async {
      final client = ref.watch(apiClientProvider);
      final payload = await client.getJson(
        '/backend/tracking',
        queryParameters: {
          'username': username,
          'mediaType': 'book',
          'limit': 500,
        },
      );
      final items = TrackingListData.fromJson(payload).items;
      return {for (final item in items) item.media.id: item};
    });
