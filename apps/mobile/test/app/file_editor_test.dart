import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/file_editor.dart';
import 'package:lore_and_story/lore/lore.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';
import 'markdown_span_test_helpers.dart';

FakeRepoStorage _storageWithSelena({String editedFile = 'a.md', String initial = ''}) {
  return FakeRepoStorage(
    '/repo',
    dirEntries: {
      '': [
        RepoEntry(name: 'selena.md', path: 'selena.md', isDirectory: false),
        if (editedFile != 'selena.md')
          RepoEntry(name: editedFile, path: editedFile, isDirectory: false),
      ],
    },
    fileContents: {
      'selena.md': '# Selena\naliases: Sel\n',
      editedFile: initial,
    },
  );
}

Future<void> _waitForEntitiesToLoad(WidgetTester tester) async {
  // FakeRepoStorage resolves near-instantly but still through a real
  // microtask chain (loadLore walks the fixture directory) — a handful of
  // pumps flushes it without relying on a fragile fixed count.
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
}

void main() {
  group('FileEditor — text and jumpToLine (Story 3.1)', () {
    testWidgets('text exposes the live buffer, including unsaved edits',
        (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      expect(state.text, 'hello');
      // No host chrome (AppBar preview toggle) is rendered for a bare
      // FileEditor in this test, so exit preview directly via the state
      // rather than the usual enterEditMode helper.
      state.togglePreview();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();
      expect(state.text, 'hello world');
    });

    testWidgets('jumpToLine exits preview and moves the caret to the start '
        'of the given line', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'a.md': 'line one\nline two\nline three'},
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      expect(state.previewing, isTrue, reason: 'preview-first default (Story 2.7)');

      state.jumpToLine(2);
      await tester.pump();

      expect(state.previewing, isFalse);
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      // "line one\n" is 9 characters — line 2 starts at offset 9.
      expect(controller.selection.baseOffset, 9);
      expect(controller.selection.isCollapsed, isTrue);
      // (Review fix) A bare selection change on an unfocused field is
      // invisible on screen — the fix requests focus so Flutter actually
      // scrolls the jump into view.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue,
          reason: 'jumpToLine must request focus, or nothing visibly moves '
              'for an off-screen line');
    });

    testWidgets('jumpToLine to the first line lands at offset 0', (tester) async {
      final storage =
          FakeRepoStorage('/repo', fileContents: {'a.md': 'only line'});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      state.jumpToLine(1);
      await tester.pump();

      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(controller.selection.baseOffset, 0);
    });

    testWidgets('jumpToLine past the last line clamps to the end of the '
        'buffer instead of throwing', (tester) async {
      final storage =
          FakeRepoStorage('/repo', fileContents: {'a.md': 'one\ntwo'});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      expect(() => state.jumpToLine(99), returnsNormally);
      await tester.pump();

      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(controller.selection.baseOffset, 7); // clamped to text length
    });
  });

  group('FileEditor — [[ autocomplete (Story 3.2)', () {
    testWidgets('typing [[Se shows a suggestion row containing Selena',
        (tester) async {
      final storage = _storageWithSelena();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();
      await _waitForEntitiesToLoad(tester);

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      state.togglePreview();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'See [[Se');
      await tester.pump();

      // (Review fix) Keyed by entry id, not title — two entities can share a
      // title, so the key can't be title-only.
      expect(find.byKey(const Key('wikilink-suggestion-selena.md')), findsOneWidget);
    });

    testWidgets('tapping a suggestion completes [[Se to [[Selena]] and '
        'marks the buffer dirty', (tester) async {
      final storage = _storageWithSelena();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();
      await _waitForEntitiesToLoad(tester);

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      state.togglePreview();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'See [[Se');
      await tester.pump();
      await tester.tap(find.byKey(const Key('wikilink-suggestion-selena.md')));
      await tester.pump();

      expect(state.text, 'See [[Selena]]');
      expect(state.isDirty, isTrue);
      expect(find.byKey(const Key('wikilink-suggestion-selena.md')), findsNothing,
          reason: 'the row closes once the query is completed');
    });

    testWidgets('closing the brackets or moving the caret away hides the row',
        (tester) async {
      final storage = _storageWithSelena();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();
      await _waitForEntitiesToLoad(tester);

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      state.togglePreview();
      await tester.pump();

      await tester.enterText(find.byType(TextField), '[[Se');
      await tester.pump();
      expect(find.byKey(const Key('wikilink-suggestion-selena.md')), findsOneWidget);

      await tester.enterText(find.byType(TextField), '[[Se]]');
      await tester.pump();
      expect(find.byKey(const Key('wikilink-suggestion-selena.md')), findsNothing);
    });

    testWidgets('no suggestions render when the entity list has not '
        'resolved yet or matches nothing — never a crash', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': ''});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      state.togglePreview();
      await tester.pump();

      await tester.enterText(find.byType(TextField), '[[Anything');
      await tester.pump();
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('the text field keeps focus (and the keyboard would stay '
        'up) after tapping a suggestion — verified, not assumed', (tester) async {
      final storage = _storageWithSelena();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();
      await _waitForEntitiesToLoad(tester);

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      state.togglePreview();
      await tester.pump();

      await tester.enterText(find.byType(TextField), '[[Se');
      await tester.pump();
      await tester.tap(find.byKey(const Key('wikilink-suggestion-selena.md')));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus ?? false, isTrue,
          reason: 'a chip tap must not steal focus from the editor field');
    });

    testWidgets('(review fix) reloadEntries picks up a title change made '
        'externally to the storage, instead of staying stale for this '
        'instance\'s lifetime', (tester) async {
      final storage = _storageWithSelena();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md', loreDir: '')),
      ));
      await tester.pumpAndSettle();
      await _waitForEntitiesToLoad(tester);

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      state.togglePreview();
      await tester.pump();

      // Simulate a title change made by another screen (e.g. reached via a
      // wikilink hop) while this FileEditor instance is still open.
      await storage.writeAtomic('selena.md', '# Селена\naliases: Selena\n');
      state.reloadEntries();
      await _waitForEntitiesToLoad(tester);

      await tester.enterText(find.byType(TextField), '[[Сел');
      await tester.pump();

      expect(find.byKey(const Key('wikilink-suggestion-selena.md')), findsOneWidget);
      expect(find.text('Селена'), findsOneWidget);
    });
  });

  group('FileEditor — wikilink tap-navigation (Story 3.2)', () {
    testWidgets('tapping a resolved [[wikilink]] in the preview calls '
        'onNavigateToEntity with the matching entry', (tester) async {
      final storage = _storageWithSelena(initial: 'See [[Selena]] here.');
      LoreEntry? navigated;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileEditor(
            storage: storage,
            path: 'a.md',
            loreDir: '',
            onNavigateToEntity: (entry) => navigated = entry,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await _waitForEntitiesToLoad(tester);

      final state = tester.state<FileEditorState>(find.byType(FileEditor));
      expect(state.previewing, isTrue, reason: 'preview-first default (Story 2.7)');

      final span = spanWith(tester, '[[Selena]]');
      final recognizer = span.recognizer;
      expect(recognizer, isA<TapGestureRecognizer>());
      (recognizer as TapGestureRecognizer).onTap!();

      expect(navigated?.title, 'Selena');
    });

    testWidgets('tapping a wikilink whose title matches no known entity '
        'never crashes and never calls onNavigateToEntity', (tester) async {
      final storage = _storageWithSelena(initial: 'See [[Nobody]] here.');
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileEditor(
            storage: storage,
            path: 'a.md',
            loreDir: '',
            onNavigateToEntity: (_) => calls++,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await _waitForEntitiesToLoad(tester);

      final span = spanWith(tester, '[[Nobody]]');
      final recognizer = span.recognizer;
      expect(recognizer, isA<TapGestureRecognizer>());
      (recognizer as TapGestureRecognizer).onTap!();

      expect(tester.takeException(), isNull);
      expect(calls, 0);
    });
  });
}
