import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/lore/lore.dart';

/// Direct unit tests for the pure helpers. The golden fixtures
/// (`lore_model_fixtures_test.dart`) are the contract; these pin the individual
/// rules so a failure points at the specific helper rather than a whole tree.
void main() {
  group('readTitleAliases', () {
    test('takes the title from the first # heading', () {
      final r = readTitleAliases('# Selena\n\nSome body.\n', 'slug');
      expect(r.title, 'Selena');
      expect(r.aliases, ['Selena']);
    });

    test('falls back to the slug when there is no heading', () {
      final r = readTitleAliases('no heading here\n', 'no-heading');
      expect(r.title, 'no-heading');
      expect(r.aliases, ['no-heading']);
    });

    test('collects the aliases line, title first', () {
      final r = readTitleAliases(
        '# Selena\naliases: Селена, Селена Моралес\n',
        'selena',
      );
      expect(r.title, 'Selena');
      expect(r.aliases, ['Selena', 'Селена', 'Селена Моралес']);
    });

    test('matches the aliases label case-insensitively', () {
      final r = readTitleAliases('# Mira\nAliases: Мира\n', 'mira');
      expect(r.aliases, ['Mira', 'Мира']);
    });

    test('dedupes while preserving first-seen order', () {
      final r = readTitleAliases('# Zoey\naliases: Zoey, Зои, Zoey\n', 'zoey');
      expect(r.aliases, ['Zoey', 'Зои']);
    });

    test('drops empty alias entries', () {
      final r = readTitleAliases('# Frank\naliases: Фрэнк, , \n', 'frank');
      expect(r.aliases, ['Frank', 'Фрэнк']);
    });

    test('a CRLF heading captures the title without the CR (like the JS ref)',
        () {
      // Pins the corrected contract: Dart's `.` does NOT match `\r`, so the
      // heading capture never includes the CR — the same result as the JS
      // reference, with or without the trim.
      final r = readTitleAliases('# Selena\r\naliases: Селена\r\n', 'selena');
      expect(r.title, 'Selena');
      expect(r.aliases, ['Selena', 'Селена']);
    });

    test('a heading with only whitespace falls back to the slug', () {
      // `# ` with nothing capturable after it → no match → slug fallback,
      // matching the JS reference.
      final r = readTitleAliases('# \r\n', 'frank');
      expect(r.title, 'frank');
      expect(r.aliases, ['frank']);
    });
  });

  group('prettify', () {
    test('replaces dashes/underscores with spaces and never changes case', () {
      expect(prettify('events'), 'events');
      expect(prettify('relationship-quest-1'), 'relationship quest 1');
      expect(prettify('some_group'), 'some group');
      expect(prettify(''), '');
    });

    test('leaves Cyrillic verbatim (no capitalization)', () {
      expect(prettify('события'), 'события');
      expect(prettify('линия-квеста'), 'линия квеста');
    });
  });

  group('passageOf', () {
    test('extracts the scene passage target', () {
      const text = '<!-- scene ⇄ passage: "Selena - Hobby" · lang: ru -->\n';
      expect(passageOf(text), 'Selena - Hobby');
    });

    test('returns null when there is no marker', () {
      expect(passageOf('# Just a card\n'), isNull);
    });
  });
}
