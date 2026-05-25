import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/models/auth/auth_state.dart';

import 'api_client.dart';

/// Shared HTTP client bound to the current auth session.
///
/// Safe to watch before the server URL is set: requests throw
/// [ApiException] with [ApiExceptionKind.serverNotConfigured] until configured.
/// Prefer checking [AuthState.hasConfiguredServer] in UI when you can avoid a round-trip.
final apiClientProvider = Provider<ApiClient>((ref) {
  final authState =
      ref.watch(authControllerProvider).asData?.value ?? const AuthState();

  return ApiClient(
    baseUrl: authState.serverApiBaseUrl ?? '',
    sessionToken: authState.session?.sessionToken,
  );
});
