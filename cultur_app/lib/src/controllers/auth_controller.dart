import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/core/api_client.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/auth/auth_session.dart';
import 'package:yamtrack/src/models/auth/auth_state.dart';

/// Controller for the authentication state and actions.
/// Handles server API URL configuration, session persistence, and authentication operations.

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends AsyncNotifier<AuthState> {
  SessionStorage get _storage => ref.read(sessionStorageProvider);
  
  @override
  Future<AuthState> build() async {
    // Load initial authentication state from storage
    final baseUrl = _sanitizeUrl(await _storage.read(key: StorageKeys.serverApiBaseUrl));
    final sessionToken = await _storage.read(key: StorageKeys.sessionToken);
    final refreshToken = await _storage.read(key: StorageKeys.refreshToken);
    final username = await _storage.read(key: StorageKeys.username);
    final displayName = await _storage.read(key: StorageKeys.displayName);

    // Create initial AuthState with loaded values
    final initial = AuthState(
      serverApiBaseUrl: baseUrl,
      session: sessionToken != null && refreshToken != null && username != null
          ? AuthSession(
              sessionToken: sessionToken,
              refreshToken: refreshToken,
              username: username,
              displayName: displayName,
            )
          : null,
    );

    if (!initial.isAuthenticated || !initial.hasConfiguredServer) {
      return initial;
    }

    try {
      final refreshedSession = await _restoreSession(
        baseUrl: initial.serverApiBaseUrl!,
        session: initial.session!,
      );
      await _persistSession(refreshedSession);
      return initial.copyWith(session: refreshedSession);
    } catch (_) {
      await _clearSession();
      return initial.copyWith(clearSession: true);
    }
  }

  Future<void> saveServerApiUrl(String rawValue) async {
    final value = _sanitizeUrl(rawValue);
    if (value == null) {
      throw Exception('Enter a valid http:// or https:// URL.');
    }

    final current = state.asData?.value ?? const AuthState();
    await _storage.write(key: StorageKeys.serverApiBaseUrl, value: value);
    await _clearSession();
    state = AsyncData(
      current.copyWith(serverApiBaseUrl: value, clearSession: true),
    );
  }

  Future<void> clearServerApiUrl() async {
    await _storage.delete(key: StorageKeys.serverApiBaseUrl);
    await _clearSession();
    state = const AsyncData(AuthState());
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final current = state.asData?.value ?? const AuthState();
    final baseUrl = current.serverApiBaseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Configure the server API URL first.');
    }

    final client = ApiClient(baseUrl: baseUrl);
    final payload = await client.postJson(
      '/auth/login',
      data: {
        'username': username,
        'password': password,
      },
    );
    final session = AuthSession.fromJson(payload);
    await _persistSession(session);
    state = AsyncData(current.copyWith(session: session));
  }

  Future<void> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final current = state.asData?.value ?? const AuthState();
    final baseUrl = current.serverApiBaseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Configure the server API URL first.');
    }

    final payload = await ApiClient(baseUrl: baseUrl).postJson(
      '/auth/register',
      data: {
        'username': username,
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
      },
    );
    final session = AuthSession.fromJson(payload);
    await _persistSession(session);
    state = AsyncData(current.copyWith(session: session));
  }

  Future<void> signOut() async {
    final current = state.asData?.value ?? const AuthState();
    final session = current.session;

    if (current.hasConfiguredServer && session != null) {
      final client = ApiClient(
        baseUrl: current.serverApiBaseUrl!,
        sessionToken: session.sessionToken,
      );
      try {
        await client.postJson('/auth/logout');
      } catch (_) {
        // Local cleanup is enough even if the server logout call fails.
      }
    }

    await _clearSession();
    state = AsyncData(current.copyWith(clearSession: true));
  }

  Future<void> _persistSession(AuthSession session) async {
    await _storage.write(key: StorageKeys.sessionToken, value: session.sessionToken);
    await _storage.write(key: StorageKeys.refreshToken, value: session.refreshToken);
    await _storage.write(key: StorageKeys.username, value: session.username);
    if (session.displayName != null) {
      await _storage.write(key: StorageKeys.displayName, value: session.displayName!);
    } else {
      await _storage.delete(key: StorageKeys.displayName);
    }
  }

  Future<void> _clearSession() async {
    await _storage.delete(key: StorageKeys.sessionToken);
    await _storage.delete(key: StorageKeys.refreshToken);
    await _storage.delete(key: StorageKeys.username);
    await _storage.delete(key: StorageKeys.displayName);
  }

  Future<AuthSession> _restoreSession({
    required String baseUrl,
    required AuthSession session,
  }) async {
    final client = ApiClient(
      baseUrl: baseUrl,
      sessionToken: session.sessionToken,
    );

    try {
      final payload = await client.getJson('/me');
      return AuthSession(
        sessionToken: session.sessionToken,
        refreshToken: session.refreshToken,
        username: payload['username']?.toString() ?? session.username,
        displayName: payload['displayName']?.toString() ?? session.displayName,
        sessionExpiresAt: payload['sessionExpiresAt']?.toString(),
      );
    } catch (_) {
      final refreshPayload = await ApiClient(
        baseUrl: baseUrl,
      ).postJson('/auth/refresh', data: {'refreshToken': session.refreshToken});
      final refreshed = AuthSession.fromJson(refreshPayload);
      final mePayload = await ApiClient(
        baseUrl: baseUrl,
        sessionToken: refreshed.sessionToken,
      ).getJson('/me');
      return AuthSession(
        sessionToken: refreshed.sessionToken,
        refreshToken: refreshed.refreshToken,
        username: mePayload['username']?.toString() ?? refreshed.username,
        displayName:
            mePayload['displayName']?.toString() ?? refreshed.displayName,
        sessionExpiresAt:
            mePayload['sessionExpiresAt']?.toString() ??
            refreshed.sessionExpiresAt,
      );
    }
  }

  String? _sanitizeUrl(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    final normalized = value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
    return normalized;
  }
}
