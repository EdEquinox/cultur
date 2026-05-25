import 'package:yamtrack/src/models/auth/auth_session.dart';

class AuthState {
  const AuthState({this.serverApiBaseUrl, this.session});

  final String? serverApiBaseUrl;
  final AuthSession? session;

  bool get hasConfiguredServer =>
      serverApiBaseUrl != null && serverApiBaseUrl!.isNotEmpty;
  bool get isAuthenticated =>
      session != null && session!.sessionToken.trim().isNotEmpty;

  AuthState copyWith({
    String? serverApiBaseUrl,
    AuthSession? session,
    bool clearSession = false,
  }) {
    return AuthState(
      serverApiBaseUrl: serverApiBaseUrl ?? this.serverApiBaseUrl,
      session: clearSession ? null : (session ?? this.session),
    );
  }
}
