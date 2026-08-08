import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/editor_page.dart';
import 'package:lore_and_story/app/entity_detail_page.dart';
import 'package:lore_and_story/lore/lore_model.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';

/// An entity folder entry with a tree containing an `events` section.
LoreEntry _folderEntry() {
  return const LoreEntry(
    id: 'characters/selena/selena.md',
    title: 'Selena',
    aliases: ['Selena'],
    category: 'characters',
    relDir: 'characters/selena',
    text: '# Selena\n',
    tree: LoreNode(
      name: '',
      title: '',
      overview: null,
      items: [],
      children: [
        LoreNode(
          name: 'events',
          title: 'Events',
          overview: null,
          items: [
            LoreItem(
              id: 'events/meeting',
              title: 'Meeting',
              group: 'events',
              passage: null,
              langs: {
                'ru': LoreLang(
                  file: 'characters/selena/events/meeting.ru.md',
                  relDir: 'characters/selena/events',
                  title: 'Meeting',
                  text: '# Meeting\n',
                ),
              },
            ),
          ],
          children: [],
        ),
      ],
    ),
    children: [
      LoreChild(
        id: 'events/meeting',
        title: 'Meeting',
        group: 'events',
        text: '# Meeting\n',
      ),
    ],
  );
}

/// An entity folder entry whose only section is named `Side Quests` — a raw
/// on-disk folder name that does NOT already equal its own `_slugify` form
/// (`side-quests`). Used to prove a suggestion chip writes into the exact
/// folder it names, never a re-slugified guess at it.
LoreEntry _mixedCaseGroupEntry() {
  return const LoreEntry(
    id: 'characters/selena/selena.md',
    title: 'Selena',
    aliases: ['Selena'],
    category: 'characters',
    relDir: 'characters/selena',
    text: '# Selena\n',
    tree: LoreNode(
      name: '',
      title: '',
      overview: null,
      items: [],
      children: [
        LoreNode(
          name: 'Side Quests',
          title: 'Side Quests',
          overview: null,
          items: [],
          children: [],
        ),
      ],
    ),
    children: [],
  );
}

/// A simple entity (no folder / no tree) — the FAB should be hidden.
LoreEntry _simpleEntry() {
  return const LoreEntry(
    id: 'characters/frank.md',
    title: 'Frank',
    aliases: ['Frank'],
    category: 'characters',
    relDir: 'characters',
    text: '# Frank\n',
    tree: null,
    children: [],
  );
}

FakeRepoStorage _storage({bool failWrites = false}) {
  return FakeRepoStorage(
    '/storage/emulated/0/repo',
    dirEntries: {
      '': const [
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
      ],
      'characters': const [
        RepoEntry(
            name: 'selena', path: 'characters/selena', isDirectory: true),
      ],
      'characters/selena': const [
        RepoEntry(
            name: 'selena.md',
            path: 'characters/selena/selena.md',
            isDirectory: false),
      ],
      'characters/selena/events': const [
        RepoEntry(
            name: 'meeting.ru.md',
            path: 'characters/selena/events/meeting.ru.md',
            isDirectory: false),
      ],
    },
    fileContents: {
      'characters/selena/selena.md': '# Selena\n',
      'characters/selena/events/meeting.ru.md': '# Meeting\n',
    },
    failWrites: failWrites,
  );
}

