import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/lore/lore.dart';

void main() {
  group('lintText — matcher error kinds (Story 3.1, FR18)', () {
    test('leaked twee produces a finding on the right line', () {
      final findings = lintText('line one\n<<if \$x>>\nline three');
      expect(findings, hasLength(1));
      expect(findings.first.line, 2);
      expect(findings.first.kind, ConventionKind.leakedTwee);
      expect(findings.first.message, isNotEmpty);
    });

    test('leaked HTML produces a finding', () {
      final findings = lintText('<b>hi</b>');
      expect(findings.map((f) => f.kind), contains(ConventionKind.leakedHtml));
    });

    test('an unterminated [[ produces a malformedMarkup finding', () {
      final findings = lintText('text [[dangling');
      expect(findings.map((f) => f.kind), contains(ConventionKind.malformedMarkup));
    });

    test('a balanced [[]] produces no finding', () {
      expect(lintText('[[Selena]]'), isEmpty);
    });

    test('a dialogue-shaped colon missing its space produces a finding', () {
      final findings = lintText('Frank:hello');
      expect(findings, hasLength(1));
      expect(findings.first.kind, ConventionKind.malformedDialogue);
    });

    test('well-formed dialogue produces no finding', () {
      expect(lintText('Frank: hi'), isEmpty);
    });

    test('an unpaired conditional open produces a finding on its own line '
        '(once the file has a closer elsewhere, evidencing the convention '
        'is in use)', () {
      final findings = lintText('intro\n— если A — текст — конец условия —\n'
          '— если игрок знаком с доктором Джулией — что-то\nmore text');
      final unpaired = findings
          .where((f) => f.kind == ConventionKind.unpairedConditional);
      expect(unpaired, hasLength(1));
      expect(unpaired.first.line, 3);
    });

    test('an unpaired conditional close (stray, no opener) produces a finding', () {
      final findings = lintText('text — конец условия —');
      expect(findings, hasLength(1));
      expect(findings.first.kind, ConventionKind.unpairedConditional);
    });

    test('a fully paired conditional (the ARCHITECTURE.md example) produces '
        'no finding', () {
      final findings = lintText('— если игрок знаком с доктором Джулией — '
          'что-то — иначе — что-то ещё — конец условия —');
      expect(findings, isEmpty);
    });

    test('a valid sceneLink never produces a finding', () {
      expect(lintText('[[Continue->Next Scene]]'), isEmpty);
    });

    test('zero findings for clean text', () {
      expect(lintText('Just some ordinary prose.'), isEmpty);
    });

    test('never throws on pathological input (AD-8)', () {
      expect(() => lintText('<' * 5000), returnsNormally);
    });
  });

  group('lintText — dangling wikilinks (Story 3.1, FR18)', () {
    test('a wikilink matching a known title produces no finding', () {
      final findings = lintText('See [[Selena]] for details.',
          knownEntityNames: {'selena'});
      expect(findings, isEmpty);
    });

    test('a wikilink matching a known alias (not the title) produces no '
        'finding', () {
      final findings = lintText('See [[Frank]] for details.',
          knownEntityNames: {'frank thompson', 'frank'});
      expect(findings, isEmpty);
    });

    test('matching is case-insensitive', () {
      final findings = lintText('See [[SELENA]] for details.',
          knownEntityNames: {'selena'});
      expect(findings, isEmpty);
    });

    test('a wikilink matching nothing known produces a dangling finding', () {
      final findings = lintText('See [[Nobody]] for details.',
          knownEntityNames: {'selena', 'frank'});
      expect(findings, hasLength(1));
      expect(findings.first.kind, ConventionKind.wikilink);
      expect(findings.first.message, contains('Nobody'));
    });

    test('an empty knownEntityNames set skips the dangling check entirely — '
        'never a false "everything is dangling" (AD-8)', () {
      expect(lintText('See [[Anything]] here.'), isEmpty);
    });

    test('a sceneLink is never checked for dangling — only wikilink tokens '
        'are, never sceneLink', () {
      final findings = lintText('[[Nowhere->Passage]]',
          knownEntityNames: {'selena'});
      expect(findings, isEmpty);
    });

    test('multiple dangling wikilinks each produce their own finding', () {
      final findings = lintText('[[A]] and [[B]] and [[Selena]]',
          knownEntityNames: {'selena'});
      expect(findings, hasLength(2));
    });
  });

  group('lintText — emphasized labels and the retired italic monologue '
      '(Story 5.5)', () {
    // A copy of the repo's sample card, lore/characters/mira.md. Before
    // Story 5.5 each of its five labeled lines was a false
    // malformedDialogue finding.
    const miraCard = '''# Mira Vane
aliases: Mira, the old keeper

**Role:** Previous keeper of Saltmere Light. Missing for nine days when the story begins.

**Appearance:** Late fifties, weathered, grey braid, always wore the keeper's spiral pendant.

**Voice / writing style:** Terse, precise, dry humor. Her journal entries are single declarative lines. She never explains — she records.

**Secrets:**
- Knew the Light burns memories, not oil. She was slowly losing hers.
- Sent the letter that brings the protagonist to Saltmere *before* she vanished — she planned her own disappearance.

**Relationships:**
- Old friends with Tomas; he ferried her supplies for twenty years and suspects more than he says.
''';

    test('the sample card lore/characters/mira.md lints clean, with LF or '
        'CRLF line endings', () {
      expect(lintText(miraCard), isEmpty);
      expect(lintText(miraCard.replaceAll('\n', '\r\n')), isEmpty);
    });

    test('a bold label reports nothing; a genuinely missing space after it '
        'still does', () {
      expect(lintText('**Role:** Previous keeper.'), isEmpty);
      final findings = lintText('**Role:**value');
      expect(findings, hasLength(1));
      expect(findings.single.kind, ConventionKind.malformedDialogue);
    });

    test('the retired italic monologue gets its own finding and message — '
        'never "missing a space"', () {
      final findings =
          lintText('Intro.\n*Thought:* She knew.\nThought: plain is fine.');
      expect(findings, hasLength(1));
      expect(findings.single.line, 2);
      expect(findings.single.kind, ConventionKind.italicMonologue);
      expect(findings.single.message, contains('`Thought:`'));
      expect(findings.single.message,
          isNot(lintText('Frank:hello').single.message));
    });
  });

  group('LintFinding', () {
    test('toString is human-readable (debugging aid, not a contract)', () {
      const finding = LintFinding(
        line: 3,
        kind: ConventionKind.leakedTwee,
        message: 'test message',
      );
      expect(finding.toString(), contains('line 3'));
      expect(finding.toString(), contains('test message'));
    });
  });
}
