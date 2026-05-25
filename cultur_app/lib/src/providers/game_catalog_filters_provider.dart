import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/models/games/game_filter_option.dart';

final gameCatalogFiltersProvider = FutureProvider.autoDispose<GameCatalogFilters>((ref) async {
  final client = ref.watch(apiClientProvider);
  final payload = await client.getJson('/catalog/games/filters');
  return GameCatalogFilters.fromJson(payload);
});
