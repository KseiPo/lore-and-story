import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/convention_styles.dart';
import 'package:lore_and_story/lore/lore.dart';

void main() {
  const scheme = ColorScheme.light();
  const base = TextStyle(fontSize: 14);

  group('styleForConvention', () {
    test('wikilink is bold-ish and colored, no error decoration', () {
      final s = styleForConvention(ConventionKind.wikilink, scheme, base);
      expect(s.fontWeight, FontWeight.w600);
      expect(s.color, scheme.tertiary);
      expect(s.decorationStyle, isNot(TextDecorationStyle.wavy));
    });

    test('all error kinds share the distinct wavy error style', () {
      for (final kind in errorKinds) {
        final s = styleForConvention(kind, scheme, base);
        expect(s.color, scheme.error, reason: '$kind color');
        expect(s.decoration, TextDecoration.underline, reason: '$kind decoration');
        expect(s.decorationStyle, TextDecorationStyle.wavy, reason: '$kind style');
      }
    });

    test('bold/italic map to weight/style; emDash is colored', () {
      expect(styleForConvention(ConventionKind.bold, scheme, base).fontWeight,
          FontWeight.bold);
      expect(styleForConvention(ConventionKind.italic, scheme, base).fontStyle,
          FontStyle.italic);
      expect(styleForConvention(ConventionKind.emDash, scheme, base).color,
          scheme.primary);
    });
  });

  group('buildConventionSpans', () {
    TextStyle styleFor(ConventionKind k) => styleForConvention(k, scheme, base);

    test('span text always concatenates to the exact input (nothing lost)', () {
      const text = 'see [[Selena]] said <<if x>> — end';
      final spans = buildConventionSpans(
        text,
        matchConventions(text),
        base: base,
        apply: ConventionKind.values.toSet(),
        styleFor: styleFor,
      );
      final joined = spans
          .whereType<TextSpan>()
          .map((s) => s.text ?? '')
          .join();
      expect(joined, text);
    });

    test('only kinds in `apply` are styled; others fall into plain runs', () {
      const text = 'a [[Selena]] b';
      // Apply nothing → a single plain span equal to the input.
      final none = buildConventionSpans(text, matchConventions(text),
          base: base, apply: const {}, styleFor: styleFor);
      expect(none.length, 1);
      expect((none.first as TextSpan).text, text);

      // Apply only wikilink → the [[Selena]] run is split out and styled.
      final wiki = buildConventionSpans(text, matchConventions(text),
          base: base, apply: const {ConventionKind.wikilink}, styleFor: styleFor);
      final styled = wiki
          .whereType<TextSpan>()
          .firstWhere((s) => (s.text ?? '').contains('[[Selena]]'));
      expect(styled.style?.fontWeight, FontWeight.w600);
    });

    test('empty input yields one empty plain span, never throws', () {
      final spans = buildConventionSpans('', const [],
          base: base, apply: ConventionKind.values.toSet(), styleFor: styleFor);
      expect(spans.length, 1);
      expect((spans.first as TextSpan).text, '');
    });
  });
}
