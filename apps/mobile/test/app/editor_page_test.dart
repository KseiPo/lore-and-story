import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/editor_page.dart';
import 'package:lore_and_story/app/editor_toolbar.dart';
import 'package:lore_and_story/app/markdown_preview.dart';

import '../fakes.dart';
import 'editor_test_helpers.dart';

/// Pumps the editor and settles. The editor now opens in read-only preview
/// (Story 2.7); since most editor tests exercise editing, this flips into edit
/// mode by default. Pass `edit: false` to observe the default preview surface.
Future<void> pumpEditor(
  WidgetTester tester,
  FakeRepoStorage storage,
  String path, {
  bool edit = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: EditorPage(storage: storage, path: path),
    ),
  );
  await tester.pumpAndSettle();
  if (edit) await enterEditMode(tester);
}

void main() {
  testWidgets('loads raw content into the field untransformed (FR7)', (
    tester,
  ) async {
    final storage = FakeRepoStorage(
      '/repo',
      fileContents: {'scene.ru.md': '# Title\n\n**bold** [[Selena]]\n'},
    );
    await pumpEditor(tester, storage, 'scene.ru.md');
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextField, '# Title\n\n**bold** [[Selena]]\n'),
      findsOneWidget,
    );
  });

  testWidgets('shows a dirty indicator after an edit, none before', (
    tester,
  ) async {
    final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
    await pumpEditor(tester, storage, 'a.md');
    await tester.pumpAndSettle();

    expect(find.byKey(kDirtyIndicatorKey), findsNothing);

    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.pump();

    expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
  });

  testWidgets(
    'typing alone never calls writeAtomic (no autosave-per-keystroke)',
    (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(storage.writeCalls, isEmpty);
    },
  );

  testWidgets(
    'tapping save writes the edited text and clears the dirty indicator',
    (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();
      expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);

      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, [('a.md', 'hello world')]);
      expect(find.byKey(kDirtyIndicatorKey), findsNothing);
    },
  );

  testWidgets('backgrounding while dirty saves (save-on-background, FR11)', (
    tester,
  ) async {
    final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
    await pumpEditor(tester, storage, 'a.md');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(storage.writeCalls, [('a.md', 'hello world')]);
  });

  testWidgets('backgrounding while NOT dirty never calls writeAtomic', (
    tester,
  ) async {
    final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
    await pumpEditor(tester, storage, 'a.md');
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(storage.writeCalls, isEmpty);
  });

  testWidgets('a read failure shows an error state instead of crashing', (
    tester,
  ) async {
    final storage = FakeRepoStorage('/repo'); // no content seeded → read throws
    await pumpEditor(tester, storage, 'ghost.md');
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open this file'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'the dirty indicator reappears on the next edit after a save (AC3)',
    (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'first');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();
      expect(find.byKey(kDirtyIndicatorKey), findsNothing);

      await tester.enterText(find.byType(TextField), 'second');
      await tester.pump();

      expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
    },
  );

  group('malformed (lossily-decoded) file', () {
    // read() decodes invalid UTF-8 best-effort to U+FFFD; writing that buffer
    // back would destroy the original bytes.
    const lossy = 'caf\u{FFFD} content';

    testWidgets('warns and never writes, even when edited', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'bad.md': lossy});
      await pumpEditor(tester, storage, 'bad.md');
      await tester.pumpAndSettle();

      expect(find.textContaining('not valid UTF-8'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'edited');
      await tester.pump();

      // Save action is disabled...
      final saveButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.save_outlined),
          matching: find.byType(IconButton),
        ),
      );
      expect(saveButton.onPressed, isNull);

      // ...and backgrounding must not sneak a corrupting write through either.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(storage.writeCalls, isEmpty);
    });
  });

  testWidgets(
    'a save failure surfaces a snackbar and leaves the buffer dirty',
    (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'a.md': 'hello'},
        failWrites: true,
      );
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();

      expect(find.textContaining('Save failed'), findsOneWidget);
      expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
    },
  );

  testWidgets(
    'a file full of suspect markup opens, edits, and saves (FR9a/AD-8)',
    (tester) async {
      // Leaked twee + a scene passage-link — flagged, never fatal.
      const suspect = 'Frank: hi <<if \$x>>\n[[label->passage]] <b>bold</b>\n';
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'bad.md': suspect},
      );
      await pumpEditor(tester, storage, 'bad.md');
      await tester.pumpAndSettle();

      // Opens without throwing, raw content intact.
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextField, suspect), findsOneWidget);

      // Editable and saveable — suspect markup does not disable saving.
      await tester.enterText(find.byType(TextField), '$suspect edited');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, [('bad.md', '$suspect edited')]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backing out with a failed save keeps the screen — never discards (AD-10)',
      (tester) async {
    final storage = FakeRepoStorage(
      '/repo',
      fileContents: {'a.md': 'hello'},
      failWrites: true,
    );
    // Push the editor so there is a back button to pop.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => EditorPage(storage: storage, path: 'a.md'),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await enterEditMode(tester);
    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    // The save failed, so the editor stays open with the edit — not popped away.
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.textContaining('Save failed'), findsOneWidget);
    expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
  });

  group('preview toggle (FR10)', () {
    testWidgets('toggles between the editor and a read-only rendered preview', (
      tester,
    ) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'a.md': '# Title\n\n**bold**'},
      );
      await pumpEditor(tester, storage, 'a.md', edit: false);

      // preview by default.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditorToolbar), findsNothing);
      expect(find.byType(MarkdownPreview), findsOneWidget);

      // Toggle to edit.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownPreview), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(EditorToolbar), findsOneWidget);

      // Toggle back to preview.
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(MarkdownPreview), findsOneWidget);
    });

    testWidgets('previewing does not change the buffer (stays dirty)', (
      tester,
    ) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
      await pumpEditor(tester, storage, 'a.md', edit: false);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello edited');
      await tester.pump();
      expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
      // The edited text is what the preview renders...
      expect(find.byType(MarkdownPreview), findsOneWidget);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      // ...and returning to the editor keeps the exact edited buffer, still dirty.
      expect(find.widgetWithText(TextField, 'hello edited'), findsOneWidget);
      expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
    });

    testWidgets('Save still works from preview mode', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
      await pumpEditor(tester, storage, 'a.md', edit: false);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();
      expect(storage.writeCalls, [('a.md', 'hello world')]);
    });

    testWidgets('a lossy file can be previewed and Save stays disabled', (
      tester,
    ) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'bad.md': 'caf\u{FFFD} content'},
      );
      // A lossy file opens straight into preview (the default surface).
      await pumpEditor(tester, storage, 'bad.md', edit: false);
      expect(find.byType(MarkdownPreview), findsOneWidget);

      final saveButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.save_outlined),
          matching: find.byType(IconButton),
        ),
      );
      expect(saveButton.onPressed, isNull);
    });
  });

  group('helper toolbar (FR8)', () {
    testWidgets('is shown in the ready state', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'word'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();
      expect(find.byType(EditorToolbar), findsOneWidget);
    });

    testWidgets(
      'bold wraps at the cursor, keeps the buffer raw, and marks dirty',
      (tester) async {
        final storage = FakeRepoStorage(
          '/repo',
          fileContents: {'a.md': 'word'},
        );
        await pumpEditor(tester, storage, 'a.md');
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.format_bold));
        await tester.pump();

        // The toolbar mutated the raw buffer (controller.text) — no WYSIWYG. The
        // display invariant (span text == buffer) is proven separately in
        // convention_highlighting_controller_test.dart.
        expect(find.widgetWithText(TextField, 'word****'), findsOneWidget);
        expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
      },
    );

    testWidgets('H2 prefixes the current line', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'word'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.tap(find.text('H2'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '## word'), findsOneWidget);
    });

    testWidgets('[[ inserts the wikilink pair with the cursor between', (
      tester,
    ) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'word'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.tap(find.text('[['));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'word[[]]'), findsOneWidget);
    });

    testWidgets('a toolbar edit is saved by the existing save action', (
      tester,
    ) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'word'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.tap(find.text('H2'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, [('a.md', '## word')]);
    });
  });
}
