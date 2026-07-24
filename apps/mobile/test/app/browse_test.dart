import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/app.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';

/// A small lore repo whose root **is** the lore folder (the author syncs the
/// lore folder itself — there is no `lore/` level):
///
/// ```
/// <picked root>/
///   intro.md                     (general)
///   characters/
///     frank.md                   (simple entity, category 'characters')
///     selena/selena.md           (entity folder, category 'characters')
///   locations/
///     tavern.md                  (simple entity, category 'locations')
/// ```
///
/// [conflictInCharacters] optionally drops a Syncthing conflict copy inside
/// `characters/` (surfaced, never an entity).
FakeRepoStorage _repo({bool conflictInCharacters = false}) {
  final characters = <RepoEntry>[
    const RepoEntry(name: 'frank.md', path: 'characters/frank.md', isDirectory: false),
    const RepoEntry(name: 'selena', path: 'characters/selena', isDirectory: true),
    if (conflictInCharacters)
      const RepoEntry(
        name: 'frank.sync-conflict-20240612-093000-K3F9AAA.md',
        path: 'characters/frank.sync-conflict-20240612-093000-K3F9AAA.md',
        isDirectory: false,
      ),
  ];
  return FakeRepoStorage(
    '/storage/emulated/0/repo',
    dirEntries: {
      '': const [
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
        RepoEntry(name: 'intro.md', path: 'intro.md', isDirectory: false),
        RepoEntry(name: 'locations', path: 'locations', isDirectory: true),
      ],
      'characters': characters,
      'characters/selena': const [
        RepoEntry(
            name: 'selena.md', path: 'characters/selena/selena.md', isDirectory: false),
      ],
      'locations': const [
        RepoEntry(name: 'tavern.md', path: 'locations/tavern.md', isDirectory: false),
      ],
    },
    fileContents: {
      'intro.md': '# Intro\n',
      'characters/frank.md': '# Frank\n',
      'characters/selena/selena.md': '# Selena\n',
      'locations/tavern.md': '# Tavern\n',
    },
  );
}

