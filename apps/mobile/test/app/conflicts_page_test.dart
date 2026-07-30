import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/conflicts_page.dart';
import 'package:lore_and_story/lore/lore.dart';

import '../fakes.dart';
import 'editor_test_helpers.dart';

void main() {
  const conflicts = [
    ConflictCopy(
      id: 'characters/selena.sync-conflict-20240612-093000-K3F9AAA.md',
      name: 'selena.sync-conflict-20240612-093000-K3F9AAA.md',
      relDir: 'characters',
    ),
    ConflictCopy(
      id: 'intro.sync-conflict-20240101-120000-ABC.md',
      name: 'intro.sync-conflict-20240101-120000-ABC.md',
      relDir: '.',
    ),
  ];

  FakeRepoStorage makeStorage() => FakeRepoStorage(
        '/storage/emulated/0/repo',
        fileContents: {
          'characters/selena.sync-conflict-20240612-093000-K3F9AAA.md':
              '# selena conflict\n',
          'intro.sync-conflict-20240101-120000-ABC.md': '# intro conflict\n',
        },
      );

  Future<void> pump(
    WidgetTester tester, {
    List<ConflictCopy> items = conflicts,
    FakeRepoStorage? storage,
    String loreDir = '',
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ConflictsPage(
        storage: storage ?? makeStorage(),
        conflicts: items,
        loreDir: loreDir,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists each conflict with a badge, name, and location (FR17)',
      (tester) async {
    await pump(tester);

    expect(find.text('CONFLICT'), findsNWidgets(2));
    expect(find.text('selena.sync-conflict-20240612-093000-K3F9AAA.md'), findsOneWidget);
    expect(find.text('intro.sync-conflict-20240101-120000-ABC.md'), findsOneWidget);
    // Locations: the subfolder, and `.` rendered as `root`.
    expect(find.text('characters'), findsOneWidget);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('tapping a conflict opens it in the editor, flagged as a conflict copy',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('intro.sync-conflict-20240101-120000-ABC.md'));
    await tester.pumpAndSettle();
    await enterEditMode(tester); // editor opens in preview (Story 2.7)

    expect(find.widgetWithText(TextField, '# intro conflict\n'), findsOneWidget);
    // The editor re-asserts that this is a conflict copy (the AppBar path
    // ellipsis would otherwise clip the `.sync-conflict-…` marker).
    expect(find.byKey(const Key('editor-conflict-banner')), findsOneWidget);
  });

  testWidgets('joins a non-empty loreDir onto the conflict id when opening',
      (tester) async {
    const c = ConflictCopy(
      id: 'characters/x.sync-conflict-20240101-120000-ABC.md',
      name: 'x.sync-conflict-20240101-120000-ABC.md',
      relDir: 'characters',
    );
    // Whole-repo sync: loreDir is a real subfolder, so the editor path is
    // `lore/` + the loreDir-relative id.
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      fileContents: {
        'lore/characters/x.sync-conflict-20240101-120000-ABC.md':
            '# subfolder conflict\n',
      },
    );
    await pump(tester, items: const [c], storage: storage, loreDir: 'lore');

    await tester.tap(find.text('x.sync-conflict-20240101-120000-ABC.md'));
    await tester.pumpAndSettle();
    await enterEditMode(tester); // editor opens in preview (Story 2.7)

    expect(find.widgetWithText(TextField, '# subfolder conflict\n'), findsOneWidget);
  });

  testWidgets('an empty list renders a friendly state without throwing',
      (tester) async {
    await pump(tester, items: const []);

    expect(find.text('No sync conflict copies.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
