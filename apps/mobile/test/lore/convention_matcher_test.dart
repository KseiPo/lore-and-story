import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/lore/lore.dart';

/// The kinds present in [text], for concise assertions.
Set<ConventionKind> kindsOf(String text) =>
    matchConventions(text).map((t) => t.kind).toSet();

void main() {
  group('matchConventions — markdown structure', () {
    test('a heading spans the whole line', () {
      expect(matchConventions('# Title'),
          [const ConventionToken(0, 7, ConventionKind.heading)]);
      expect(kindsOf('## Two'), {ConventionKind.heading});
      expect(kindsOf('### Three'), {ConventionKind.heading});
    });

    test('bold and italic', () {
      expect(matchConventions('**b**'),
          [const ConventionToken(0, 5, ConventionKind.bold)]);
      expect(matchConventions('_i_'),
          [const ConventionToken(0, 3, ConventionKind.italic)]);
      expect(matchConventions('*i*'),
          [const ConventionToken(0, 3, ConventionKind.italic)]);
    });

    test('bold is not double-counted as italic', () {
      // `**x**` must be one bold token, never an inner `*x*` italic.
      expect(matchConventions('**x**'),
          [const ConventionToken(0, 5, ConventionKind.bold)]);
    });

    test('list markers (bullet, star, numbered)', () {
      expect(matchConventions('- item').first,
          const ConventionToken(0, 2, ConventionKind.listMarker));
      expect(matchConventions('* item').first,
          const ConventionToken(0, 2, ConventionKind.listMarker));
      expect(matchConventions('1. item').first,
          const ConventionToken(0, 3, ConventionKind.listMarker));
    });
  });

  group('matchConventions — project conventions', () {
    test('wikilink', () {
      expect(matchConventions('[[Selena]]'),
          [const ConventionToken(0, 10, ConventionKind.wikilink)]);
    });

    test('placeholder (single bracket) — and [[x]] is a wikilink, not a placeholder', () {
      expect(matchConventions('[reward]'),
          [const ConventionToken(0, 8, ConventionKind.placeholder)]);
      // `[[x]]` must resolve to a single wikilink, never an inner `[x]`.
      expect(matchConventions('[[x]]'),
          [const ConventionToken(0, 5, ConventionKind.wikilink)]);
    });

    test('a markdown link [label](url) is NOT misclassified as a placeholder '
        '(Story 2.15 review fix)', () {
      expect(kindsOf('[label](url)'), isEmpty);
      // A real placeholder immediately followed by prose text (not `(`) is
      // still recognized normally.
      expect(kindsOf('[reward] later'), {ConventionKind.placeholder});
    });

    test('dialogue speaker with an emotion (Cyrillic is first-class)', () {
      final tokens = matchConventions('Селена (спокойно): реплика');
      expect(tokens.first.kind, ConventionKind.dialogueSpeaker);
      expect(tokens.first.start, 0);
      // Spans up to and including the colon.
      expect('Селена (спокойно): реплика'.substring(0, tokens.first.end),
          'Селена (спокойно):');
    });

    test('dialogue speaker without an emotion', () {
      expect(matchConventions('Frank: hi').first,
          const ConventionToken(0, 6, ConventionKind.dialogueSpeaker));
    });

    test('a plain prose line (no leading name:colon) is not a dialogue speaker', () {
      expect(kindsOf('Just some prose without a speaker.'), isEmpty);
    });

    test('em-dash conditional marker', () {
      // Written before Story 3.1 added conditional-marker recognition
      // (`— если …` / `— конец условия —`, FR18). `'— если —'` alone has no
      // closer anywhere, and the check requires at least one "конец условия"
      // in the text before it reports anything at all (a review-fix
      // narrowing — see the "unpaired conditional markers" group's own
      // comment) — so this stays two generic emDash tokens, same as before
      // Story 3.1, not because the feature doesn't exist but because a lone
      // "если" with zero convention evidence anywhere in the file is
      // indistinguishable from ordinary prose.
      final tokens = matchConventions('— если —');
      expect(tokens.map((t) => t.kind), everyElement(ConventionKind.emDash));
      expect(tokens.length, 2);
    });

    test('a line-start wikilink in a dialogue-shaped line keeps its wikilink highlight', () {
      // The wikilinked speaker must not be swallowed by dialogue-speaker detection.
      final kinds = kindsOf('[[Селена]] (спокойно): реплика');
      expect(kinds, contains(ConventionKind.wikilink));
    });
  });

  group('matchConventions — sceneLink (Story 2.15: unified scene-navigation links)', () {
    test('-> and <- and | all produce sceneLink, not wikilink', () {
      expect(matchConventions('[[label->passage]]'),
          [const ConventionToken(0, 18, ConventionKind.sceneLink)]);
      expect(matchConventions('[[passage<-label]]'),
          [const ConventionToken(0, 18, ConventionKind.sceneLink)]);
      expect(matchConventions('[[label|passage]]'),
          [const ConventionToken(0, 17, ConventionKind.sceneLink)]);
      // The inner text must not leak a placeholder/wikilink token.
      expect(kindsOf('[[label->passage]]'), {ConventionKind.sceneLink});
    });

    test('sceneLink is a valid convention, not an error', () {
      expect(isError(ConventionKind.sceneLink), isFalse);
      expect(errorKinds, isNot(contains(ConventionKind.sceneLink)));
    });

    test('a bracket pair with no separator still resolves to wikilink '
        '(regression guard for the core disambiguation rule)', () {
      expect(matchConventions('[[Title]]'),
          [const ConventionToken(0, 9, ConventionKind.wikilink)]);
      expect(matchConventions('[[Selena]]'),
          [const ConventionToken(0, 10, ConventionKind.wikilink)]);
    });

    test('Cyrillic sceneLink content is first-class', () {
      expect(kindsOf('[[Селена->станция]]'), {ConventionKind.sceneLink});
    });

    test('sceneLink is CRLF-safe', () {
      expect(kindsOf('<<if>>\r\n[[a->b]]'),
          {ConventionKind.leakedTwee, ConventionKind.sceneLink});
    });

    test('an empty label/target does not crash (AD-8, degenerate but total)', () {
      expect(() => matchConventions('[[->]]'), returnsNormally);
      expect(kindsOf('[[->]]'), {ConventionKind.sceneLink});
    });

    test('Story 3.1\'s new error kinds never flag a sceneLink — FR9a/FR18\'s '
        'old "Twine passage-link syntax is an error" wording is stale and '
        'superseded by this story (2026-08-05), see the story\'s Context '
        'section', () {
      expect(kindsOf('[[Continue->Next Scene]]'),
          isNot(contains(ConventionKind.malformedDialogue)));
      expect(kindsOf('[[Continue->Next Scene]]'),
          isNot(contains(ConventionKind.unpairedConditional)));
      expect(kindsOf('[[Continue->Next Scene]]'), {ConventionKind.sceneLink});
    });
  });

  group('matchConventions — invalid/suspect markup (FR9a)', () {
    test('leaked twee macros are flagged over the whole <<…>> run', () {
      expect(matchConventions('<<if \$x>>'),
          [const ConventionToken(0, 9, ConventionKind.leakedTwee)]);
      expect(matchConventions('<<=\$var>>'),
          [const ConventionToken(0, 9, ConventionKind.leakedTwee)]);
      expect(matchConventions('<<linkBack>>'),
          [const ConventionToken(0, 12, ConventionKind.leakedTwee)]);
    });

    test('leaked twee wins over an inner HTML-shaped match', () {
      // `<<x>>` contains the HTML-shaped `<x>` — the twee run must claim it.
      expect(matchConventions('<<x>>'),
          [const ConventionToken(0, 5, ConventionKind.leakedTwee)]);
    });

    test('a macro with an interior > or < is still flagged (delimiter fallback)', () {
      // The two most idiomatic leaked shapes — a comparison and a link macro —
      // carry an interior `>`/`<` the clean whole-macro pattern can't span; the
      // `<<`/`>>` delimiters must still flag them as leakedTwee (never HTML).
      expect(kindsOf('<<if \$hp >= 100>>'), {ConventionKind.leakedTwee});
      expect(kindsOf('<<link "Next" -> "Scene2">>'), {ConventionKind.leakedTwee});
      expect(kindsOf('<<if \$x < 5>>'), {ConventionKind.leakedTwee});
      // The `<<` opener is flagged even with no closer on the line.
      expect(kindsOf('stray <<if \$x'), {ConventionKind.leakedTwee});
    });

    test('leaked HTML tags are flagged', () {
      expect(matchConventions('<b>'),
          [const ConventionToken(0, 3, ConventionKind.leakedHtml)]);
      expect(matchConventions('</i>'),
          [const ConventionToken(0, 4, ConventionKind.leakedHtml)]);
      expect(matchConventions('<br/>'),
          [const ConventionToken(0, 5, ConventionKind.leakedHtml)]);
      expect(matchConventions('<div class="x">'),
          [const ConventionToken(0, 15, ConventionKind.leakedHtml)]);
    });

    test('a plain wikilink stays valid (no false error)', () {
      expect(matchConventions('[[Title]]'),
          [const ConventionToken(0, 9, ConventionKind.wikilink)]);
    });

    test('an unterminated [[ is flagged malformed; a balanced [[]] is not', () {
      final tokens = matchConventions('see [[Selena');
      expect(tokens, [const ConventionToken(4, 6, ConventionKind.malformedMarkup)]);
      // The toolbar inserts a balanced empty pair — never an error.
      expect(matchConventions('[[]]'), isEmpty);
    });

    test('Cyrillic is first-class inside error markup', () {
      expect(kindsOf('<<если>>'), {ConventionKind.leakedTwee});
    });

    test('no false positives on innocent angle brackets / brackets', () {
      // Space or a non-letter after `<` is prose, not a tag.
      expect(kindsOf('5 < 10'), isEmpty);
      expect(kindsOf('a <3 heart'), isEmpty);
      expect(kindsOf('>:( face'), isEmpty);
    });

    test('errorKinds / isError expose the error set as one source of truth', () {
      expect(isError(ConventionKind.leakedTwee), isTrue);
      expect(isError(ConventionKind.leakedHtml), isTrue);
      expect(isError(ConventionKind.malformedMarkup), isTrue);
      expect(isError(ConventionKind.wikilink), isFalse);
      expect(isError(ConventionKind.bold), isFalse);
      expect(isError(ConventionKind.sceneLink), isFalse);
      expect(errorKinds, everyElement(predicate<ConventionKind>(isError)));
    });

    test('error and valid kinds coexist, sorted and non-overlapping', () {
      final tokens = matchConventions('[[Selena]] said <<if \$x>> and <b>');
      for (var i = 1; i < tokens.length; i++) {
        expect(tokens[i - 1].end <= tokens[i].start, isTrue,
            reason: 'overlap between ${tokens[i - 1]} and ${tokens[i]}');
      }
      expect(tokens.map((t) => t.kind),
          containsAll([
            ConventionKind.wikilink,
            ConventionKind.leakedTwee,
            ConventionKind.leakedHtml,
          ]));
    });

    test('error markup is CRLF-safe', () {
      expect(kindsOf('<<if>>\r\n<b>'),
          {ConventionKind.leakedTwee, ConventionKind.leakedHtml});
    });

    test('adversarial input stays linear — never hangs (ReDoS guard)', () {
      final sw = Stopwatch()..start();
      matchConventions('<' * 50000);
      matchConventions('[' * 50000);
      matchConventions('<<' * 20000);
      matchConventions('<<<>>>' * 10000);
      // The trap the `contains('>>')` guard alone does NOT cover: a `>>` exists
      // on the line (guard passes) but never *after* the `<<` run, so a body
      // class that spans `>` would scan-and-backtrack O(n²) per opener. Excluding
      // `<` from the body keeps each attempt opener-bounded.
      matchConventions('>>${'<<' * 20000}');
      // Many real macros with an interior `>` (exercises the delimiter fallback).
      matchConventions('<<if \$x >= 5>>' * 2000);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'error regexes must be linear, not backtracking');
    });
  });

  group('matchConventions — malformed dialogue (Story 3.1, FR18)', () {
    test('a dialogue-shaped colon with no trailing space is flagged', () {
      expect(matchConventions('Frank:hello').first,
          const ConventionToken(0, 6, ConventionKind.malformedDialogue));
      expect(kindsOf('Иван:привет'), {ConventionKind.malformedDialogue});
    });

    test('a well-formed dialogue line is never also flagged as malformed', () {
      expect(kindsOf('Frank: hi'), {ConventionKind.dialogueSpeaker});
      expect(kindsOf('Frank:'), {ConventionKind.dialogueSpeaker});
      expect(kindsOf('Селена (спокойно): реплика'),
          {ConventionKind.dialogueSpeaker});
    });

    test('a single-symbol "prefix" (e.g. an emoticon) is never flagged — '
        'regression guard for the >:( false positive found while adding '
        'this pattern', () {
      expect(kindsOf('>:( face'), isEmpty);
      expect(kindsOf('>:(no space'), isEmpty);
    });

    test('ordinary prose with an early colon and no space after it is '
        'flagged (accepted, narrow tradeoff — see the pattern\'s own '
        'comment)', () {
      // Two words minimum avoids single-symbol false positives (above) but
      // does not attempt to distinguish real dialogue intent from prose.
      expect(kindsOf('Note:see below'), {ConventionKind.malformedDialogue});
    });

    test('URLs, timestamps, and ratios are never flagged (review fix — '
        'regression guard for false positives found by the code review)',
        () {
      expect(kindsOf('http://example.com/page'), isEmpty);
      expect(kindsOf('https://example.com'), isEmpty);
      expect(kindsOf('12:30 he arrived'), isEmpty);
      expect(kindsOf('Ratio 3:1 is fine'), isEmpty);
      expect(kindsOf('Ratio 10:1 here'), isEmpty);
      // The exact shape the Story 2.15 "External link" toolbar button
      // inserts — must not be flagged as broken dialogue.
      expect(kindsOf('See [link](http://x) here'), isEmpty);
    });
  });

  group('matchConventions — emphasized labels are not malformed dialogue '
      '(Story 5.5)', () {
    test('a profile label whose colon sits inside the bold is just bold — '
        'the reported false positive; the bold token it used to hide (which '
        'the toolbar\'s Bold active state reads) is back', () {
      expect(matchConventions('**Role:** Previous keeper of Saltmere Light.'),
          [const ConventionToken(0, 9, ConventionKind.bold)]);
      expect(kindsOf('**Селена:** Привет.'), {ConventionKind.bold});
    });

    test('the label may end the line (e.g. heading the list below it), '
        'including under CRLF', () {
      expect(matchConventions('**Secrets:**'),
          [const ConventionToken(0, 12, ConventionKind.bold)]);
      expect(kindsOf('**Secrets:**\r\n- Knew the Light burns memories.'),
          {ConventionKind.bold, ConventionKind.listMarker});
    });

    test('italic, underscore, and nested emphasis closers are recognized too',
        () {
      expect(kindsOf('*Note:* see arc.md'), {ConventionKind.italic});
      // Exactly what the toolbar's italic button inserts around a selection.
      expect(kindsOf('_Note:_ see arc.md'), {ConventionKind.italic});
      // Toolbar bold, then italic, on the same label — it closes with `_**`.
      expect(kindsOf('**_Role:_** value'), {ConventionKind.bold});
      // The matcher doesn't model `__bold__` or bold-italic as `bold`, so
      // only the absence of an error is asserted for these two.
      expect(kindsOf('__Role:__ value').where(isError), isEmpty);
      expect(kindsOf('***Role:*** value').where(isError), isEmpty);
    });

    test('other label shapes the old pattern also tripped on', () {
      expect(kindsOf('**Voice / writing style:** Terse, precise.'),
          {ConventionKind.bold});
      expect(kindsOf('**Age:** 42'), {ConventionKind.bold});
      expect(kindsOf('  **Indented:** value'), {ConventionKind.bold});
      expect(kindsOf('Note that **the key:** matters'), {ConventionKind.bold});
    });

    test('a closer followed by punctuation, or a longer delimiter run, still '
        'closes the label (review fix)', () {
      expect(kindsOf('**Role:**, value'), {ConventionKind.bold});
      expect(kindsOf('**Role:**.'), {ConventionKind.bold});
      expect(kindsOf('(**Note:**) see arc.md'), {ConventionKind.bold});
      // A doubled `****` is what pressing Bold on a label produced while the
      // old false positive hid the bold token from the toolbar.
      expect(kindsOf('****Role:**** value').where(isError), isEmpty);
      expect(kindsOf('**__Role:__** value').where(isError), isEmpty);
    });

    test('a genuinely missing space is still flagged — including one right '
        'after the closing emphasis', () {
      expect(matchConventions('**Role:**value').first,
          const ConventionToken(0, 7, ConventionKind.malformedDialogue));
      expect(kindsOf('Frank:**hello**'),
          contains(ConventionKind.malformedDialogue));
      expect(kindsOf('Frank:_hello_'),
          contains(ConventionKind.malformedDialogue));
      expect(kindsOf('*Note:*text'), {ConventionKind.malformedDialogue});
      // The retired monologue form with no space after it is a missing
      // space, never also an italicMonologue (the two are disjoint).
      expect(kindsOf('*Thought:*text'), {ConventionKind.malformedDialogue});
    });

    test('an emphasis run that opens right after the colon is no closer — '
        'nothing was opened before the colon (review fix)', () {
      expect(kindsOf('Frank:* sighs heavily* Look.'),
          contains(ConventionKind.malformedDialogue));
      expect(kindsOf('Selena:** frowns** Careful.'),
          contains(ConventionKind.malformedDialogue));
      expect(kindsOf('Note:_ дальше по тексту_ пояснение.'),
          contains(ConventionKind.malformedDialogue));
      expect(kindsOf('Frank:** hi'), {ConventionKind.malformedDialogue});
    });

    test('emphasis-delimiter runs after a colon stay linear (ReDoS guard)', () {
      final sw = Stopwatch()..start();
      matchConventions('ab:${'*' * 50000}');
      matchConventions('**ab:${'_' * 50000}x');
      matchConventions('_${'_' * 50000}:');
      // The opener check looks back across the whole emotion group.
      matchConventions('a (${'x' * 50000}):* x');
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'the emphasis-closer lookahead must stay bounded');
    });
  });

  group('matchConventions — retired italic inner monologue (Story 5.5)', () {
    test('the retired `*Thought:*` form is its own error kind, spanning the '
        'whole emphasized label', () {
      expect(matchConventions('*Thought:* She knew.'),
          [const ConventionToken(0, 10, ConventionKind.italicMonologue)]);
      expect(isError(ConventionKind.italicMonologue), isTrue);
      expect(errorKinds, contains(ConventionKind.italicMonologue));
    });

    test('underscore italics, the RU mirror, an emotion, end of line, and CRLF',
        () {
      expect(kindsOf('_Thought:_ She knew.'), {ConventionKind.italicMonologue});
      expect(kindsOf('*Мысль:* Она знала.'), {ConventionKind.italicMonologue});
      expect(kindsOf('*Thought (tired):* Not again.'),
          {ConventionKind.italicMonologue});
      expect(kindsOf('*Мысль (устало):* Опять.'),
          {ConventionKind.italicMonologue});
      expect(kindsOf('*Thought:*'), {ConventionKind.italicMonologue});
      expect(kindsOf('*Thought:*\r\nnext'), {ConventionKind.italicMonologue});
    });

    test('punctuation after the closer, or a mismatched closer run, is still '
        'the retired form — never a "missing space" or silence (review fix)',
        () {
      expect(kindsOf('*Thought:*, she thought.'),
          {ConventionKind.italicMonologue});
      expect(kindsOf('*Мысль:*.'), {ConventionKind.italicMonologue});
      expect(kindsOf('*Thought:** value'), {ConventionKind.italicMonologue});
      expect(kindsOf('*Thought:**'), {ConventionKind.italicMonologue});
    });

    test('is case-insensitive', () {
      expect(kindsOf('*thought:* x'), {ConventionKind.italicMonologue});
      expect(kindsOf('*МЫСЛЬ:* x'), {ConventionKind.italicMonologue});
    });

    test('the current plain form stays valid and is never flagged', () {
      expect(matchConventions('Thought: She knew.').first,
          const ConventionToken(0, 8, ConventionKind.dialogueSpeaker));
      expect(kindsOf('Мысль (устало): Опять.'), {ConventionKind.dialogueSpeaker});
    });

    test('only the retired shape is flagged — never other emphasized labels',
        () {
      // Bold monologue was never a convention in any version (out of scope).
      expect(kindsOf('**Thought:** x'), {ConventionKind.bold});
      expect(kindsOf('*Thoughts:* x'), {ConventionKind.italic});
      // Line-anchored, like dialogue: a mid-line italic "thought:" is prose.
      expect(kindsOf('He had one *thought:* only.').where(isError), isEmpty);
    });

    test('an emotion containing a colon still yields one italicMonologue '
        'token — it outranks the dialogue patterns that stop at the inner '
        'colon (same priority, longer span wins)', () {
      expect(matchConventions('*Thought (a: b):* x'),
          [const ConventionToken(0, 17, ConventionKind.italicMonologue)]);
    });

    test('stays linear on adversarial input (ReDoS guard)', () {
      final sw = Stopwatch()..start();
      matchConventions('*Thought (${'x' * 50000}');
      matchConventions('*Thought${' ' * 50000}x');
      matchConventions('_Мысль${'\t' * 50000}:');
      matchConventions('*Thought:${'*' * 50000}x');
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'the italic-monologue pattern must stay linear');
    });
  });

  group('matchConventions — unpaired conditional markers (Story 3.1, FR18)', () {
    test('the exact ARCHITECTURE.md example, fully paired, is never flagged', () {
      const text = '— если игрок знаком с доктором Джулией — что-то — '
          'иначе — что-то ещё — конец условия —';
      expect(kindsOf(text), isNot(contains(ConventionKind.unpairedConditional)));
    });

    test('a file that never uses this convention (no "конец условия" '
        'anywhere) is never flagged, even with an unmatched "если" — '
        '(review fix) the whole check requires evidence the convention is '
        'in use at all, since an ordinary literary em-dash aside using '
        '"если" is indistinguishable from a real open marker on its own',
        () {
      const withoutCloser = '— если игрок знаком с доктором Джулией — что-то';
      expect(matchConventions(withoutCloser),
          everyElement(isA<ConventionToken>().having(
              (t) => t.kind, 'kind', isNot(ConventionKind.unpairedConditional))));

      // The exact false-positive case the review caught: an ordinary
      // literary aside, not this app's structural marker at all.
      const literaryAside =
          'Она замолчала — если бы он знал, что будет дальше — и вздохнула.';
      expect(kindsOf(literaryAside),
          isNot(contains(ConventionKind.unpairedConditional)));
    });

    test('an unclosed opener IS flagged once the file has at least one '
        'closer elsewhere — evidence the convention is genuinely in use',
        () {
      const text = '— если A — текст — конец условия — '
          'позже — если B — без конца совсем';
      final tokens = matchConventions(text)
          .where((t) => t.kind == ConventionKind.unpairedConditional);
      expect(tokens, hasLength(1));
      expect(text.substring(tokens.first.start, tokens.first.end),
          contains('если B'));
    });

    test('a stray closer with no opener is flagged at the closer', () {
      const text = 'какой-то текст — конец условия —';
      final tokens = matchConventions(text);
      expect(tokens, hasLength(1));
      expect(tokens.first.kind, ConventionKind.unpairedConditional);
      expect(text.substring(tokens.first.start, tokens.first.end),
          contains('конец условия'));
    });

    test('two opens and one close leaves exactly one opener unpaired '
        '(LIFO stack)', () {
      const text = '— если A — текст — если B — текст — конец условия —';
      final tokens = matchConventions(text);
      expect(
          tokens.where((t) => t.kind == ConventionKind.unpairedConditional),
          hasLength(1));
    });

    test('is case-insensitive', () {
      // A capitalized "Если" pairs correctly with a lowercase closer.
      const paired = '— Если что-то — текст — конец условия —';
      expect(kindsOf(paired), isNot(contains(ConventionKind.unpairedConditional)));

      // A second, unmatched capitalized "Если" is still detected as
      // unpaired, once the file has evidence of the convention (the closer
      // above already satisfies the file-level gate).
      const withExtra = '$paired позже — Если этот — не закрыт';
      expect(kindsOf(withExtra), contains(ConventionKind.unpairedConditional));
    });

    test('an opener on one line paired with a closer on a later line is '
        'correctly recognized as balanced — this check is cross-line, '
        'unlike every other kind in this file', () {
      const text = '— если что-то —\nтекст на другой строке\n— конец условия —';
      expect(kindsOf(text), isNot(contains(ConventionKind.unpairedConditional)));
    });

    test('two overlapping markers sharing one em-dash delimiter never '
        'produce overlapping tokens (review fix — regression guard for a '
        'violation of the documented non-overlapping contract)', () {
      const text = 'текст — конец условия — если A — далее';
      final tokens = matchConventions(text);
      for (var i = 1; i < tokens.length; i++) {
        expect(tokens[i - 1].end <= tokens[i].start, isTrue,
            reason: 'overlap between ${tokens[i - 1]} and ${tokens[i]}');
      }
    });

    test('a wikilink inside a condition clause is preserved — never '
        'swallowed into the marker span (review fix — this fed a silent '
        'hole in the AC4 dangling-wikilink check)', () {
      const text = '— если [[Selena]] знает — что-то — конец условия —';
      expect(kindsOf(text), contains(ConventionKind.wikilink));
    });

    test('bold inside an UNPAIRED marker\'s span is still swallowed — '
        'consistent with every other error kind in this file ("the '
        'interior is never partially styled"); a PAIRED marker never '
        'produces a token at all, so it never swallows anything', () {
      // The first "если" pairs cleanly with the closer (no token emitted,
      // nothing swallowed there). The second, bold-containing "если" has no
      // closer left to pair with, so it's the one that ends up unpaired —
      // and swallows the bold inside its own span.
      const text = '— если этот — текст — конец условия — '
          'потом — если **важно** — без конца';
      final tokens = matchConventions(text);
      for (var i = 1; i < tokens.length; i++) {
        expect(tokens[i - 1].end <= tokens[i].start, isTrue,
            reason: 'overlap between ${tokens[i - 1]} and ${tokens[i]}');
      }
      expect(kindsOf(text), isNot(contains(ConventionKind.bold)));
      expect(kindsOf(text), contains(ConventionKind.unpairedConditional));
    });

    test('an ordinary em-dash aside with no "если" is never flagged '
        '(baseline — emDash alone is not a marker)', () {
      expect(kindsOf('Она замолчала — надолго.'),
          isNot(contains(ConventionKind.unpairedConditional)));
    });
  });

  group('matchConventions — English conditional markers (Story 5.7, FR18)', () {
    test('a fully paired English conditional is never flagged', () {
      const text = '— if the player knows Julia — text — else — other — '
          'end if —';
      expect(kindsOf(text), isNot(contains(ConventionKind.unpairedConditional)));
    });

    test('no closer anywhere means no finding (the file-level gate) — '
        'including an ordinary literary "— if … —" aside', () {
      const withoutCloser = '— if the player knows Julia — text';
      expect(kindsOf(withoutCloser),
          isNot(contains(ConventionKind.unpairedConditional)));
      const literaryAside = 'She would come — if he asked — and stay.';
      expect(kindsOf(literaryAside),
          isNot(contains(ConventionKind.unpairedConditional)));
    });

    test('an unclosed English opener is flagged once the file has a closer '
        'elsewhere, spanning the opener', () {
      const text = '— if A — text — end if — later — if B — never closed';
      final tokens = matchConventions(text)
          .where((t) => t.kind == ConventionKind.unpairedConditional);
      expect(tokens, hasLength(1));
      expect(text.substring(tokens.first.start, tokens.first.end),
          contains('if B'));
    });

    test('a stray "— end if —" with no opener is flagged at the closer', () {
      const text = 'some text — end if —';
      final tokens = matchConventions(text);
      expect(tokens, hasLength(1));
      expect(tokens.first.kind, ConventionKind.unpairedConditional);
      expect(text.substring(tokens.first.start, tokens.first.end),
          contains('end if'));
    });

    test('an opener and a closer on different lines pair up', () {
      const text = '— if something —\ntext on another line\n— end if —';
      expect(kindsOf(text), isNot(contains(ConventionKind.unpairedConditional)));
    });

    test('is case-insensitive', () {
      const text = '— If the player knows Julia — text — END IF —';
      expect(kindsOf(text), isNot(contains(ConventionKind.unpairedConditional)));
    });

    test('"if" must be a whole word — "iffy" / "ifs" are never openers '
        '(AC2)', () {
      // The closer satisfies the gate; if either aside were read as an
      // opener it would be left unpaired and flagged.
      const text = '— if A — text — end if — then — iffy weather — and — ifs '
          'and buts — done';
      expect(kindsOf(text), isNot(contains(ConventionKind.unpairedConditional)));
    });

    test('a wikilink in an English condition keeps the opener from '
        'matching, so the closer is flagged — the same bracket rule as '
        'Russian', () {
      const text = '— if [[Selena]] knows — text — end if —';
      expect(kindsOf(text), contains(ConventionKind.wikilink));
      expect(kindsOf(text), contains(ConventionKind.unpairedConditional));
    });

    test('pairing is language-agnostic: a Russian opener closed by '
        '"— end if —" counts as paired', () {
      const text = '— если игрок знаком с Джулией — текст — end if —';
      expect(kindsOf(text), isNot(contains(ConventionKind.unpairedConditional)));
      const reverse = '— if the player knows Julia — text — конец условия —';
      expect(
          kindsOf(reverse), isNot(contains(ConventionKind.unpairedConditional)));
    });
  });

  group('matchConventions — robustness', () {
    test('CRLF input is not broken by the trailing \\r', () {
      // Heading + list marker still detected across CRLF line endings.
      expect(kindsOf('# A\r\n- b'),
          {ConventionKind.heading, ConventionKind.listMarker});
      expect(kindsOf('[[y]]\r\n**z**'),
          {ConventionKind.wikilink, ConventionKind.bold});
    });

    test('tokens are sorted and non-overlapping', () {
      final tokens = matchConventions('- **b** [[w]] [p] —');
      for (var i = 1; i < tokens.length; i++) {
        expect(tokens[i - 1].end <= tokens[i].start, isTrue,
            reason: 'overlap between ${tokens[i - 1]} and ${tokens[i]}');
      }
    });

    test('empty and whitespace input yield no tokens, no throw', () {
      expect(matchConventions(''), isEmpty);
      expect(matchConventions('   \n  \n'), isEmpty);
    });

    test('pathological input never throws', () {
      expect(() => matchConventions('[' * 5000), returnsNormally);
      expect(() => matchConventions('*' * 5000), returnsNormally);
      expect(() => matchConventions('[[' * 2000), returnsNormally);
      expect(() => matchConventions('${'—' * 3000}\n${'#' * 3000}'), returnsNormally);
    });
  });
}
