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

    test('scene passage-link syntax is an error, not a wikilink', () {
      expect(matchConventions('[[label->passage]]'),
          [const ConventionToken(0, 18, ConventionKind.scenePassageLink)]);
      expect(matchConventions('[[passage<-label]]'),
          [const ConventionToken(0, 18, ConventionKind.scenePassageLink)]);
      // The inner text must not leak a placeholder/wikilink token.
      expect(kindsOf('[[label->passage]]'), {ConventionKind.scenePassageLink});
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
      expect(kindsOf('[[Селена->станция]]'), {ConventionKind.scenePassageLink});
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
      expect(isError(ConventionKind.scenePassageLink), isTrue);
      expect(isError(ConventionKind.malformedMarkup), isTrue);
      expect(isError(ConventionKind.wikilink), isFalse);
      expect(isError(ConventionKind.bold), isFalse);
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
      expect(kindsOf('<<if>>\r\n[[a->b]]'),
          {ConventionKind.leakedTwee, ConventionKind.scenePassageLink});
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
