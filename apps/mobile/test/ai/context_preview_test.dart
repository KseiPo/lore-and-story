import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';

/// Pumps a minimal host with a button that opens the preview and records the
/// resolved value, so tests can drive the sheet via real widget interactions
/// (tap Confirm/Cancel, tap the barrier, trigger a back navigation) rather
/// than calling `showContextPreview` directly and never rendering anything.
Future<void> _pumpHost(WidgetTester tester, List<ContextSection> sections,
    {required ValueChanged<bool> onResult}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          child: const Text('open'),
          onPressed: () async {
            final result = await showContextPreview(context, sections: sections);
            onResult(result);
          },
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('renders each section\'s exact label and full, untruncated '
      'text (AC2)', (tester) async {
    final longText = 'x' * 5000;
    await _pumpHost(tester, [
      const ContextSection(label: 'Section A', text: 'short text'),
      ContextSection(label: 'Section B', text: longText),
    ], onResult: (_) {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Section A'), findsOneWidget);
    expect(find.text('short text'), findsOneWidget);
    expect(find.text('Section B'), findsOneWidget);

    // find.text only proves the string reached a widget's data property, not
    // that it renders unclipped — check the actual SelectableText directly:
    // full data intact, and no maxLines/overflow that would truncate it.
    final selectableText = tester.widget<SelectableText>(find.descendant(
      of: find.byKey(const Key('context-preview-section-1')),
      matching: find.byType(SelectableText),
    ));
    expect(selectableText.data, longText);
    expect(selectableText.data!.length, 5000);
    expect(selectableText.maxLines, isNull);
  });

  testWidgets('(FR22 traceability) the literal three named sections FR22 '
      'describes — the file, glossary terms, conventions — render correctly '
      'through the generic component', (tester) async {
    await _pumpHost(tester, const [
      ContextSection(label: 'The file', text: '# Selena\n\nShe walked in.'),
      ContextSection(label: 'Glossary terms', text: 'Selena, Selena Ivanova'),
      ContextSection(label: 'Conventions', text: 'Dialogue: Name (emotion): text'),
    ], onResult: (_) {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('The file'), findsOneWidget);
    expect(find.text('# Selena\n\nShe walked in.'), findsOneWidget);
    expect(find.text('Glossary terms'), findsOneWidget);
    expect(find.text('Selena, Selena Ivanova'), findsOneWidget);
    expect(find.text('Conventions'), findsOneWidget);
    expect(find.text('Dialogue: Name (emotion): text'), findsOneWidget);
  });

  testWidgets('tapping Confirm resolves true (AC3)', (tester) async {
    bool? result;
    await _pumpHost(tester, const [ContextSection(label: 'L', text: 'T')],
        onResult: (v) => result = v);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('context-preview-confirm')));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byKey(const Key('context-preview-confirm')), findsNothing);
  });

  testWidgets('tapping Cancel resolves false (AC4)', (tester) async {
    bool? result;
    await _pumpHost(tester, const [ContextSection(label: 'L', text: 'T')],
        onResult: (v) => result = v);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('context-preview-cancel')));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('(review fix — verify empirically, not assumed) the system '
      'back gesture resolves false, not null and not left unresolved (AC4)',
      (tester) async {
    bool? result;
    await _pumpHost(tester, const [ContextSection(label: 'L', text: 'T')],
        onResult: (v) => result = v);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Simulates the Android hardware/gesture back navigation.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('(review fix — verify empirically, not assumed) tapping '
      'outside the sheet (barrier dismiss) resolves false (AC4)', (tester) async {
    bool? result;
    await _pumpHost(tester, const [ContextSection(label: 'L', text: 'T')],
        onResult: (v) => result = v);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Target the barrier widget directly rather than a raw coordinate — a
    // coordinate guess only works by luck of a short payload leaving most of
    // the screen uncovered by the sheet.
    await tester.tap(find.byType(ModalBarrier).first);
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('an empty sections list renders the empty state without '
      'crashing (AC5)', (tester) async {
    bool? result;
    await _pumpHost(tester, const [], onResult: (v) => result = v);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('context-preview-empty')), findsOneWidget);
    expect(find.text('Nothing to preview.'), findsOneWidget);

    // (review fix) Confirming an empty preview must never resolve true —
    // there is nothing to consent to sending.
    final confirmButton = tester.widget<FilledButton>(
        find.byKey(const Key('context-preview-confirm')));
    expect(confirmButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('context-preview-cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('multiple sections render in the given order (AC1/AC6)',
      (tester) async {
    await _pumpHost(tester, const [
      ContextSection(label: 'First', text: 'one'),
      ContextSection(label: 'Second', text: 'two'),
      ContextSection(label: 'Third', text: 'three'),
    ], onResult: (_) {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final labelFinder = find.byWidgetPredicate((w) =>
        w is Text && (w.data == 'First' || w.data == 'Second' || w.data == 'Third'));
    final labels = tester
        .widgetList<Text>(labelFinder)
        .map((w) => w.data)
        .toList();
    expect(labels, ['First', 'Second', 'Third']);

    expect(find.byKey(const Key('context-preview-section-0')), findsOneWidget);
    expect(find.byKey(const Key('context-preview-section-1')), findsOneWidget);
    expect(find.byKey(const Key('context-preview-section-2')), findsOneWidget);
  });

  testWidgets('a section with empty text still renders its label — never '
      'silently dropped (AC5)', (tester) async {
    await _pumpHost(tester, const [
      ContextSection(label: 'Has content', text: 'hello'),
      ContextSection(label: 'Empty section', text: ''),
    ], onResult: (_) {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Has content'), findsOneWidget);
    expect(find.text('Empty section'), findsOneWidget);
    expect(find.byKey(const Key('context-preview-section-0')), findsOneWidget);
    expect(find.byKey(const Key('context-preview-section-1')), findsOneWidget);
  });
}
