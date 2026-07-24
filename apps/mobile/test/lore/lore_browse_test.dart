import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/lore/lore.dart';

/// Builds a [LoreEntry] with just the fields the grouping cares about; the rest
/// get harmless defaults. Keeps the grouping tests focused on category/title/id.
LoreEntry entry({
  required String id,
  required String title,
  required String category,
}) {
  return LoreEntry(
    id: id,
    title: title,
    aliases: [title],
    category: category,
    relDir: category,
    text: '# $title\n',
    tree: null,
    children: const [],
  );
}

void main() {
  group('categoriesOf', () {
    test('empty input yields no categories', () {
      expect(categoriesOf(const []), isEmpty);
    });

    test('groups entries by their top-level folder', () {
      final cats = categoriesOf([
        entry(id: 'characters/frank.md', title: 'Frank', category: 'characters'),
        entry(id: 'locations/tavern.md', title: 'Tavern', category: 'locations'),
        entry(id: 'characters/selena/selena.md', title: 'Selena', category: 'characters'),
      ]);

      expect(cats.map((c) => c.key), ['characters', 'locations']);
      final characters = cats.firstWhere((c) => c.key == 'characters');
      expect(characters.entries.map((e) => e.title), ['Frank', 'Selena']);
      expect(characters.label, 'characters');
    });

    test('folds a nested sub-category under its top-level parent (reachability)', () {
      final cats = categoriesOf([
        entry(id: 'characters/secondary/frank.md', title: 'Frank', category: 'characters/secondary'),
        entry(id: 'characters/selena/selena.md', title: 'Selena', category: 'characters'),
      ]);

      // 'characters/secondary' folds into 'characters' — no separate group, and
      // the deep entity is still present (nothing stranded).
      expect(cats.map((c) => c.key), ['characters']);
      expect(cats.single.entries.map((e) => e.id), containsAll([
        'characters/secondary/frank.md',
        'characters/selena/selena.md',
      ]));
    });

    test('a card directly in loreDir becomes the general group', () {
      final cats = categoriesOf([
        entry(id: 'intro.md', title: 'Intro', category: 'general'),
        entry(id: 'characters/frank.md', title: 'Frank', category: 'characters'),
      ]);

      expect(cats.map((c) => c.key), ['characters', 'general']);
      expect(cats.firstWhere((c) => c.key == 'general').entries.single.id, 'intro.md');
    });

    test('orders categories and entities case-insensitively and deterministically', () {
      final cats = categoriesOf([
        entry(id: 'Zeta/a.md', title: 'apple', category: 'Zeta'),
        entry(id: 'alpha/b.md', title: 'Banana', category: 'alpha'),
        entry(id: 'alpha/a.md', title: 'apple', category: 'alpha'),
      ]);

      // Categories sorted case-insensitively: 'alpha' before 'Zeta'.
      expect(cats.map((c) => c.key), ['alpha', 'Zeta']);
      // Within 'alpha', title case-insensitive: 'apple' before 'Banana'.
      expect(cats.first.entries.map((e) => e.title), ['apple', 'Banana']);
    });

    test('same-titled entries both survive with a stable id-broken order', () {
      final cats = categoriesOf([
        entry(id: 'characters/frank-2.md', title: 'Frank', category: 'characters'),
        entry(id: 'characters/frank-1.md', title: 'Frank', category: 'characters'),
      ]);

      // Both present; tie broken by id so the order is stable across runs.
      expect(cats.single.entries.map((e) => e.id),
          ['characters/frank-1.md', 'characters/frank-2.md']);
    });

    test('two case-only-distinct category keys have a stable order', () {
      // 'Zoo' and 'zoo' compare equal case-insensitively; the raw-key tie-break
      // makes their order deterministic (uppercase sorts before lowercase).
      final cats = categoriesOf([
        entry(id: 'zoo/a.md', title: 'A', category: 'zoo'),
        entry(id: 'Zoo/b.md', title: 'B', category: 'Zoo'),
      ]);
      expect(cats.map((c) => c.key), ['Zoo', 'zoo']);
    });

    test('a blank first segment falls back to the general bucket', () {
      // The loader never emits this, but the key derivation stays robust: an
      // empty or leading-slash category must not produce a blank, unlabeled row.
      final cats = categoriesOf([
        entry(id: 'x.md', title: 'X', category: ''),
        entry(id: 'y.md', title: 'Y', category: '/'),
      ]);
      expect(cats.map((c) => c.key), ['general']);
      expect(cats.single.entries.length, 2);
    });

    test('returned entry lists are unmodifiable', () {
      final cats = categoriesOf([
        entry(id: 'characters/frank.md', title: 'Frank', category: 'characters'),
      ]);
      expect(() => cats.single.entries.add(cats.single.entries.first),
          throwsUnsupportedError);
    });
  });
}
