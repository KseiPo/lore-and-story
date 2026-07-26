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
