import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/editor_toolbar.dart';
import 'package:lore_and_story/lore/lore.dart';

TextEditingValue val(String text, {int? base, int? extent}) => TextEditingValue(
      text: text,
      selection: (base == null)
          ? const TextSelection.collapsed(offset: -1)
          : TextSelection(baseOffset: base, extentOffset: extent ?? base),
    );

TextSelection sel(int base, [int? extent]) =>
    TextSelection(baseOffset: base, extentOffset: extent ?? base);

void main() {
  group('insertAtCursor', () {
    test('inserts at the caret and moves it after', () {
      final r = insertAtCursor(val('ac', base: 1), 'b');
      expect(r.text, 'abc');
      expect(r.selection.baseOffset, 2);
      expect(r.selection.isCollapsed, isTrue);
    });

    test('with no valid selection, appends at the end', () {
      final r = insertAtCursor(val('ac'), '!');
      expect(r.text, 'ac!');
      expect(r.selection.baseOffset, 3);
    });
  });

  group('wrapSelection', () {
    test('wraps a non-empty selection and keeps it selected', () {
      final r = wrapSelection(val('abc', base: 0, extent: 3), '**', '**');
      expect(r.text, '**abc**');
      expect(r.selection.baseOffset, 2);
      expect(r.selection.extentOffset, 5);
    });

    test('empty selection inserts the pair with the caret between', () {
      final r = wrapSelection(val('', base: 0), '[[', ']]');
      expect(r.text, '[[]]');
      expect(r.selection.isCollapsed, isTrue);
      expect(r.selection.baseOffset, 2);
    });
  });

  group('prefixLines', () {
    test('prefixes a single line and shifts the caret', () {
      final r = prefixLines(val('title', base: 2), '# ');
      expect(r.text, '# title');
      expect(r.selection.baseOffset, 4);
    });

    test('prefixes every line the selection touches', () {
      // Selection [0,3) covers "a\nb" — lines "a" and "b", not "c".
      final r = prefixLines(val('a\nb\nc', base: 0, extent: 3), '- ');
      expect(r.text, '- a\n- b\nc');
    });

    test('a caret with no selection prefixes only its own line', () {
      final r = prefixLines(val('a\nb\nc', base: 3), '# '); // caret on line "b"
      expect(r.text, 'a\n# b\nc');
    });

    test('a selection ending exactly at a newline does not prefix the next line', () {
      // [0,2) is exactly "a\n" — line "b" is not touched.
      final r = prefixLines(val('a\nb\nc', base: 0, extent: 2), '- ');
      expect(r.text, '- a\nb\nc');
    });

    test('a caret at offset 0 of a buffer starting with a newline prefixes the empty first line', () {
      final r = prefixLines(val('\nb', base: 0), '# ');
      expect(r.text, '# \nb');
      expect(r.selection.baseOffset, 2);
      expect(r.selection.isCollapsed, isTrue);
    });
  });

  group('isFormattingActive', () {
    test('a collapsed caret inside a bold span is active', () {
      final tokens = matchConventions('a **bold** word');
      // caret in the middle of "bold" (index 6, inside "**bold**" [2,10))
      expect(isFormattingActive(tokens, sel(6), ConventionKind.bold), isTrue);
    });

    test('a collapsed caret outside the span is inactive', () {
      final tokens = matchConventions('a **bold** word');
      expect(isFormattingActive(tokens, sel(0), ConventionKind.bold), isFalse);
    });

    test('a collapsed caret exactly at the span edges is active (inclusive)', () {
      final tokens = matchConventions('**bold**'); // span [0, 8)
      expect(isFormattingActive(tokens, sel(0), ConventionKind.bold), isTrue);
      expect(isFormattingActive(tokens, sel(8), ConventionKind.bold), isTrue);
    });

    test('a selection entirely within the span is active', () {
      final tokens = matchConventions('**bold**');
      expect(isFormattingActive(tokens, sel(2, 6), ConventionKind.bold), isTrue);
    });

    test('a selection partially overlapping the span is inactive', () {
      final tokens = matchConventions('**bold** word');
      expect(isFormattingActive(tokens, sel(6, 12), ConventionKind.bold), isFalse);
    });

    test('a different kind at the same position is inactive', () {
      final tokens = matchConventions('_italic_');
      expect(isFormattingActive(tokens, sel(2), ConventionKind.bold), isFalse);
    });

    test('detects and unwraps a star-delimited italic span, not just underscore',
        () {
      final text = 'a *italic* word';
      final tokens = matchConventions(text);
      // span [2, 10) = "*italic*"; caret at 5 sits inside "italic".
      expect(isFormattingActive(tokens, sel(5), ConventionKind.italic), isTrue);
      // The toggle-off strip is length-based (1 char each side), so it works
      // for either delimiter — verified here for `*`, not just the `_` the
      // toolbar's own insert always writes.
      final r = unwrap(val(text, base: 5), 2, 10, 1, 1);
      expect(r.text, 'a italic word');
    });
  });

  group('isHeadingActive', () {
    test('an H1 line activates only level 1, not 2/3', () {
      final text = '# Title';
      final tokens = matchConventions(text);
      expect(isHeadingActive(text, tokens, sel(3), 1), isTrue);
      expect(isHeadingActive(text, tokens, sel(3), 2), isFalse);
      expect(isHeadingActive(text, tokens, sel(3), 3), isFalse);
    });

    test('an H2 line activates only level 2', () {
      final text = '## Title';
      final tokens = matchConventions(text);
      expect(isHeadingActive(text, tokens, sel(3), 1), isFalse);
      expect(isHeadingActive(text, tokens, sel(3), 2), isTrue);
      expect(isHeadingActive(text, tokens, sel(3), 3), isFalse);
    });

    test('a non-heading line is inactive for every level', () {
      final text = 'plain text';
      final tokens = matchConventions(text);
      expect(isHeadingActive(text, tokens, sel(3), 1), isFalse);
    });

    test('a heading using a tab after the #s is still recognized (matcher '
        'allows [ \\t], not just space)', () {
      final text = '#\tTitle';
      final tokens = matchConventions(text);
      expect(isHeadingActive(text, tokens, sel(3), 1), isTrue);
    });

    test('a selection spanning two heading lines is inactive, even though '
        'both lines are headings', () {
      final text = '# One\n# Two';
      final tokens = matchConventions(text);
      expect(isHeadingActive(text, tokens, sel(2, 8), 1), isFalse);
    });
  });

  group('headingPrefixLength / bulletPrefixLength / numberedPrefixLength', () {
    test('heading prefix length is level + 1', () {
      expect(headingPrefixLength(1), 2);
      expect(headingPrefixLength(2), 3);
      expect(headingPrefixLength(3), 4);
    });

    test('bullet prefix length reflects actual leading whitespace', () {
      expect(bulletPrefixLength('- item', sel(3)), 2);
      expect(bulletPrefixLength('  - item', sel(5)), 4);
    });

    test('numbered prefix length reflects the actual digit-run width', () {
      expect(numberedPrefixLength('1. item', sel(4)), 3);
      expect(numberedPrefixLength('42. item', sel(5)), 4);
    });

    test('a non-matching line returns null', () {
      expect(bulletPrefixLength('plain text', sel(3)), isNull);
      expect(numberedPrefixLength('plain text', sel(3)), isNull);
    });
  });

  group('isBulletActive / isNumberedActive', () {
    test('a bullet line activates bullet, not numbered', () {
      final text = '- item';
      final tokens = matchConventions(text);
      expect(isBulletActive(text, tokens, sel(3)), isTrue);
      expect(isNumberedActive(text, tokens, sel(3)), isFalse);
    });

    test('a numbered line with an arbitrary number activates numbered, not '
        'bullet, even though the toolbar always inserts "1. "', () {
      final text = '42. item';
      final tokens = matchConventions(text);
      expect(isNumberedActive(text, tokens, sel(5)), isTrue);
      expect(isBulletActive(text, tokens, sel(5)), isFalse);
    });

    test('a selection spanning two bullet lines is inactive, even though '
        'both lines are bullets', () {
      final text = '- one\n- two';
      final tokens = matchConventions(text);
      expect(isBulletActive(text, tokens, sel(2, 8)), isFalse);
    });
  });

  group('unwrap', () {
    test('round-trips a collapsed caret placed between the delimiters by wrapSelection', () {
      final wrapped = wrapSelection(val('', base: 0), '**', '**');
      expect(wrapped.text, '****');
      expect(wrapped.selection.baseOffset, 2);

      final r = unwrap(wrapped, 0, 4, 2, 2);
      expect(r.text, '');
      expect(r.selection.baseOffset, 0);
      expect(r.selection.isCollapsed, isTrue);
    });

    test('round-trips a non-empty selection placed by wrapSelection', () {
      final wrapped = wrapSelection(val('abc', base: 0, extent: 3), '**', '**');
      expect(wrapped.text, '**abc**');

      final r = unwrap(wrapped, 0, 7, 2, 2);
      expect(r.text, 'abc');
      expect(r.selection.baseOffset, 0);
      expect(r.selection.extentOffset, 3);
    });

    test('unwraps a wikilink with different before/after lengths', () {
      final r = unwrap(val('[[Selena]]'), 0, 10, 2, 2);
      expect(r.text, 'Selena');
    });

    test('out-of-range start/end clamp and never throw', () {
      expect(() => unwrap(val('abc'), -5, 500, 2, 2), returnsNormally);
    });
  });

  group('unprefixLine', () {
    test('round-trips a single-line prefix placed by prefixLines', () {
      final prefixed = prefixLines(val('title', base: 2), '# ');
      expect(prefixed.text, '# title');
      expect(prefixed.selection.baseOffset, 4);

      final r = unprefixLine(prefixed, 0, 2);
      expect(r.text, 'title');
      expect(r.selection.baseOffset, 2);
      expect(r.selection.isCollapsed, isTrue);
    });

    test('removes a numbered-list marker of arbitrary length', () {
      final r = unprefixLine(val('42. item', base: 6), 0, 4);
      expect(r.text, 'item');
      expect(r.selection.baseOffset, 2);
    });

    test('out-of-range lineStart/prefixLen clamp and never throw', () {
      expect(() => unprefixLine(val('abc'), -5, 500), returnsNormally);
    });
  });

  group('out-of-range selection is total (clamped, never throws)', () {
    final stale = TextEditingValue(
      text: 'abc',
      selection: const TextSelection(baseOffset: 0, extentOffset: 50),
    );

    test('insert/wrap/prefix do not throw and clamp to the text length', () {
      expect(() => insertAtCursor(stale, 'x'), returnsNormally);
      expect(() => wrapSelection(stale, '(', ')'), returnsNormally);
      expect(() => prefixLines(stale, '# '), returnsNormally);
      // The extent clamps to 3, so wrap covers the whole (real) text.
      expect(wrapSelection(stale, '(', ')').text, '(abc)');
    });
  });
}
