import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/storage/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('read returns null before any theme mode is stored', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ThemeModeStore().read(), isNull);
  });

  test('write then read round-trips the chosen theme mode (dark)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ThemeModeStore();
    await store.write(ThemeMode.dark);

    // A fresh instance simulates a later launch reading the same prefs.
    expect(await ThemeModeStore().read(), ThemeMode.dark);
  });

  test('write then read round-trips the chosen theme mode (light)', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ThemeModeStore();
    await store.write(ThemeMode.light);

    expect(await ThemeModeStore().read(), ThemeMode.light);
  });

  test('clear forgets the stored theme mode', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ThemeModeStore();
    await store.write(ThemeMode.dark);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a corrupted/unrecognized stored value reads back as null, never throws (AC6)',
      () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'not-a-real-mode'});
    expect(await ThemeModeStore().read(), isNull);
  });

  test(
      'writing ThemeMode.system (never used by this app\'s own toggle, but '
      'type-permitted) is explicitly, deliberately stored and read back as '
      'light — not left as an untested implicit fallback (Review fix)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = ThemeModeStore();
    await store.write(ThemeMode.system);

    expect(await ThemeModeStore().read(), ThemeMode.light);
  });
}
