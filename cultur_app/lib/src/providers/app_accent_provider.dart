import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateNotifier, StateNotifierProvider;
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';

/// Device-local accent presets (primary / brand colour).
enum CulturAccentId {
  rose,
  coral,
  amber,
  sage,
  teal,
  ocean,
  indigo,
  plum,
}

@immutable
class CulturAccentOption {
  const CulturAccentOption({
    required this.id,
    required this.label,
    required this.seed,
  });

  final CulturAccentId id;
  final String label;
  final Color seed;

  static const CulturAccentId defaultId = CulturAccentId.rose;

  static const List<CulturAccentOption> all = [
    CulturAccentOption(
      id: CulturAccentId.rose,
      label: 'Rose',
      seed: Color(0xFF8B5C69),
    ),
    CulturAccentOption(
      id: CulturAccentId.coral,
      label: 'Coral',
      seed: Color(0xFFE5634A),
    ),
    CulturAccentOption(
      id: CulturAccentId.amber,
      label: 'Amber',
      seed: Color(0xFFE5A020),
    ),
    CulturAccentOption(
      id: CulturAccentId.sage,
      label: 'Sage',
      seed: Color(0xFF6B9E78),
    ),
    CulturAccentOption(
      id: CulturAccentId.teal,
      label: 'Teal',
      seed: Color(0xFF3DAA9C),
    ),
    CulturAccentOption(
      id: CulturAccentId.ocean,
      label: 'Ocean',
      seed: Color(0xFF5B8FD4),
    ),
    CulturAccentOption(
      id: CulturAccentId.indigo,
      label: 'Indigo',
      seed: Color(0xFF6E6BC7),
    ),
    CulturAccentOption(
      id: CulturAccentId.plum,
      label: 'Plum',
      seed: Color(0xFF9B6BA8),
    ),
  ];

  static CulturAccentOption byId(CulturAccentId id) {
    for (final option in all) {
      if (option.id == id) {
        return option;
      }
    }
    return all.first;
  }

  static CulturAccentId? parseStorage(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final key = raw.trim().toLowerCase();
    for (final option in all) {
      if (option.id.name == key) {
        return option.id;
      }
    }
    return null;
  }
}

class CulturAccentNotifier extends StateNotifier<CulturAccentId> {
  CulturAccentNotifier(this._storage) : super(CulturAccentOption.defaultId) {
    _restore();
  }

  final SessionStorage _storage;

  Future<void> _restore() async {
    final raw = await _storage.read(key: StorageKeys.appAccentColor);
    final parsed = CulturAccentOption.parseStorage(raw);
    if (parsed != null) {
      state = parsed;
    }
  }

  Future<void> setAccent(CulturAccentId id) async {
    state = id;
    await _storage.write(key: StorageKeys.appAccentColor, value: id.name);
  }
}

final culturAccentProvider =
    StateNotifierProvider<CulturAccentNotifier, CulturAccentId>((ref) {
  return CulturAccentNotifier(ref.watch(sessionStorageProvider));
});

final culturAccentOptionProvider = Provider<CulturAccentOption>((ref) {
  return CulturAccentOption.byId(ref.watch(culturAccentProvider));
});
