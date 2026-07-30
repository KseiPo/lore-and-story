import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/entity_detail_page.dart';
import 'package:lore_and_story/app/editor_page.dart';
import 'package:lore_and_story/app/paired_editor_page.dart';
import 'package:lore_and_story/lore/lore.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';
import 'editor_test_helpers.dart';

/// An entity folder `selena/` (the picked root is the lore folder):
///
/// ```
/// selena/
///   selena.md                         (card — # Selena)
///   bio.md                            (root sub-entry — # Bio)
///   events/
///     events.md                       (section overview — # Events)
///     first-meeting.md                (# First Meeting)
///   quests/
///     relationship-quest-1/
///       01-hobby.md                   (# Hobby)
///   media/                            (excluded by the walk)
///     portrait.png
/// ```
FakeRepoStorage _repo() => FakeRepoStorage(
      '/storage/emulated/0/repo',
      dirEntries: {
        '': const [RepoEntry(name: 'selena', path: 'selena', isDirectory: true)],
        'selena': const [
          RepoEntry(name: 'selena.md', path: 'selena/selena.md', isDirectory: false),
          RepoEntry(name: 'bio.md', path: 'selena/bio.md', isDirectory: false),
          RepoEntry(name: 'events', path: 'selena/events', isDirectory: true),
          RepoEntry(name: 'quests', path: 'selena/quests', isDirectory: true),
          RepoEntry(name: 'media', path: 'selena/media', isDirectory: true),
        ],
        'selena/events': const [
          RepoEntry(name: 'events.md', path: 'selena/events/events.md', isDirectory: false),
          RepoEntry(
              name: 'first-meeting.md',
              path: 'selena/events/first-meeting.md',
              isDirectory: false),
        ],
        'selena/quests': const [
          RepoEntry(
              name: 'relationship-quest-1',
              path: 'selena/quests/relationship-quest-1',
              isDirectory: true),
        ],
        'selena/quests/relationship-quest-1': const [
          RepoEntry(
              name: '01-hobby.md',
              path: 'selena/quests/relationship-quest-1/01-hobby.md',
              isDirectory: false),
        ],
        'selena/media': const [
          RepoEntry(name: 'portrait.png', path: 'selena/media/portrait.png', isDirectory: false),
        ],
      },
      fileContents: {
        'selena/selena.md': '# Selena\n',
        'selena/bio.md': '# Bio\n',
        'selena/events/events.md': '# Events\n',
        'selena/events/first-meeting.md': '# First Meeting\n',
        'selena/quests/relationship-quest-1/01-hobby.md': '# Hobby\n',
      },
    );

/// Loads the model and returns the entity whose id matches [id].
Future<LoreEntry> _entry(FakeRepoStorage storage, String id) async {
  final model = await loadLore(storage, '');
  return model.entries.firstWhere((e) => e.id == id);
}

Future<void> _pump(WidgetTester tester, FakeRepoStorage storage, LoreEntry entry) async {
  await tester.pumpWidget(MaterialApp(
    home: EntityDetailPage(storage: storage, entry: entry, loreDir: ''),
  ));
  await tester.pumpAndSettle();
}

/// A `selena/` folder with one **paired** sub-entry (`scene.ru.md` + `scene.en.md`)
/// and one single-file sub-entry (`bio.md`).
FakeRepoStorage _pairRepo() => FakeRepoStorage(
      '/repo',
      dirEntries: {
        '': const [RepoEntry(name: 'selena', path: 'selena', isDirectory: true)],
        'selena': const [
          RepoEntry(name: 'selena.md', path: 'selena/selena.md', isDirectory: false),
          RepoEntry(name: 'bio.md', path: 'selena/bio.md', isDirectory: false),
          RepoEntry(name: 'scene.ru.md', path: 'selena/scene.ru.md', isDirectory: false),
          RepoEntry(name: 'scene.en.md', path: 'selena/scene.en.md', isDirectory: false),
        ],
      },
      fileContents: {
        'selena/selena.md': '# Selena\n',
        'selena/bio.md': '# Bio\n',
        'selena/scene.ru.md': '# Сцена\n',
        'selena/scene.en.md': '# Scene\n',
      },
    );

