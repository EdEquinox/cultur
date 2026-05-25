import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Session storage for persistent authentication and preferences.
/// Handles secure storage for sensitive data and preferences for device-local UI.

/// Riverpod provider for the [SessionStorage] singleton.
final sessionStorageProvider = Provider<SessionStorage>((ref) {
  return SessionStorage(const FlutterSecureStorage());
});

/// Session storage for persistent authentication and preferences.
/// Handles secure storage for sensitive data and preferences for device-local UI.
class SessionStorage {
  SessionStorage(this._secureStorage);

  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _sharedPreferences;

  bool get _usePreferencesFirst =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.linux;

  Future<String?> read({required String key}) async {
    if (_usePreferencesFirst) {
      return (await _prefs).getString(key);
    }

    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return (await _prefs).getString(key);
    }
  }

  Future<void> write({required String key, required String value}) async {
    if (_usePreferencesFirst) {
      await (await _prefs).setString(key, value);
      return;
    }

    try {
      await _secureStorage.write(key: key, value: value);
    } catch (_) {
      await (await _prefs).setString(key, value);
    }
  }

  Future<void> delete({required String key}) async {
    if (_usePreferencesFirst) {
      await (await _prefs).remove(key);
      return;
    }

    try {
      await _secureStorage.delete(key: key);
    } catch (_) {
      await (await _prefs).remove(key);
    }
  }

  Future<SharedPreferences> get _prefs async {
    return _sharedPreferences ??= await SharedPreferences.getInstance();
  }
}