Future<void> _pumpDetail(
  WidgetTester tester,
  FakeRepoStorage storage,
  LoreEntry entry,
) async {
  await tester.pumpWidget(MaterialApp(
    home: EntityDetailPage(
      storage: storage,
      entry: entry,
      loreDir: '',
      aiClient: FakeAiClient(),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapFab(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

void main() {
  group('Create sub-entry (Story 2.11)', () {
    testWidgets('FAB → dialog → creates <slug>.ru.md in new group',
        (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      expect(find.text('New sub-entry'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), 'quests');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'The Dark Forest');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, ['characters/selena/quests']);
      expect(storage.writeCalls, hasLength(1));
      expect(storage.writeCalls.first,
          ('characters/selena/quests/the-dark-forest.ru.md',
              '# The Dark Forest\n'));
      expect(find.byType(EditorPage), findsOneWidget);
    });

    testWidgets('creates sub-entry in existing group', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), 'events');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'Departure');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, ['characters/selena/events']);
      expect(storage.writeCalls, hasLength(1));
      expect(storage.writeCalls.first,
          ('characters/selena/events/departure.ru.md', '# Departure\n'));
      expect(find.byType(EditorPage), findsOneWidget);
    });

    testWidgets('FAB hidden for simple entity (no tree)', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _simpleEntry());

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets(
        'empty group creates the sub-entry at the entity root, no subfolder '
        '(Story 2.19, AC1)', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      // Leave the group field untouched entirely.
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'Some Event');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, isEmpty);
      expect(storage.writeCalls, [
        ('characters/selena/some-event.ru.md', '# Some Event\n'),
      ]);
      expect(find.byType(EditorPage), findsOneWidget);
    });

    testWidgets(
        'whitespace-only group also creates at the entity root (same as '
        'empty — both slugify to "")', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), '   ');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'Some Event');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, isEmpty);
      expect(storage.writeCalls, [
        ('characters/selena/some-event.ru.md', '# Some Event\n'),
      ]);
      expect(find.byType(EditorPage), findsOneWidget);
    });

    for (final clobberFile in [
      'some-event.ru.md',
      'some-event.md',
      'some-event.en.md',
    ]) {
      testWidgets(
          'a clobber at the entity root ($clobberFile) is still caught, no '
          'write (Story 2.19)', (tester) async {
        final storage = FakeRepoStorage(
          '/storage/emulated/0/repo',
          dirEntries: {
            '': const [
              RepoEntry(
                  name: 'characters', path: 'characters', isDirectory: true),
            ],
            'characters': const [
              RepoEntry(
                  name: 'selena', path: 'characters/selena', isDirectory: true),
            ],
            'characters/selena': [
              const RepoEntry(
                  name: 'selena.md',
                  path: 'characters/selena/selena.md',
                  isDirectory: false),
              RepoEntry(
                  name: clobberFile,
                  path: 'characters/selena/$clobberFile',
                  isDirectory: false),
            ],
          },
          fileContents: {
            'characters/selena/selena.md': '# Selena\n',
            'characters/selena/$clobberFile': '# Some Event\n',
          },
        );
        await _pumpDetail(tester, storage, _folderEntry());

        await _tapFab(tester);
        await tester.enterText(
            find.byKey(const Key('sub-entry-title-field')), 'Some Event');
        await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
        await tester.pumpAndSettle();

        expect(storage.writeCalls, isEmpty);
        expect(storage.ensureDirCalls, isEmpty);
        expect(find.text('A sub-entry with this name already exists.'),
            findsOneWidget);
      });
    }

    testWidgets(
        'existing groups render as tappable chips, and tapping one fills '
        'the group field (without submitting) and still creates in that '
        'group (Story 2.19, AC2)', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      expect(find.byKey(const Key('sub-entry-group-chip-events')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sub-entry-group-chip-events')));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('sub-entry-group-field')),
          matching: find.text('events'),
        ),
        findsOneWidget,
      );
      // Tapping the chip only fills the field — it must not submit.
      expect(storage.writeCalls, isEmpty);
      expect(find.text('New sub-entry'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'Departure');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, ['characters/selena/events']);
      expect(storage.writeCalls, [
        ('characters/selena/events/departure.ru.md', '# Departure\n'),
      ]);
    });

    testWidgets(
        'a chip for a group whose raw name is not already slug-safe writes '
        'into that exact folder, never a re-slugified guess at it (Story '
        '2.19 review fix)', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _mixedCaseGroupEntry());

      await _tapFab(tester);
      await tester.tap(find.byKey(const Key('sub-entry-group-chip-Side Quests')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'New Quest');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      // Writes into "Side Quests" exactly as it exists on disk — NOT
      // "side-quests", which would silently create a near-duplicate folder.
      expect(storage.ensureDirCalls, ['characters/selena/Side Quests']);
      expect(storage.writeCalls, [
        ('characters/selena/Side Quests/new-quest.ru.md', '# New Quest\n'),
      ]);
    });

    testWidgets(
        'typed group text that slugifies to nothing (but was not left '
        'blank) still errors, instead of silently falling back to root '
        '(Story 2.19 review fix)', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), '!!!');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'Some Event');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(storage.ensureDirCalls, isEmpty);
      expect(find.text('Names produce invalid filenames.'), findsOneWidget);
    });

    testWidgets(
        'a chip can still be overridden by typing a different group name '
        '(Story 2.19, AC3)', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.tap(find.byKey(const Key('sub-entry-group-chip-events')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), 'quests');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'New Quest');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, ['characters/selena/quests']);
      expect(storage.writeCalls, [
        ('characters/selena/quests/new-quest.ru.md', '# New Quest\n'),
      ]);
    });

    testWidgets(
        'an entity with no sections yet shows no group chips (Story 2.19)',
        (tester) async {
      const noSectionsEntry = LoreEntry(
        id: 'characters/selena/selena.md',
        title: 'Selena',
        aliases: ['Selena'],
        category: 'characters',
        relDir: 'characters/selena',
        text: '# Selena\n',
        tree: LoreNode(
          name: '',
          title: '',
          overview: null,
          items: [],
          children: [],
        ),
        children: [],
      );
      final storage = _storage();
      await _pumpDetail(tester, storage, noSectionsEntry);

      await _tapFab(tester);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('New sub-entry'), findsOneWidget);
    });

    testWidgets('empty title → error, no write', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), 'events');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), '');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(storage.ensureDirCalls, isEmpty);
      expect(find.text('Names produce invalid filenames.'), findsOneWidget);
    });

    testWidgets('hyphen-only slug → error, no write', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), 'events');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), '!! !!');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(find.text('Names produce invalid filenames.'), findsOneWidget);
    });

    testWidgets('"media" group name is rejected as reserved', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), 'Media');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'Some Event');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(storage.ensureDirCalls, isEmpty);
      expect(
          find.text('"media" is reserved and cannot be used as a group name.'),
          findsOneWidget);
    });

    testWidgets('duplicate exists → error, no write', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), 'events');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'Meeting');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(find.text('A sub-entry with this name already exists.'),
          findsOneWidget);
    });

    testWidgets('write failure → error snackbar, no navigation',
        (tester) async {
      final storage = _storage(failWrites: true);
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), 'quests');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'New Quest');
      await tester.tap(find.byKey(const Key('create-sub-entry-confirm')));
      await tester.pumpAndSettle();

      expect(
          find.text('Failed to create the sub-entry.'), findsOneWidget);
      expect(find.byType(EditorPage), findsNothing);
    });

    testWidgets('cancel dialog → no write', (tester) async {
      final storage = _storage();
      await _pumpDetail(tester, storage, _folderEntry());

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('sub-entry-group-field')), 'events');
      await tester.enterText(
          find.byKey(const Key('sub-entry-title-field')), 'Some Event');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(storage.ensureDirCalls, isEmpty);
    });
  });
}
