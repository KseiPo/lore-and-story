import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/editor_toolbar.dart';

TextEditingValue val(String text, {int? base, int? extent}) => TextEditingValue(
      text: text,
      selection: (base == null)
          ? const TextSelection.collapsed(offset: -1)
          : TextSelection(baseOffset: base, extentOffset: extent ?? base),
    );

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
