import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/markdown_preview.dart';

import 'markdown_span_test_helpers.dart';

/// Pumps [MarkdownPreview] for [text] and returns nothing — callers query the
/// tree via `find`. A real MaterialApp gives it a Theme.
Future<void> pumpPreview(WidgetTester tester, String text) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: MarkdownPreview(text: text))));
  await tester.pump();
}

void main() {
  testWidgets('renders headings, bold, italic as styled runs', (tester) async {
    await pumpPreview(tester, '# Title\n\nsome **bold** and _italic_ words');
    expect(find.textContaining('Title'), findsWidgets);
    expect(spanWith(tester, 'bold').style?.fontWeight, FontWeight.bold);
    expect(spanWith(tester, 'italic').style?.fontStyle, FontStyle.italic);
  });

  testWidgets('renders unordered and ordered lists (incl. nesting)', (tester) async {
    await pumpPreview(tester, '- one\n- two\n  - nested\n\n1. first\n2. second');
    expect(find.textContaining('one'), findsWidgets);
    expect(find.textContaining('nested'), findsWidgets);
    expect(find.textContaining('first'), findsWidgets);
  });

  testWidgets('renders a fenced code block in monospace', (tester) async {
    await pumpPreview(tester, '```\ncode here\n```');
    final code = spanWith(tester, 'code here');
    expect(code.style?.fontFamily, 'monospace');
  });

  testWidgets('renders a blockquote and a thematic break without error', (tester) async {
    await pumpPreview(tester, '> quoted\n\n---\n\nafter');
    expect(find.textContaining('quoted'), findsWidgets);
    expect(find.textContaining('after'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a link renders as styled (non-tappable) text', (tester) async {
    await pumpPreview(tester, '[label](http://example.com)');
    expect(find.textContaining('label'), findsWidgets);
    // No GestureDetector/InkWell wrapping the link text in v0.1.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an image renders as its alt text / placeholder (no file load)',
      (tester) async {
    await pumpPreview(tester, '![a hero picture](media/hero.png)');
    // Alt text is surfaced; no Image widget is built (loading is Story 2.16).
    expect(find.textContaining('hero picture'), findsWidgets);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('malformed markdown never throws; the text still shows (AD-8)',
      (tester) async {
    await pumpPreview(tester, '# [[unclosed **bold ```\n<<if \$x >> ]]] [](');
    expect(tester.takeException(), isNull);
    // Best-effort: the raw content is still visible somewhere.
    expect(find.textContaining('unclosed'), findsWidgets);
  });

  testWidgets('empty buffer renders nothing and never throws', (tester) async {
    await pumpPreview(tester, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cyrillic content renders intact', (tester) async {
    await pumpPreview(tester, '# Селена\n\nреплика — и всё.');
    expect(find.textContaining('Селена'), findsWidgets);
    expect(find.textContaining('реплика'), findsWidgets);
  });

  group('project conventions styled (AD-7 reuse)', () {
    testWidgets('a [[wikilink]] run is styled as a convention, not plain',
        (tester) async {
      await pumpPreview(tester, 'see [[Selena]] here');
      final span = spanWith(tester, '[[Selena]]');
      expect(span.text, '[[Selena]]'); // split into its own run
      expect(span.style?.fontWeight, FontWeight.w600); // wikilink style
    });

    testWidgets('leaked twee gets the distinct wavy error style', (tester) async {
      await pumpPreview(tester, 'oops <<if \$x>> leaked');
      final span = spanWith(tester, '<<if \$x>>');
      expect(span.style?.decorationStyle, TextDecorationStyle.wavy);
    });

    testWidgets('a scene passage-link [[a->b]] is styled distinctly, not as an '
        'error (Story 2.15: unified link forms)', (tester) async {
      await pumpPreview(tester, 'go [[Choice->Passage]] here');
      final span = spanWith(tester, '[[Choice->Passage]]');
      expect(span.style?.decorationStyle, isNot(TextDecorationStyle.wavy));
      expect(span.text, '[[Choice->Passage]]'); // split into its own run
    });

    testWidgets('a plain wikilink is NOT given the error style', (tester) async {
      await pumpPreview(tester, 'good [[Selena]] ref');
      final span = spanWith(tester, '[[Selena]]');
      expect(span.style?.decorationStyle, isNot(TextDecorationStyle.wavy));
    });

    testWidgets('markdown-structural markup is rendered by markdown, not the matcher',
        (tester) async {
      // `**bold**` becomes a real bold run with the markers gone — the matcher
      // must not re-style it (the `**` are consumed by markdown).
      await pumpPreview(tester, 'a **bold** word');
      expect(spanWith(tester, 'bold').style?.fontWeight, FontWeight.bold);
      expect(find.textContaining('**'), findsNothing);
    });

    testWidgets('a [placeholder] and an em-dash are styled as conventions',
        (tester) async {
      await pumpPreview(tester, 'give [reward] to hero — now');
      // placeholder → italic; em-dash split into its own styled run.
      expect(spanWith(tester, '[reward]').style?.fontStyle, FontStyle.italic);
      expect(spanWith(tester, '—').text, '—');
    });

    testWidgets('leaked HTML is flagged with the wavy error style', (tester) async {
      await pumpPreview(tester, 'text <b>x</b> more');
      expect(spanWith(tester, '<b>').style?.decorationStyle, TextDecorationStyle.wavy);
    });

    testWidgets('a whole-line dialogue speaker is styled', (tester) async {
      await pumpPreview(tester, 'Frank (angry): hi there');
      expect(spanWith(tester, 'Frank (angry)').style?.fontWeight, FontWeight.w600);
    });

    testWidgets('no false dialogue speaker on prose after inline markup (Review P1)',
        (tester) async {
      // `intro:` sits mid-line after a bold run — it must NOT be styled as a
      // speaker (the fragment is not the block's first run).
      await pumpPreview(tester, 'See **bold** intro: this.');
      expect(spanWith(tester, 'bold').style?.fontWeight, FontWeight.bold);
      expect(spanWith(tester, 'intro').style?.fontWeight, isNot(FontWeight.w600));
    });

    testWidgets('a valid wikilink containing emphasis is NOT error-flagged (Review P1)',
        (tester) async {
      // `[[Se*le*na]]` splits around `*le*`; the `[[Se` fragment must not fire a
      // false "unterminated [[" error.
      await pumpPreview(tester, 'ref [[Se*le*na]] here');
      final wavy = allSpans(tester)
          .any((s) => s.style?.decorationStyle == TextDecorationStyle.wavy);
      expect(wavy, isFalse);
    });
  });

  group('GFM rendering (Review P2–P5)', () {
    testWidgets('a table renders as a real Table with separated cells', (tester) async {
      await pumpPreview(tester, '| Name | Age |\n|---|---|\n| Frank | 30 |');
      expect(find.byType(Table), findsOneWidget);
      expect(spanWith(tester, 'Name').text, 'Name');
      expect(spanWith(tester, 'Frank').text, 'Frank');
      expect(spanWith(tester, '30').text, '30');
    });

    testWidgets('task-list checkboxes render a glyph instead of vanishing',
        (tester) async {
      await pumpPreview(tester, '- [ ] todo\n- [x] done');
      expect(find.textContaining('todo'), findsWidgets);
      expect(spanWith(tester, '☐').text, contains('☐'));
      expect(spanWith(tester, '☑').text, contains('☑'));
    });

    testWidgets('an ordered list honors its start number', (tester) async {
      await pumpPreview(tester, '5. five\n6. six');
      expect(find.text('5.'), findsOneWidget);
      expect(find.text('6.'), findsOneWidget);
    });

    testWidgets('a thematic break nested in a list item is not dropped', (tester) async {
      await pumpPreview(tester, '- item\n\n  ---');
      expect(find.textContaining('item'), findsWidgets);
      expect(find.byType(Divider), findsWidgets);
    });
  });

  group('inline details (Review coverage)', () {
    testWidgets('inline code renders in monospace', (tester) async {
      await pumpPreview(tester, 'call `render()` now');
      expect(spanWith(tester, 'render()').style?.fontFamily, 'monospace');
    });

    testWidgets('a hard line break keeps both lines and does not throw', (tester) async {
      await pumpPreview(tester, 'line1  \nline2');
      expect(find.textContaining('line1'), findsWidgets);
      expect(find.textContaining('line2'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
