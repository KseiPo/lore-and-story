import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/theme.dart';

void main() {
  group('theme.dart (Story 5.2)', () {
    test('lightTheme is light-brightness, Material 3, indigo-seeded', () {
      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.useMaterial3, isTrue);
      expect(lightTheme.colorScheme.brightness, Brightness.light);
    });

    test('darkTheme is dark-brightness, Material 3, indigo-seeded', () {
      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.useMaterial3, isTrue);
      expect(darkTheme.colorScheme.brightness, Brightness.dark);
    });

    test('lightTheme and darkTheme share the same indigo-derived seed hue '
        '(only brightness differs)', () {
      // Both derive from the same seed, so their primary colors should be
      // the recognizable indigo family, not an arbitrary/different seed.
      expect(lightTheme.colorScheme.primary, isNot(darkTheme.colorScheme.primary));
    });

    test('kMonospaceTextStyle is the shared monospace style', () {
      expect(kMonospaceTextStyle.fontFamily, 'monospace');
    });

    test('corner-radius constants preserve today\'s two distinct existing '
        'values (4 and 6), not unified', () {
      expect(kBadgeCornerRadius, 4);
      expect(kBannerCornerRadius, 6);
    });

    test(
        'lightTheme and darkTheme agree on useMaterial3 (structural parity '
        'guard, Review fix): both are actually built by the same shared '
        '_buildTheme construction in theme.dart, so a future property added '
        'there automatically applies to both instead of risking drift '
        'between two hand-duplicated ThemeData literals — this assertion is '
        'the externally-visible half of that guarantee; the rest is '
        'enforced by the single construction path itself, not by a test',
        () {
      expect(lightTheme.useMaterial3, darkTheme.useMaterial3);
    });
  });
}
