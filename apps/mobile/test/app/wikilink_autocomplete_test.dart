import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/wikilink_autocomplete.dart';
import 'package:lore_and_story/lore/lore.dart';

TextEditingValue _value(String text, int caret) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );

LoreEntry _entry(String title, {List<String> aliases = const [], bool folder = false}) {
  return LoreEntry(
    id: '${title.toLowerCase()}.md',
    title: title,
    aliases: [title, ...aliases],
    category: 'characters',
    relDir: '.',
    text: '# $title\n',
    tree: folder
        ? const LoreNode(name: '', title: '', overview: null, items: [], children: [])
        : null,
    children: const [],
  );
}

void main() {
  group('findOpenWikilinkQuery', () {
    test('inside an open [[query returns the span', () {
      final q = findOpenWikilinkQuery(_value('text [[Se', 9));
      expect(q, const WikilinkQuery(start: 5, end: 9, query: 'Se'));
    });

    test('right after [[ with no query text yet', () {
      final q = findOpenWikilinkQuery(_value('[[', 2));
      expect(q, const WikilinkQuery(start: 0, end: 2, query: ''));
    });

    test('an already-closed [[x]] is not an open query', () {
      expect(findOpenWikilinkQuery(_value('[[x]]', 5)), isNull);
    });

    test('crossing a newline before reaching [[ returns null', () {
      expect(findOpenWikilinkQuery(_value('[[x\nSe', 6)), isNull);
    });

    test('at the very start of the text returns null', () {
      expect(findOpenWikilinkQuery(_value('', 0)), isNull);
    });

    test('Cyrillic query text', () {
      final q = findOpenWikilinkQuery(_value('текст [[Селе', 12));
      expect(q?.query, 'Селе');
    });

    test('a non-collapsed selection is never "inside" a query', () {
      final value = TextEditingValue(
        text: '[[Selena',
        selection: const TextSelection(baseOffset: 2, extentOffset: 5),
      );
      expect(findOpenWikilinkQuery(value), isNull);
    });

    test('an invalid selection returns null, never throws', () {
      expect(() => findOpenWikilinkQuery(_value('[[x', -1)), returnsNormally);
    });

    test('a ] between the caret and the nearest [[ returns null — the '
        'caret is past a closed bracket, not inside an open query', () {
      expect(findOpenWikilinkQuery(_value('[[x]sometext', 12)), isNull);
    });

    test('an unrelated ] before an unrelated, later [[ does not block '
        'detection of that later, genuinely open query', () {
      final q = findOpenWikilinkQuery(_value(']x[[y', 5));
      expect(q, const WikilinkQuery(start: 2, end: 5, query: 'y'));
    });

    test('(review fix) the caret placed inside an already-closed [[Title]] '
        'is NOT an open query — a backward-only scan would otherwise treat '
        '[[Se|lena]] as an open [[Se query and corrupt the buffer on '
        'completion', () {
      expect(findOpenWikilinkQuery(_value('[[Selena]]', 4)), isNull);
    });

    test('(review fix) the caret inside an already-closed link further down '
        'the same line, with an earlier unrelated closed pair, is still not '
        'open (caret sits inside "Selena" at offset 20 of "[[Other]] and '
        '[[Selena]]")', () {
      expect(findOpenWikilinkQuery(_value('[[Other]] and [[Selena]]', 20)), isNull);
    });

    test('(review fix) a genuinely open query is unaffected by the forward '
        'check when nothing closes it before end of line', () {
      final q = findOpenWikilinkQuery(_value('[[Se and more', 4));
      expect(q, const WikilinkQuery(start: 0, end: 4, query: 'Se'));
    });
  });

  group('matchWikilinkSuggestions', () {
    final entries = [
      _entry('Selena', aliases: ['Sel']),
      _entry('Frank'),
      _entry('Julia'),
    ];

    List<String> titles(List<LoreEntry> es) => es.map((e) => e.title).toList();

    test('case-insensitive starts-with on title', () {
      expect(titles(matchWikilinkSuggestions(entries, 'se')), ['Selena']);
      expect(titles(matchWikilinkSuggestions(entries, 'SE')), ['Selena']);
    });

    test('matches via an alias, and returns the matching entity', () {
      final result = matchWikilinkSuggestions(entries, 'Sel');
      expect(titles(result), ['Selena']);
    });

    test('an entity with no matching name is excluded', () {
      expect(titles(matchWikilinkSuggestions(entries, 'Frank')), ['Frank']);
      expect(titles(matchWikilinkSuggestions(entries, 'Frank')), isNot(contains('Selena')));
    });

    test('empty query lists the first N entities (browsing)', () {
      expect(titles(matchWikilinkSuggestions(entries, '')), ['Selena', 'Frank', 'Julia']);
    });

    test('respects the limit', () {
      final many = List.generate(20, (i) => _entry('Entity$i'));
      expect(matchWikilinkSuggestions(many, '', limit: 5), hasLength(5));
    });

    test('one suggestion per entity even if title and an alias both match '
        '(no duplicate rows)', () {
      final e = _entry('Selena', aliases: ['Selena Ivanova']);
      expect(titles(matchWikilinkSuggestions([e], 'sel')), ['Selena']);
    });

    test('no matches yields an empty list, never throws', () {
      expect(matchWikilinkSuggestions(entries, 'zzz'), isEmpty);
      expect(matchWikilinkSuggestions(const [], 'anything'), isEmpty);
    });

    test('(review fix) two entities sharing a title both surface, as '
        'distinct entries (disambiguated by id downstream, not merged '
        'or shadowed)', () {
      final dup = [
        LoreEntry(
          id: 'characters/selena.md',
          title: 'Selena',
          aliases: const ['Selena'],
          category: 'characters',
          relDir: '.',
          text: '# Selena\n',
          tree: null,
          children: const [],
        ),
        LoreEntry(
          id: 'places/selena.md',
          title: 'Selena',
          aliases: const ['Selena'],
          category: 'places',
          relDir: '.',
          text: '# Selena\n',
          tree: null,
          children: const [],
        ),
      ];
      final result = matchWikilinkSuggestions(dup, 'sel');
      expect(result.map((e) => e.id), ['characters/selena.md', 'places/selena.md']);
    });

    test('(review fix) an entity whose title contains a scene-link '
        'separator is excluded — it could never round-trip as a plain '
        '[[wikilink]]', () {
      for (final title in ['Choice->Passage', 'Return<-Widget', 'A|B', '[[X]]']) {
        final e = _entry(title);
        expect(matchWikilinkSuggestions([e], ''), isEmpty,
            reason: '"$title" should be filtered out');
      }
    });
  });

  group('completeWikilink', () {
    test('replaces the span with [[title]], caret after the closing ]]', () {
      final result = completeWikilink(
        _value('text [[Se', 9),
        const WikilinkQuery(start: 5, end: 9, query: 'Se'),
        'Selena',
      );
      expect(result.text, 'text [[Selena]]');
      expect(result.selection, const TextSelection.collapsed(offset: 15));
    });

    test('a stale span past the current text length is clamped, never '
        'throws (AD-8)', () {
      expect(
        () => completeWikilink(
          _value('short', 5),
          const WikilinkQuery(start: 100, end: 200, query: 'x'),
          'Selena',
        ),
        returnsNormally,
      );
    });

    test('preserves text before and after the span', () {
      final result = completeWikilink(
        _value('before [[Se after', 11),
        const WikilinkQuery(start: 7, end: 11, query: 'Se'),
        'Selena',
      );
      expect(result.text, 'before [[Selena]] after');
    });
  });

  group('findEntryByName', () {
    final entries = [
      _entry('Selena', aliases: ['Sel']),
      _entry('Frank', folder: true),
    ];

    test('exact case-insensitive title match', () {
      expect(findEntryByName(entries, 'selena')?.title, 'Selena');
      expect(findEntryByName(entries, 'SELENA')?.title, 'Selena');
    });

    test('exact alias match', () {
      expect(findEntryByName(entries, 'Sel')?.title, 'Selena');
    });

    test('a starts-with (not exact) match does not resolve — unlike '
        'suggestions, a tap names one specific entity', () {
      expect(findEntryByName(entries, 'Se'), isNull);
    });

    test('no match returns null, never throws (AD-8 — a dangling wikilink '
        'is not this function\'s problem)', () {
      expect(findEntryByName(entries, 'Nobody'), isNull);
      expect(findEntryByName(const [], 'Selena'), isNull);
      expect(findEntryByName(entries, ''), isNull);
    });

    test('a folder entity (tree != null) resolves the same way as a simple '
        'one — routing is the caller\'s job', () {
      expect(findEntryByName(entries, 'Frank')?.tree, isNotNull);
    });
  });
}
