/// Compile-time configuration via `--dart-define`.
///
/// Production web build (see `deploy/scripts/build-web.sh`):
/// - `CULTUR_DEFAULT_API_URL` — pre-fills server setup (e.g. https://api.example.com)
/// - `CULTUR_ANDROID_APK_URL` — enables "Install Android app" on web profile
abstract final class AppBuildConfig {
  static const String defaultApiBaseUrl = String.fromEnvironment(
    'CULTUR_DEFAULT_API_URL',
    defaultValue: '',
  );

  static const String androidApkUrl = String.fromEnvironment(
    'CULTUR_ANDROID_APK_URL',
    defaultValue: '',
  );

  static bool get hasDefaultApiBaseUrl => defaultApiBaseUrl.trim().isNotEmpty;

  static bool get hasAndroidApkUrl => androidApkUrl.trim().isNotEmpty;
}
