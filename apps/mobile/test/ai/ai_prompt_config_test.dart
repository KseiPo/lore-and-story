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
      expect(config.instructions, 'Translate carefully.');
      expect(config.conventions, 'Keep dialogue format.');
    });

    test('only Translation Instructions present leaves conventions null', () {
      const raw = '# Translation Instructions\nTranslate carefully.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.instructions, 'Translate carefully.');
      expect(config.conventions, isNull);
    });

    test('only Conventions present leaves instructions null', () {
      const raw = '# Conventions\nKeep dialogue format.\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.instructions, isNull);
      expect(config.conventions, 'Keep dialogue format.');
    });

    test('neither recognized heading present → both null', () {
      const raw = '# Something Else\nirrelevant content\n';
      final config = AiPromptConfig.parse(raw);
      expect(config.instructions, isNull);
      expect(config.conventions, isNull);
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
      expect(config.instructions, 'Real instructions.');
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
      expect(config.instructions, isNull);
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

    test('empty input → both null', () {
      final config = AiPromptConfig.parse('');
      expect(config.instructions, isNull);
      expect(config.conventions, isNull);
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
      expect(config.instructions, isNull);
      expect(config.conventions, isNull);
    });
  });

  group('resolveAiPromptConfig', () {
    test('a missing ai-prompts.md resolves to AiPromptConfig.empty', () async {
      final config = await resolveAiPromptConfig(FakeRepoStorage('/repo'));
      expect(config, AiPromptConfig.empty);
      expect(config.instructions, isNull);
      expect(config.conventions, isNull);
    });

    test('an existing ai-prompts.md is read and parsed', () async {
      final storage = FakeRepoStorage('/repo', fileContents: {
        kAiPromptConfigFile: '# Conventions\nCustom conventions.\n',
      });
      final config = await resolveAiPromptConfig(storage);
      expect(config.conventions, 'Custom conventions.');
      expect(config.instructions, isNull);
    });
  });
}
