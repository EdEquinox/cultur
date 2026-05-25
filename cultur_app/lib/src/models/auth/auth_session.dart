class AuthSession {
  const AuthSession({
    required this.sessionToken,
    required this.refreshToken,
    required this.username,
    this.displayName,
    this.sessionExpiresAt,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      sessionToken: json['sessionToken']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString() ?? '',
      username: json['username']?.toString() ?? 'user',
      displayName: json['displayName']?.toString(),
      sessionExpiresAt: json['sessionExpiresAt']?.toString(),
    );
  }

  final String sessionToken;
  final String refreshToken;
  final String username;
  final String? displayName;
  final String? sessionExpiresAt;
}