void main() {
  group('RU/EN pair routing (Story 2.8)', () {
    testWidgets('tapping a paired sub-entry opens the tabbed paired editor',
        (tester) async {
      final storage = _pairRepo();
      final selena = await _entry(storage, 'selena/selena.md');
      await _pump(tester, storage, selena);

      // The pair renders as one row titled "<ru> — <en>".
      await tester.tap(find.text('Сцена — Scene'));
      await tester.pumpAndSettle();

      expect(find.byType(PairedEditorPage), findsOneWidget);
      expect(find.text('RU'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
    });

    testWidgets('tapping a single-file sub-entry opens the plain editor (no tabs)',
        (tester) async {
      final storage = _pairRepo();
      final selena = await _entry(storage, 'selena/selena.md');
      await _pump(tester, storage, selena);

      await tester.tap(find.text('Bio'));
      await tester.pumpAndSettle();

      expect(find.byType(EditorPage), findsOneWidget);
      expect(find.byType(PairedEditorPage), findsNothing);
      expect(find.byType(TabBar), findsNothing);
    });
  });

  testWidgets('renders the card, root items, sections, and nested sections (FR6)',
      (tester) async {
    final storage = _repo();
    final selena = await _entry(storage, 'selena/selena.md');
    await _pump(tester, storage, selena);

    // Card on top (keyed so it is distinct from the AppBar title).
    expect(find.byKey(const Key('entity-card')), findsOneWidget);
    // Root-level sub-entry.
    expect(find.text('Bio'), findsOneWidget);
    // Section headers (Events takes its heading from events.md; quests is the
    // prettified folder name).
    expect(find.text('Events'), findsOneWidget);
    expect(find.text('quests'), findsOneWidget);
    // A section overview row.
    expect(find.text('Overview'), findsOneWidget);
    // Section item.
    expect(find.text('First Meeting'), findsOneWidget);
    // Nested section (prettified) + its item.
    expect(find.text('relationship quest 1'), findsOneWidget);
    expect(find.text('Hobby'), findsOneWidget);
  });

  testWidgets('media/ is excluded and the card is not listed as its own child (FR6)',
      (tester) async {
    final storage = _repo();
    final selena = await _entry(storage, 'selena/selena.md');
    await _pump(tester, storage, selena);

    expect(find.text('media'), findsNothing);
    expect(find.text('portrait.png'), findsNothing);
    // The card 'Selena' appears once as the keyed card row (plus the AppBar
    // title) — never duplicated as a sub-entry beneath itself.
    expect(find.widgetWithText(ListTile, 'Selena'), findsOneWidget);
  });

  testWidgets('tapping the card opens it in the editor', (tester) async {
    final storage = _repo();
    final selena = await _entry(storage, 'selena/selena.md');
    await _pump(tester, storage, selena);

    await tester.tap(find.byKey(const Key('entity-card')));
    await tester.pumpAndSettle();
    await enterEditMode(tester); // editor opens in preview (Story 2.7)
    expect(find.widgetWithText(TextField, '# Selena\n'), findsOneWidget);
  });

  testWidgets('tapping a sub-entry, a section item, and an overview each opens the editor',
      (tester) async {
    final storage = _repo();
    final selena = await _entry(storage, 'selena/selena.md');
    await _pump(tester, storage, selena);

    for (final probe in const [
      ('Bio', '# Bio\n'),
      ('First Meeting', '# First Meeting\n'),
      ('Hobby', '# Hobby\n'),
      ('Overview', '# Events\n'),
    ]) {
      await tester.tap(find.text(probe.$1));
      await tester.pumpAndSettle();
      await enterEditMode(tester); // editor opens in preview (Story 2.7)
      expect(find.widgetWithText(TextField, probe.$2), findsOneWidget,
          reason: 'tapping "${probe.$1}" should open ${probe.$2}');
      // Back to the detail outline for the next probe (nothing was edited, so
      // the editor pops without a save prompt).
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a card-only entity folder shows just the card without throwing (AD-8)',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      dirEntries: {
        '': const [RepoEntry(name: 'lonely', path: 'lonely', isDirectory: true)],
        'lonely': const [
          RepoEntry(name: 'lonely.md', path: 'lonely/lonely.md', isDirectory: false),
        ],
      },
      fileContents: {'lonely/lonely.md': '# Lonely\n'},
    );
    final entry = await _entry(storage, 'lonely/lonely.md');
    // It is a folder entity (has a tree), just an empty one.
    expect(entry.tree, isNotNull);
    await _pump(tester, storage, entry);

    expect(find.byKey(const Key('entity-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rows render in order: card, then items, then sections, nested below parent',
      (tester) async {
    final storage = _repo();
    final selena = await _entry(storage, 'selena/selena.md');
    await _pump(tester, storage, selena);

    double y(Finder f) => tester.getTopLeft(f).dy;
    // Card above the root sub-entry above the first section header.
    expect(y(find.byKey(const Key('entity-card'))), lessThan(y(find.text('Bio'))));
    expect(y(find.text('Bio')), lessThan(y(find.text('Events'))));
    // A nested section header sits below its parent section header...
    expect(y(find.text('quests')), lessThan(y(find.text('relationship quest 1'))));
    // ...and its item sits below the nested header (nesting is not flattened).
    expect(y(find.text('relationship quest 1')), lessThan(y(find.text('Hobby'))));
  });

  testWidgets('a dual-card folder surfaces the second card as an Overview row (not stranded)',
      (tester) async {
    // Both index.md and dual.md present: the loader picks index.md as the card
    // and dual.md becomes the entity-root node's overview.
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      dirEntries: {
        '': const [RepoEntry(name: 'dual', path: 'dual', isDirectory: true)],
        'dual': const [
          RepoEntry(name: 'index.md', path: 'dual/index.md', isDirectory: false),
          RepoEntry(name: 'dual.md', path: 'dual/dual.md', isDirectory: false),
        ],
      },
      fileContents: {
        'dual/index.md': '# Dual Card\n',
        'dual/dual.md': '# Dual Overview\n',
      },
    );
    final entry = await _entry(storage, 'dual/index.md');
    await _pump(tester, storage, entry);

    expect(find.byKey(const Key('entity-card')), findsOneWidget);
    // The second card is reachable as an Overview row, not stranded.
    expect(find.text('Overview'), findsOneWidget);
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    await enterEditMode(tester); // editor opens in preview (Story 2.7)
    expect(find.widgetWithText(TextField, '# Dual Overview\n'), findsOneWidget);
  });

  testWidgets('an entity deleted between scans degrades to a "no longer present" state',
      (tester) async {
    // A mutable listing lets the card vanish while the detail page is open.
    final selenaListing = <RepoEntry>[
      const RepoEntry(name: 'selena.md', path: 'selena/selena.md', isDirectory: false),
      const RepoEntry(name: 'bio.md', path: 'selena/bio.md', isDirectory: false),
    ];
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      dirEntries: {
        '': const [RepoEntry(name: 'selena', path: 'selena', isDirectory: true)],
        'selena': selenaListing,
      },
      fileContents: {'selena/selena.md': '# Selena\n', 'selena/bio.md': '# Bio\n'},
    );
    final selena = await _entry(storage, 'selena/selena.md');
    await _pump(tester, storage, selena);

    await tester.tap(find.text('Bio'));
    await tester.pumpAndSettle();
    // The entity's card vanishes on disk while the sub-entry is open.
    selenaListing.removeWhere((e) => e.name == 'selena.md');
    await tester.pageBack(); // triggers _rescan
    await tester.pumpAndSettle();

    expect(find.text('This entity is no longer present.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a sub-entry updates the detail row on return (AC3 rescan)',
      (tester) async {
    final storage = _repo();
    final selena = await _entry(storage, 'selena/selena.md');
    await _pump(tester, storage, selena);

    await tester.tap(find.text('Bio'));
    await tester.pumpAndSettle();
    await enterEditMode(tester); // editor opens in preview (Story 2.7)
    await tester.enterText(find.byType(TextField), '# Biography\n');
    await tester.pump();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The detail re-walked and shows the new title.
    expect(find.text('Biography'), findsOneWidget);
    expect(find.text('Bio'), findsNothing);
  });
}
