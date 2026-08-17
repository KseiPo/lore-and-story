import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/theme_mode_controller.dart';
import 'package:lore_and_story/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [ThemeModeStore] whose [write] always throws — for exercising the AD-8
/// never-crash path.
class _FailingWriteStore extends ThemeModeStore {
  @override
  Future<void> write(ThemeMode mode) async {
    throw Exception('boom (fake persistence failure)');
  }
}

/// A [ThemeModeStore] whose [read] doesn't resolve until [release] is
/// called — lets a test hold a "load in flight" state deliberately, to
/// exercise the race between a still-pending load and a user's own [set].
class _SlowReadStore extends ThemeModeStore {
  final _gate = Completer<ThemeMode?>();

  void release(ThemeMode? value) => _gate.complete(value);

  @override
  Future<ThemeMode?> read() => _gate.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeController (Story 5.2 review fix)', () {
    test('starts at the given initial value', () {
      final controller = ThemeModeController(ThemeModeStore());
      expect(controller.value, ThemeMode.light);
      expect(controller.listenable.value, ThemeMode.light);
    });

    test('set() applies immediately and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final store = ThemeModeStore();
      final controller = ThemeModeController(store);

      await controller.set(ThemeMode.dark);

      expect(controller.value, ThemeMode.dark);
      expect(await store.read(), ThemeMode.dark);
    });

    test('a persistence failure in set() never blocks the applied change (AD-8)',
        () async {
      final controller = ThemeModeController(_FailingWriteStore());

      await controller.set(ThemeMode.dark);

      expect(controller.value, ThemeMode.dark);
    });

    test('loadStored() applies a stored value when nothing has been set yet',
        () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
      final controller = ThemeModeController(ThemeModeStore());

      await controller.loadStored();

      expect(controller.value, ThemeMode.dark);
    });

    test('loadStored() leaves the default when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeModeController(ThemeModeStore());

      await controller.loadStored();

      expect(controller.value, ThemeMode.light);
    });

    test('a read failure in loadStored() never throws and leaves the current value (AD-8)',
        () async {
      final controller = ThemeModeController(_ThrowingReadStore());

      await controller.loadStored();

      expect(controller.value, ThemeMode.light);
    });

    test(
        "set() always wins over a still-in-flight loadStored() — a user's own "
        'toggle is never silently reverted by a late-resolving preference load '
        '(Review fix for the main.dart race)', () async {
      final store = _SlowReadStore();
      final controller = ThemeModeController(store);

      // Simulate app launch: the load kicks off but hasn't resolved yet.
      final loadFuture = controller.loadStored();

      // The user opens Settings and toggles before the load resolves.
      await controller.set(ThemeMode.dark);
      expect(controller.value, ThemeMode.dark);

      // The pending load NOW resolves with a stale value read before the
      // toggle — it must not override the user's already-applied choice.
      store.release(ThemeMode.light);
      await loadFuture;

      expect(controller.value, ThemeMode.dark);
    });

    test('loadStored() still applies normally when it resolves before any set()',
        () async {
      final store = _SlowReadStore();
      final controller = ThemeModeController(store);

      final loadFuture = controller.loadStored();
      store.release(ThemeMode.dark);
      await loadFuture;

      expect(controller.value, ThemeMode.dark);
    });
  });
}

/// A [ThemeModeStore] whose [read] always throws.
class _ThrowingReadStore extends ThemeModeStore {
  @override
  Future<ThemeMode?> read() async {
    throw Exception('boom (fake read failure)');
  }
}
