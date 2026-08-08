import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/editor_page.dart';
import 'package:lore_and_story/app/editor_toolbar.dart';
import 'package:lore_and_story/app/markdown_preview.dart';
import 'package:lore_and_story/lore/lore.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';
import 'editor_test_helpers.dart';
import 'test_image_fixtures.dart';

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
      home: EditorPage(
          storage: storage, path: path, loreDir: '', aiClient: FakeAiClient()),
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
              builder: (_) => EditorPage(
                  storage: storage,
                  path: 'a.md',
                  loreDir: '',
                  aiClient: FakeAiClient()),
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

    testWidgets(
        'a local image referenced by the open file renders in the preview '
        '(Story 2.16 — proves storage/filePath actually reach MarkdownPreview)',
        (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {
          'characters/selena/selena.md': '# Selena\n\n![portrait](media/portrait.png)',
        },
        fileBytes: {'characters/selena/media/portrait.png': validPngFixture},
      );
      await pumpEditor(tester, storage, 'characters/selena/selena.md', edit: false);
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownPreview), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
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

  group('active state and toggle-off (Story 2.14)', () {
    testWidgets('Bold shows active inside a bold span, and tapping toggles it off',
        (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': '**bold** word'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
      controller.selection = const TextSelection.collapsed(offset: 4); // inside "bold"
      await tester.pump();

      final boldBtn =
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.format_bold));
      expect(boldBtn.style?.backgroundColor?.resolve({}), isNotNull);

      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pump();

      expect(find.widgetWithText(TextField, 'bold word'), findsOneWidget);
      final boldBtnAfter =
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.format_bold));
      expect(boldBtnAfter.style?.backgroundColor?.resolve({}), isNull);
    });

    testWidgets('H2 shows active on a heading line, and tapping strips the prefix',
        (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': '## Title'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
      controller.selection = const TextSelection.collapsed(offset: 5); // inside "Title"
      await tester.pump();

      final h2Btn = tester.widget<TextButton>(
        find.ancestor(of: find.text('H2'), matching: find.byType(TextButton)),
      );
      expect(h2Btn.style?.backgroundColor?.resolve({}), isNotNull);

      await tester.tap(find.text('H2'));
      await tester.pump();

      expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    });

    testWidgets(
        'Bullet list shows active on a bulleted line, and tapping removes the marker',
        (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': '- item'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
      controller.selection = const TextSelection.collapsed(offset: 4); // inside "item"
      await tester.pump();

      final bulletBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.format_list_bulleted),
      );
      expect(bulletBtn.style?.backgroundColor?.resolve({}), isNotNull);

      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pump();

      expect(find.widgetWithText(TextField, 'item'), findsOneWidget);
    });

    testWidgets(
        'Bold with the caret outside any bold span is inactive and still inserts '
        '(regression guard)', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'word'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      final boldBtn =
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.format_bold));
      expect(boldBtn.style?.backgroundColor?.resolve({}), isNull);

      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pump();

      expect(find.widgetWithText(TextField, 'word****'), findsOneWidget);
    });
  });

  group('unified scene-link and expanded tokens (Story 2.15)', () {
    testWidgets('Dialogue line inserts the full template as a line prefix', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': ''});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pump();

      expect(find.widgetWithText(TextField, 'Name (emotion): '), findsOneWidget);
    });

    testWidgets('Dialogue line with a multi-line selection prefixes only one '
        'line, not every touched line (review fix)', (tester) async {
      final storage =
          FakeRepoStorage('/repo', fileContents: {'a.md': 'first\nsecond\nthird'});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
      // Select across all three lines.
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 18);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pump();

      expect(
        find.widgetWithText(
            TextField, 'Name (emotion): first\nsecond\nthird'),
        findsOneWidget,
      );
    });

    testWidgets('Passage link inserts the bracket template', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': ''});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.call_made));
      await tester.pump();

      expect(find.widgetWithText(TextField, '[[Choice->Passage Name]]'), findsOneWidget);
    });

    testWidgets('Return link inserts the bracket template', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': ''});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard_return));
      await tester.pump();

      expect(find.widgetWithText(TextField, '[[back<-Label]]'), findsOneWidget);
    });

    testWidgets('External link inserts the markdown template', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': ''});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.link));
      await tester.pump();

      expect(find.widgetWithText(TextField, '[label](url)'), findsOneWidget);
    });

    testWidgets('a passage-link insert round-trips through matchConventions as '
        'sceneLink, not left as generic bold+italic', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': ''});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.call_made));
      await tester.pump();

      final buffer =
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      final kinds = matchConventions(buffer).map((t) => t.kind).toSet();
      expect(kinds, contains(ConventionKind.sceneLink));
    });

    testWidgets('a dialogue-line insert round-trips through matchConventions as '
        'dialogueSpeaker (no matcher change needed for this button)', (tester) async {
      final storage = FakeRepoStorage('/repo', fileContents: {'a.md': ''});
      await pumpEditor(tester, storage, 'a.md');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pump();

      final buffer =
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      final kinds = matchConventions(buffer).map((t) => t.kind).toSet();
      expect(kinds, contains(ConventionKind.dialogueSpeaker));
    });
  });

  group('Lint action (Story 3.1)', () {
    testWidgets('shows findings for both a syntax error and a dangling '
        'wikilink, and tapping one exits preview and jumps the editor',
        (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        dirEntries: {
          '': const [
            RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
            RepoEntry(name: 'scene.md', path: 'scene.md', isDirectory: false),
          ],
          'characters': const [
            RepoEntry(
                name: 'selena.md',
                path: 'characters/selena.md',
                isDirectory: false),
          ],
        },
        fileContents: {
          'characters/selena.md': '# Selena\n',
          'scene.md': 'intro line\n<<if \$x>>\ntext [[Nobody]] here\n',
        },
      );
      // Start in preview (Story 2.7 default) so a jump demonstrably exits it.
      await pumpEditor(tester, storage, 'scene.md', edit: false);

      await tester.tap(find.byKey(const Key('lint-action')));
      // The `_linting` spinner now clears before the panel opens (`onLoaded`
      // fires pre-open — see runLintAndShowPanel's doc comment), so a plain
      // pumpAndSettle no longer risks hanging on an indeterminate animation;
      // it also settles the sheet's entrance transition, which a bare
      // tree-presence check would not — a row can exist in the tree mid-
      // slide-up and still be positioned off the visible viewport.
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lint-finding-0')), findsOneWidget);
      expect(find.byKey(const Key('lint-finding-1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('lint-finding-1')),
          matching: find.textContaining('Nobody'),
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing,
          reason: 'still in preview until a finding is tapped');

      await tester.tap(find.byKey(const Key('lint-finding-1')));
      await tester.pumpAndSettle();

      // Panel dismissed and the editor jumped out of preview.
      expect(find.byKey(const Key('lint-finding-0')), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a clean file shows "No issues found"', (tester) async {
      final storage =
          FakeRepoStorage('/repo', fileContents: {'a.md': 'Just prose.'});
      await pumpEditor(tester, storage, 'a.md', edit: false);

      await tester.tap(find.byKey(const Key('lint-action')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lint-no-issues')), findsOneWidget);
    });

    testWidgets('wikilinks to a section overview and a sub-entry are not '
        'reported dangling (AC4 — ARCHITECTURE.md: wikilinks reference '
        '"cards/overviews", not just top-level entity cards)', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        dirEntries: {
          '': const [
            RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
            RepoEntry(name: 'scene.md', path: 'scene.md', isDirectory: false),
          ],
          'characters': const [
            RepoEntry(name: 'selena', path: 'characters/selena', isDirectory: true),
          ],
          'characters/selena': const [
            RepoEntry(
                name: 'selena.md',
                path: 'characters/selena/selena.md',
                isDirectory: false),
            RepoEntry(
                name: 'events',
                path: 'characters/selena/events',
                isDirectory: true),
          ],
          'characters/selena/events': const [
            RepoEntry(
                name: 'events.md',
                path: 'characters/selena/events/events.md',
                isDirectory: false),
            RepoEntry(
                name: 'meeting.ru.md',
                path: 'characters/selena/events/meeting.ru.md',
                isDirectory: false),
          ],
        },
        fileContents: {
          'characters/selena/selena.md': '# Selena\n',
          'characters/selena/events/events.md': '# Events\n',
          'characters/selena/events/meeting.ru.md': '# Meeting\n',
          'scene.md': 'See [[Events]] and [[Meeting]].',
        },
      );
      await pumpEditor(tester, storage, 'scene.md', edit: false);

      await tester.tap(find.byKey(const Key('lint-action')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lint-no-issues')), findsOneWidget,
          reason: 'both [[Events]] (a section overview) and [[Meeting]] (a '
              'sub-entry) are legitimate wikilink targets, not dangling');
    });

    testWidgets('a loadLore failure degrades to syntax-only findings, never '
        'blocks the panel (AC4/AC7, AD-8)', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'a.md': '<<if \$x>> and [[Anything]]'},
        throwOnListDir: true,
      );
      await pumpEditor(tester, storage, 'a.md', edit: false);

      await tester.tap(find.byKey(const Key('lint-action')));
      await tester.pumpAndSettle();

      // The syntax error still shows...
      expect(find.byKey(const Key('lint-finding-0')), findsOneWidget);
      // ...but the wikilink is never reported dangling — the entity list
      // couldn't load, so that check was skipped entirely, not run against
      // an empty (falsely "nothing exists") set.
      expect(find.byKey(const Key('lint-finding-1')), findsNothing);
    });

    testWidgets('a loadLore failure on an otherwise-clean file says so, '
        'instead of an unqualified "No issues found" (AC7)', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'a.md': 'See [[Anything]].'},
        throwOnListDir: true,
      );
      await pumpEditor(tester, storage, 'a.md', edit: false);

      await tester.tap(find.byKey(const Key('lint-action')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lint-no-issues')), findsOneWidget);
      expect(find.textContaining('could not be loaded'), findsOneWidget);
    });
  });
}
