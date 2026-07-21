import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/editor_page.dart';

import '../fakes.dart';

Future<void> pumpEditor(WidgetTester tester, FakeRepoStorage storage, String path) {
  return tester.pumpWidget(MaterialApp(
    home: EditorPage(storage: storage, path: path),
  ));
}

void main() {
  testWidgets('loads raw content into the field untransformed (FR7)',
      (tester) async {
    final storage = FakeRepoStorage(
      '/repo',
      fileContents: {'scene.ru.md': '# Title\n\n**bold** [[Selena]]\n'},
    );
    await pumpEditor(tester, storage, 'scene.ru.md');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '# Title\n\n**bold** [[Selena]]\n'),
        findsOneWidget);
  });

  testWidgets('shows a dirty indicator after an edit, none before', (tester) async {
    final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
    await pumpEditor(tester, storage, 'a.md');
    await tester.pumpAndSettle();

    expect(find.byKey(kDirtyIndicatorKey), findsNothing);

    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.pump();

    expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
  });

  testWidgets('typing alone never calls writeAtomic (no autosave-per-keystroke)',
      (tester) async {
    final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
    await pumpEditor(tester, storage, 'a.md');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(storage.writeCalls, isEmpty);
  });

  testWidgets('tapping save writes the edited text and clears the dirty indicator',
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
  });

  testWidgets('backgrounding while dirty saves (save-on-background, FR11)',
      (tester) async {
    final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
    await pumpEditor(tester, storage, 'a.md');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(storage.writeCalls, [('a.md', 'hello world')]);
  });

  testWidgets('backgrounding while NOT dirty never calls writeAtomic',
      (tester) async {
    final storage = FakeRepoStorage('/repo', fileContents: {'a.md': 'hello'});
    await pumpEditor(tester, storage, 'a.md');
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(storage.writeCalls, isEmpty);
  });

  testWidgets('a read failure shows an error state instead of crashing',
      (tester) async {
    final storage = FakeRepoStorage('/repo'); // no content seeded → read throws
    await pumpEditor(tester, storage, 'ghost.md');
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open this file'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the dirty indicator reappears on the next edit after a save (AC3)',
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
  });

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

  testWidgets('a save failure surfaces a snackbar and leaves the buffer dirty',
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
  });
}
