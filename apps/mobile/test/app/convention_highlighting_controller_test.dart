import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/convention_highlighting_controller.dart';

/// Builds the span the [TextField] would render, in a real BuildContext.
Future<TextSpan> spanFor(WidgetTester tester, String text) async {
  final controller = ConventionHighlightingController(text: text);
  late TextSpan span;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      span = controller.buildTextSpan(
          context: context, style: const TextStyle(), withComposing: false);
      return const SizedBox();
    }),
  ));
  return span;
}

void main() {
  testWidgets('the styled spans concatenate to the exact buffer (nothing lost/hidden)',
      (tester) async {
    const text = '# Title\n\n**bold** [[link]] [x] Frank: hi — end';
    final span = await spanFor(tester, text);
    // The buffer stays raw: the display text equals the input byte-for-byte.
    expect(span.toPlainText(), text);
  });

  testWidgets('highlighting actually splits the text into multiple styled spans',
      (tester) async {
    // A non-heading line (headings subsume inline tokens by design): bold + gap
    // + italic → several children.
    final span = await spanFor(tester, '**bold** and _italic_');
    expect((span.children ?? const <InlineSpan>[]).length, greaterThan(1));
  });

  testWidgets('a heading child is styled bold', (tester) async {
    final span = await spanFor(tester, '# Heading');
    final child = (span.children ?? const <InlineSpan>[]).whereType<TextSpan>().firstWhere(
          (s) => s.toPlainText().contains('Heading'),
          orElse: () => const TextSpan(),
        );
    expect(child.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('degrades to plain text without throwing on pathological input',
      (tester) async {
    final text = '[' * 3000;
    late TextSpan span;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        final c = ConventionHighlightingController(text: text);
        span = c.buildTextSpan(
            context: context, style: const TextStyle(), withComposing: false);
        return const SizedBox();
      }),
    ));
    expect(tester.takeException(), isNull);
    expect(span.toPlainText(), text);
  });

  testWidgets('empty buffer yields an empty plain span', (tester) async {
    final span = await spanFor(tester, '');
    expect(span.toPlainText(), '');
  });

  /// The [TextSpan] child whose text contains [needle], if any.
  TextSpan? childContaining(TextSpan span, String needle) {
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan && (child.toPlainText()).contains(needle)) {
        return child;
      }
    }
    return null;
  }

  testWidgets('suspect markup gets a distinct wavy error decoration (FR9a)',
      (tester) async {
    // Leaked twee, leaked HTML, and a scene passage-link on one line.
    const text = 'ok <<if \$x>> and <b> and [[a->passage]]';
    final span = await spanFor(tester, text);

    // The buffer stays raw — nothing hidden or dropped.
    expect(span.toPlainText(), text);

    for (final suspect in ['<<if \$x>>', '<b>', '[[a->passage]]']) {
      final child = childContaining(span, suspect);
      expect(child, isNotNull, reason: 'expected a span for "$suspect"');
      expect(child!.style?.decoration, TextDecoration.underline);
      expect(child.style?.decorationStyle, TextDecorationStyle.wavy,
          reason: 'error markup should read as a distinct squiggle');
    }
  });

  testWidgets('a valid wikilink is NOT given the error decoration', (tester) async {
    final span = await spanFor(tester, 'see [[Selena]] here');
    final child = childContaining(span, '[[Selena]]');
    expect(child, isNotNull);
    expect(child!.style?.decorationStyle, isNot(TextDecorationStyle.wavy));
  });

  testWidgets('a buffer full of suspect markup still renders plainly, no throw',
      (tester) async {
    final text = '${'<<x>>' * 500}\n${'[[a->b]]' * 500}';
    final span = await spanFor(tester, text);
    expect(tester.takeException(), isNull);
    expect(span.toPlainText(), text);
  });
}
