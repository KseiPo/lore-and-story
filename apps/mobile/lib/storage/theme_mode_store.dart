import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user-chosen theme mode (light/dark) across launches (Story
/// 5.2), mirroring [RepoRootStore]'s exact shape.
///
/// The theme choice is non-secret user preference, so `shared_preferences` is
/// used, same as [RepoRootStore] — `flutter_secure_storage` stays reserved for
/// the AI key (Epic 4). [ThemeMode] is stored as a plain string
/// (`'light'`/`'dark'`), mapped to/from the enum at this store's boundary, so
/// nothing outside this file needs to know the storage representation.
class ThemeModeStore {
  static const String _key = 'theme_mode';

  /// Returns the stored theme mode, or `null` if none has been chosen yet, or
  /// the stored value is unrecognized/corrupted (AC6 — malformed degrades to
  /// "unset," never an error, mirroring `AiServerConfig`'s/`ProjectConfig`'s
  /// own "malformed becomes default, not an error" precedent).
  Future<ThemeMode?> read() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }

  /// Stores [mode] as the remembered theme choice. This app only ever offers
  /// a light/dark toggle (no "follow system" option — see Story 5.2's
  /// non-goals), so [ThemeMode.system] has no dedicated stored
  /// representation; it's deliberately, explicitly treated the same as
  /// [ThemeMode.light] rather than left as an unspecified ternary fallback —
  /// see `theme_mode_store_test.dart` for the case this covers.
  Future<void> write(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light || ThemeMode.system => 'light',
    };
    await prefs.setString(_key, value);
  }

  /// Forgets the stored theme mode.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
