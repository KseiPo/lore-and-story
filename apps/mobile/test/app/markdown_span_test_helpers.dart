import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every [TextSpan] in the pumped tree (flattened), for style assertions.
/// Shared by `markdown_preview_test.dart` and `entity_detail_page_test.dart`
/// so the two consumers of `MarkdownPreview` assert against it the same way.
Iterable<TextSpan> allSpans(WidgetTester tester) sync* {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    final root = rich.text;
    if (root is TextSpan) yield* _flatten(root);
  }
}

Iterable<TextSpan> _flatten(TextSpan s) sync* {
  yield s;
  for (final c in s.children ?? const <InlineSpan>[]) {
    if (c is TextSpan) yield* _flatten(c);
  }
}

/// The first span whose text contains [needle].
TextSpan spanWith(WidgetTester tester, String needle) => allSpans(tester)
    .firstWhere((s) => (s.text ?? '').contains(needle), orElse: () => const TextSpan());
