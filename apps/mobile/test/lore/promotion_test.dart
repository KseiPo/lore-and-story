import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/lore/lore.dart';

void main() {
  group('promotionTargetOf (Story 5.6)', () {
    test('a card without a language suffix keeps today\'s `.md`-only strip',
        () {
      final t = promotionTargetOf('characters/frank.md');
      expect(t.folderId, 'characters/frank');
      expect(t.cardId, 'characters/frank/frank.md');
    });

    test('a `.ru.md` card drops the suffix from both folder and card', () {
      final t = promotionTargetOf('characters/frank.ru.md');
      expect(t.folderId, 'characters/frank');
      expect(t.cardId, 'characters/frank/frank.md');
    });

    test('a `.en.md` card drops the suffix from both folder and card', () {
      final t = promotionTargetOf('characters/frank.en.md');
      expect(t.folderId, 'characters/frank');
      expect(t.cardId, 'characters/frank/frank.md');
    });

    test('the suffix is matched case-insensitively, like the loader', () {
      expect(promotionTargetOf('characters/frank.RU.md').cardId,
          'characters/frank/frank.md');
      expect(promotionTargetOf('characters/frank.En.md').cardId,
          'characters/frank/frank.md');
    });

    test('only the final language suffix is stripped — the loader\'s own base',
        () {
      final t = promotionTargetOf('characters/frank.ru.en.md');
      expect(t.folderId, 'characters/frank.ru');
      expect(t.cardId, 'characters/frank.ru/frank.ru.md');
    });

    test('a card at the lore root (no directory) promotes in place', () {
      final t = promotionTargetOf('frank.ru.md');
      expect(t.folderId, 'frank');
      expect(t.cardId, 'frank/frank.md');
    });

    test('a card in a nested sub-category keeps its full directory', () {
      final t = promotionTargetOf('characters/secondary/carrie.en.md');
      expect(t.folderId, 'characters/secondary/carrie');
      expect(t.cardId, 'characters/secondary/carrie/carrie.md');
    });

    test('names that only look suffix-like keep the `.md`-only strip', () {
      expect(promotionTargetOf('characters/frank.russian.md').cardId,
          'characters/frank.russian/frank.russian.md');
      expect(promotionTargetOf('characters/ru.md').cardId,
          'characters/ru/ru.md');
      expect(promotionTargetOf('characters/en.md').folderId, 'characters/en');
    });
  });
}
