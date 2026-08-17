import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../storage/storage.dart';

/// Owns the app-wide theme-mode state — the live signal plus its persistence
/// — behind one small controlled surface (Story 5.2 code-review fix).
///
/// Read access is [listenable] (a [ValueListenable], never the mutable
/// [ValueNotifier] itself) so no holder of a [ThemeModeController] can flip
/// the visible theme directly; the only way to change it is [set], which
/// applies the change **and** persists it in the same call — a caller can no
/// longer change the theme without also saving the change, the way a raw,
/// externally-writable `ValueNotifier<ThemeMode>` field previously allowed.
///
/// [set] and [loadStored] guard against each other: whichever the user's own
/// toggle races against a still-in-flight preference load (`main.dart` kicks
/// [loadStored] off right after `runApp`, fire-and-forget), the user's [set]
/// always wins — a load that resolves after a manual toggle is discarded
/// rather than silently reverting the user's already-applied choice.
///
/// Total (AD-8): neither [set] nor [loadStored] ever throws — a persistence
/// or read failure is swallowed and leaves the already-applied/default value
/// in place.
class ThemeModeController {
  final ThemeModeStore _store;
  final ValueNotifier<ThemeMode> _notifier;

  /// Set the instant [set] is called for the first time — guards
  /// [loadStored] from overwriting a choice the user already made.
  bool _userHasSet = false;

  ThemeModeController(this._store, {ThemeMode initial = ThemeMode.light})
      : _notifier = ValueNotifier<ThemeMode>(initial);

  /// The app-wide signal to listen to (e.g. via `ValueListenableBuilder`).
  ValueListenable<ThemeMode> get listenable => _notifier;

  /// The current mode, without subscribing.
  ThemeMode get value => _notifier.value;

  /// Applies [mode] immediately and persists it in the background. A
  /// persistence failure never blocks or undoes the already-applied visual
  /// change (AD-8) — the toggle stays correct for this session even if it
  /// can't be remembered for the next one.
  Future<void> set(ThemeMode mode) async {
    _userHasSet = true;
    _notifier.value = mode;
    try {
      await _store.write(mode);
    } catch (_) {
      // AD-8: swallow — see doc comment above.
    }
  }

  /// Loads the persisted preference, if any, and applies it — but only if
  /// [set] hasn't been called since this was kicked off. `main.dart` calls
  /// this once, fire-and-forget, right after `runApp`; without the
  /// [_userHasSet] guard, a slow load that resolves after the user has
  /// already toggled the theme would silently revert their choice back to
  /// the stale stored value.
  Future<void> loadStored() async {
    try {
      final stored = await _store.read();
      if (stored != null && !_userHasSet) {
        _notifier.value = stored;
      }
    } catch (_) {
      // AD-8: a read failure simply leaves the current (default) value.
    }
  }
}
