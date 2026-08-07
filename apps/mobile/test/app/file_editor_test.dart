import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/file_editor.dart';

import '../fakes.dart';

void main() {
  group('FileEditor — text and jumpToLine (Story 3.1)', () {
    testWidgets('text exposes the live buffer, including unsaved edits',
        (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md')),
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
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md')),
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
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md')),
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
        home: Scaffold(body: FileEditor(storage: storage, path: 'a.md')),
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
}