Future<void> _pumpReady(WidgetTester tester, FakeRepoStorage storage) async {
  await tester.pumpWidget(LoreStoryApp(
    rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
    permission: FakeStoragePermission(granted: true),
    storageFactory: (root) => storage,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Categories screen lists top-level categories with entity counts (FR4)',
      (tester) async {
    await _pumpReady(tester, _repo());

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('characters'), findsOneWidget);
    expect(find.text('general'), findsOneWidget);
    expect(find.text('locations'), findsOneWidget);
    // characters holds frank.md + selena/ = 2.
    expect(find.text('2 entities'), findsOneWidget);
  });

  testWidgets(
      'tapping a category shows its entities; a simple file and an entity folder '
      'are the same kind of item (FR5)', (tester) async {
    await _pumpReady(tester, _repo());

    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();

    // Both the simple entity (frank.md) and the folder entity (selena/) appear.
    expect(find.text('Frank'), findsOneWidget);
    expect(find.text('Selena'), findsOneWidget);
    // Presented identically — same leading icon, one row each (FR5: one node
    // type). Two entity rows -> two identical icons.
    expect(find.byIcon(Icons.description_outlined), findsNWidgets(2));
  });

  testWidgets('tapping an entity opens its card in the editor (navigate to any card)',
      (tester) async {
    await _pumpReady(tester, _repo());

    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frank'));
    await tester.pumpAndSettle();

    // The editor opened on the entity's card (characters/frank.md).
    expect(find.widgetWithText(TextField, '# Frank\n'), findsOneWidget);
  });

  testWidgets('an entity in a nested sub-category is reachable under its top-level '
      'category (AC4)', (tester) async {
    // characters/secondary/deep.md — a card two levels deep.
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      dirEntries: {
        '': const [
          RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
        ],
        'characters': const [
          RepoEntry(name: 'secondary', path: 'characters/secondary', isDirectory: true),
        ],
        'characters/secondary': const [
          RepoEntry(
              name: 'deep.md', path: 'characters/secondary/deep.md', isDirectory: false),
        ],
      },
      fileContents: {'characters/secondary/deep.md': '# Deep One\n'},
    );
    await _pumpReady(tester, storage);

    // Folded under the top-level 'characters' category, not a separate group.
    expect(find.text('characters'), findsOneWidget);
    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();
    expect(find.text('Deep One'), findsOneWidget);

    // ...and it actually opens its card (not just listed) — the two-level
    // browse reaches a card two folders deep.
    await tester.tap(find.text('Deep One'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '# Deep One\n'), findsOneWidget);
  });

  testWidgets('a general root card opens its card (AC4 reachability)',
      (tester) async {
    await _pumpReady(tester, _repo());

    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intro'));
    await tester.pumpAndSettle();

    // intro.md sits directly in loreDir (category 'general'); its card opens.
    expect(find.widgetWithText(TextField, '# Intro\n'), findsOneWidget);
  });

  testWidgets(
      'editing an entity updates the entities list without leaving the category (AC3)',
      (tester) async {
    await _pumpReady(tester, _repo());

    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frank'));
    await tester.pumpAndSettle();

    // Rename the card's heading and save (the atomic writer updates the fake).
    await tester.enterText(find.byType(TextField), '# Franklin\n');
    await tester.pump();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    // Back to the still-open entities list — it re-walks and reflects the edit
    // rather than showing the stale tap-time snapshot.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Franklin'), findsOneWidget);
    expect(find.text('Frank'), findsNothing);
  });

  testWidgets('a conflict copy is banner-only and never appears in the entities list (FR17)',
      (tester) async {
    await _pumpReady(tester, _repo(conflictInCharacters: true));

    // Surfaced on the home banner.
    expect(find.byKey(const Key('conflict-banner')), findsOneWidget);

    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();

    // The real entities are listed; the conflict copy is not among them.
    expect(find.text('Frank'), findsOneWidget);
    expect(find.text('Selena'), findsOneWidget);
    expect(find.textContaining('sync-conflict'), findsNothing);
  });

  testWidgets(
      'a lore-story.json redirects loreDir to a subfolder (whole-repo sync); '
      'root-level non-lore files are not ingested (FR2)', (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      dirEntries: {
        '': const [
          RepoEntry(name: 'lore', path: 'lore', isDirectory: true),
          RepoEntry(name: 'README.md', path: 'README.md', isDirectory: false),
        ],
        'lore': const [
          RepoEntry(name: 'characters', path: 'lore/characters', isDirectory: true),
        ],
        'lore/characters': const [
          RepoEntry(name: 'frank.md', path: 'lore/characters/frank.md', isDirectory: false),
        ],
      },
      fileContents: {
        'lore-story.json': '{"loreDir":"lore"}',
        'lore/characters/frank.md': '# Frank\n',
        'README.md': '# Readme\n',
      },
    );
    await _pumpReady(tester, storage);

    // loreDir redirected into 'lore/': its category shows...
    expect(find.text('characters'), findsOneWidget);
    // ...and the root-level README is outside loreDir, so it is not a 'general'
    // entity.
    expect(find.text('general'), findsNothing);
  });

  testWidgets(
      'a configured loreDir that does not exist shows empty — never silently '
      'walks the repo root (FR2 safety)', (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      dirEntries: {
        '': const [
          RepoEntry(name: 'README.md', path: 'README.md', isDirectory: false),
        ],
      },
      fileContents: {
        // Points loreDir at a subfolder that isn't present (mid-sync / typo).
        'lore-story.json': '{"loreDir":"lore"}',
        'README.md': '# Readme\n',
      },
    );
    await _pumpReady(tester, storage);

    // The missing 'lore/' must NOT be substituted by the repo root — otherwise
    // README would load as an editable entity. Show the empty state instead.
    expect(find.textContaining('No lore entities found'), findsOneWidget);
    expect(find.text('general'), findsNothing);
  });

  testWidgets(
      'root-level syncer/VCS dirs and hidden files are skipped when the root is '
      'the lore folder (FR16 / all-dot rule)', (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      dirEntries: {
        '': const [
          RepoEntry(name: '.git', path: '.git', isDirectory: true),
          RepoEntry(name: '.stfolder', path: '.stfolder', isDirectory: true),
          RepoEntry(name: 'media', path: 'media', isDirectory: true),
          RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
          RepoEntry(name: '.hidden.md', path: '.hidden.md', isDirectory: false),
        ],
        '.git': const [
          RepoEntry(name: 'config.md', path: '.git/config.md', isDirectory: false),
        ],
        'characters': const [
          RepoEntry(name: 'frank.md', path: 'characters/frank.md', isDirectory: false),
        ],
      },
      fileContents: {
        '.git/config.md': '# not lore\n',
        'characters/frank.md': '# Frank\n',
        '.hidden.md': '# hidden\n',
      },
    );
    await _pumpReady(tester, storage);

    // Only the real category is surfaced.
    expect(find.text('characters'), findsOneWidget);
    expect(find.text('.git'), findsNothing);
    expect(find.text('.stfolder'), findsNothing);
    expect(find.text('media'), findsNothing);
    // The hidden root-level .md is not loaded as a 'general' entity.
    expect(find.text('general'), findsNothing);
  });

  testWidgets('an empty model shows a friendly empty state, not a hollow list (AD-8)',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      dirEntries: {'': const <RepoEntry>[]},
    );
    await _pumpReady(tester, storage);

    expect(find.textContaining('No lore entities found'), findsOneWidget);
    // The other ready-view actions are still available.
    expect(find.text('Open a file'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });
}
