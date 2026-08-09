import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';

import '../fakes.dart';

void main() {
  group('AiPromptConfig.parse', () {
    test('both sections present populates both fields', () {
      const raw = '# Translation Instructions\n'
          'Translate carefully.\n'
          '# Conventions\n'
          'Keep dialogue format.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.instructionsRuToEn, 'Translate carefully.');
      expect(config.conventions, 'Keep dialogue format.');
    });

    test('only Translation Instructions present leaves conventions null', () {
      const raw = '# Translation Instructions\nTranslate carefully.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.instructionsRuToEn, 'Translate carefully.');
      expect(config.conventions, isNull);
    });

    test('only Conventions present leaves instructions null', () {
      const raw = '# Conventions\nKeep dialogue format.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.instructionsRuToEn, isNull);
      expect(config.conventions, 'Keep dialogue format.');
    });

    test('no recognized heading present → all four fields null', () {
      const raw = '# Something Else\nirrelevant content\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.instructionsRuToEn, isNull);
      expect(config.instructionsEnToRu, isNull);
      expect(config.conventions, isNull);
      expect(config.grammarInstructions, isNull);
    });

    test('an unrelated ## heading is part of the enclosing section\'s body, '
        'not a new top-level section', () {
      const raw = '# Conventions\n'
          'Top-level rule.\n'
          '## A sub-heading\n'
          'More convention text under it.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.conventions,
          'Top-level rule.\n## A sub-heading\nMore convention text under it.');
    });

    test('a heading with only whitespace/blank lines under it leaves that '
        'field null (review-anticipated Design decision 3)', () {
      const raw = '# Conventions\n   \n\n# Translation Instructions\n'
          'Real instructions.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.conventions, isNull);
      expect(config.instructionsRuToEn, 'Real instructions.');
    });

    test('a heading immediately followed by EOF (no body at all) leaves that '
        'field null', () {
      final config = AiPromptConfig.parse('# Conventions');
      expect(config.conventions, isNull);
    });

    test('heading text is matched trimmed and case-insensitively', () {
      const raw = '#   CONVENTIONS   \nUpper-case heading.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.conventions, 'Upper-case heading.');
    });

    test('a repeated heading — the last occurrence wins', () {
      const raw = '# Conventions\nFirst.\n# Conventions\nSecond.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.conventions, 'Second.');
    });

    test(
        '(review fix) a repeated heading whose LAST occurrence is empty '
        'erases the earlier non-empty one — "last occurrence wins" applies '
        'even when the last occurrence is empty, not just when it is not',
        () {
      const raw = '# Conventions\nFirst.\n# Conventions\n\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.conventions, isNull,
          reason: 'the later, empty occurrence must win outright, not be '
              'silently skipped in favor of the earlier stale value');
    });

    test('(AC5) an empty Translation Instructions heading also falls back '
        'to null, not just Conventions', () {
      const raw = '# Translation Instructions\n   \n';
      final config = AiPromptConfig.parse(raw);
      expect(config.instructionsRuToEn, isNull);
    });

    test('(AC7) lossy-decoded input (U+FFFD replacement characters, as '
        'RepoStorage.read would already have produced for non-UTF-8 bytes) '
        'never throws', () {
      const raw = '# Conventions\nSome text with a \u{FFFD} in it.\n';
      expect(() => AiPromptConfig.parse(raw), returnsNormally);
      expect(AiPromptConfig.parse(raw).conventions,
          'Some text with a \u{FFFD} in it.');
    });

    test('strips a leading BOM before parsing', () {
      const raw = '\u{FEFF}# Conventions\nBommed content.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.conventions, 'Bommed content.');
    });

    test('CRLF line endings never leak a stray \\r into a section\'s body',
        () {
      final raw = '# Conventions\r\nLine one.\r\nLine two.\r\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.conventions, 'Line one.\nLine two.');
      expect(config.conventions, isNot(contains('\r')));
    });

    test('empty input → all four fields null', () {
      final config = AiPromptConfig.parse('');
      expect(config.instructionsRuToEn, isNull);
      expect(config.instructionsEnToRu, isNull);
      expect(config.conventions, isNull);
      expect(config.grammarInstructions, isNull);
    });

    test('never throws on pathologically large input', () {
      final huge = '# Conventions\n${'x' * 500000}\n';
      expect(() => AiPromptConfig.parse(huge), returnsNormally);
      expect(AiPromptConfig.parse(huge).conventions, isNotNull);
    });

    test('never throws when content is only ##/### headings and no top-level '
        '# heading at all', () {
      const raw = '## Not top-level\ntext\n### Also not top-level\nmore\n';
      expect(() => AiPromptConfig.parse(raw), returnsNormally);
      final config = AiPromptConfig.parse(raw);
      expect(config.instructionsRuToEn, isNull);
      expect(config.conventions, isNull);
    });

    group('Story 4.5: EN→RU direction-aware heading', () {
      test(
          '# Translation Instructions (EN→RU) populates instructionsEnToRu '
          'only — the RU→EN field stays null', () {
        const raw = '# Translation Instructions (EN→RU)\n'
            'Translate into Russian carefully.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.instructionsEnToRu, 'Translate into Russian carefully.');
        expect(config.instructionsRuToEn, isNull);
      });

      test('the ASCII (en->ru) spelling parses identically to the arrow '
          'form', () {
        const raw = '# Translation Instructions (en->ru)\n'
            'Translate into Russian carefully.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.instructionsEnToRu, 'Translate into Russian carefully.');
      });

      test(
          '(Review fix) # Translation Instructions (RU→EN) — the symmetric '
          'heading an author naturally writes after seeing (EN→RU) — is '
          'recognized as an explicit synonym of the unprefixed heading, not '
          'silently discarded', () {
        const raw = '# Translation Instructions (RU→EN)\n'
            'Translate into English carefully.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.instructionsRuToEn, 'Translate into English carefully.');
      });

      test('(Review fix) the ASCII (ru->en) spelling of the symmetric '
          'heading parses identically to its arrow form', () {
        const raw = '# Translation Instructions (ru->en)\n'
            'Translate into English carefully.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.instructionsRuToEn, 'Translate into English carefully.');
      });

      test('matched case-insensitively and trimmed, same as the other '
          'headings', () {
        const raw = '#   TRANSLATION INSTRUCTIONS (EN→RU)   \n'
            'Upper-case heading.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.instructionsEnToRu, 'Upper-case heading.');
      });

      test('both the RU→EN and EN→RU headings present independently '
          'populate their own fields, plus Conventions', () {
        const raw = '# Translation Instructions\n'
            'RU to EN text.\n'
            '# Translation Instructions (EN→RU)\n'
            'EN to RU text.\n'
            '# Conventions\n'
            'Shared conventions.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.instructionsRuToEn, 'RU to EN text.');
        expect(config.instructionsEnToRu, 'EN to RU text.');
        expect(config.conventions, 'Shared conventions.');
      });

      test('an empty-body EN→RU heading falls back to null (Design '
          'decision 3, now for the third field)', () {
        const raw = '# Translation Instructions (EN→RU)\n   \n';
        final config = AiPromptConfig.parse(raw);
        expect(config.instructionsEnToRu, isNull);
      });

      test('a repeated EN→RU heading whose last occurrence is empty clears '
          'an earlier non-empty one', () {
        const raw = '# Translation Instructions (EN→RU)\n'
            'First.\n'
            '# Translation Instructions (EN→RU)\n'
            '\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.instructionsEnToRu, isNull);
      });
    });

    group('Story 4.6: Grammar Instructions heading', () {
      test('# Grammar Instructions populates grammarInstructions only — the '
          'other three fields stay null', () {
        const raw = '# Grammar Instructions\nReview for grammar carefully.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.grammarInstructions, 'Review for grammar carefully.');
        expect(config.instructionsRuToEn, isNull);
        expect(config.instructionsEnToRu, isNull);
        expect(config.conventions, isNull);
      });

      test('matched case-insensitively and trimmed, same as the other '
          'headings', () {
        const raw = '#   GRAMMAR INSTRUCTIONS   \nUpper-case heading.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.grammarInstructions, 'Upper-case heading.');
      });

      test('an empty-body Grammar Instructions heading falls back to null '
          '(Design decision 3, now for the fourth field)', () {
        const raw = '# Grammar Instructions\n   \n';
        final config = AiPromptConfig.parse(raw);
        expect(config.grammarInstructions, isNull);
      });

      test('a repeated Grammar Instructions heading whose last occurrence is '
          'empty clears an earlier non-empty one', () {
        const raw = '# Grammar Instructions\nFirst.\n'
            '# Grammar Instructions\n\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.grammarInstructions, isNull);
      });

      test('a repeated Grammar Instructions heading — the last non-empty '
          'occurrence wins', () {
        const raw = '# Grammar Instructions\nFirst.\n'
            '# Grammar Instructions\nSecond.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.grammarInstructions, 'Second.');
      });

      test('all four headings present populate all four fields '
          'independently', () {
        const raw = '# Translation Instructions\n'
            'RU to EN text.\n'
            '# Translation Instructions (EN→RU)\n'
            'EN to RU text.\n'
            '# Conventions\n'
            'Shared conventions.\n'
            '# Grammar Instructions\n'
            'Grammar review text.\n';
        final config = AiPromptConfig.parse(raw);
        expect(config.instructionsRuToEn, 'RU to EN text.');
        expect(config.instructionsEnToRu, 'EN to RU text.');
        expect(config.conventions, 'Shared conventions.');
        expect(config.grammarInstructions, 'Grammar review text.');
      });
    });

    test('toString/== /hashCode cover all four fields', () {
      const a = AiPromptConfig(
        instructionsRuToEn: 'a',
        instructionsEnToRu: 'b',
        conventions: 'c',
        grammarInstructions: 'd',
      );
      const b = AiPromptConfig(
        instructionsRuToEn: 'a',
        instructionsEnToRu: 'b',
        conventions: 'c',
        grammarInstructions: 'd',
      );
      const different =
          AiPromptConfig(instructionsRuToEn: 'a', instructionsEnToRu: 'x');
      const missingGrammar = AiPromptConfig(
        instructionsRuToEn: 'a',
        instructionsEnToRu: 'b',
        conventions: 'c',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(different));
      expect(a, isNot(missingGrammar));
      expect(
        a.toString(),
        'AiPromptConfig(instructionsRuToEn: overridden, '
        'instructionsEnToRu: overridden, conventions: overridden, '
        'grammarInstructions: overridden)',
      );
      expect(
        AiPromptConfig.empty.toString(),
        'AiPromptConfig(instructionsRuToEn: default, '
        'instructionsEnToRu: default, conventions: default, '
        'grammarInstructions: default)',
      );
    });
  });

  group('resolveAiPromptConfig', () {
    test('a missing ai-prompts.md resolves to AiPromptConfig.empty', () async {
      final config = await resolveAiPromptConfig(FakeRepoStorage('/repo'));
      expect(config, AiPromptConfig.empty);
      expect(config.instructionsRuToEn, isNull);
      expect(config.instructionsEnToRu, isNull);
      expect(config.conventions, isNull);
      expect(config.grammarInstructions, isNull);
    });

    test('an existing ai-prompts.md is read and parsed', () async {
      final storage = FakeRepoStorage('/repo', fileContents: {
        kAiPromptConfigFile: '# Conventions\nCustom conventions.\n',
      });
      final config = await resolveAiPromptConfig(storage);
      expect(config.conventions, 'Custom conventions.');
      expect(config.instructionsRuToEn, isNull);
      expect(config.instructionsEnToRu, isNull);
      expect(config.grammarInstructions, isNull);
    });

    test('an ai-prompts.md with # Grammar Instructions is read and parsed '
        '(Story 4.6)', () async {
      final storage = FakeRepoStorage('/repo', fileContents: {
        kAiPromptConfigFile: '# Grammar Instructions\nCustom review text.\n',
      });
      final config = await resolveAiPromptConfig(storage);
      expect(config.grammarInstructions, 'Custom review text.');
      expect(config.instructionsRuToEn, isNull);
      expect(config.conventions, isNull);
    });
  });
}
