import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/app.dart';
import 'package:lore_and_story/app/editor_page.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';

FakeRepoStorage _repo({bool failWrites = false}) {
  return FakeRepoStorage(
    '/storage/emulated/0/repo',
    dirEntries: {
      '': const [
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
        RepoEntry(name: 'locations', path: 'locations', isDirectory: true),
      ],
      'characters': const [
        RepoEntry(
            name: 'frank.md', path: 'characters/frank.md', isDirectory: false),
      ],
      'locations': const [
        RepoEntry(
            name: 'tavern.md',
            path: 'locations/tavern.md',
            isDirectory: false),
      ],
    },
    fileContents: {
      'characters/frank.md': '# Frank\n',
      'locations/tavern.md': '# Tavern\n',
    },
    failWrites: failWrites,
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

Future<void> _navigateToCategory(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _tapFab(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

void main() {
  group('Create entity in existing category (Story 2.10, AC1/AC3/AC4/AC5)', () {
    testWidgets('FAB → dialog → create writes <slug>.ru.md with seed',
        (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _tapFab(tester);
      expect(find.text('New entity'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('entity-title-field')), 'Raven\'s Nest');
      await tester.tap(find.byKey(const Key('create-entity-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, hasLength(1));
      expect(storage.writeCalls.first,
          ('characters/ravens-nest.ru.md', '# Raven\'s Nest\n'));
      expect(storage.ensureDirCalls, isEmpty);

      // Editor opens on the new file (AC4).
      expect(find.byType(EditorPage), findsOneWidget);
    });

    testWidgets('duplicate entity name is rejected — no write', (tester) async {
      final storage = FakeRepoStorage(
        '/storage/emulated/0/repo',
        dirEntries: {
          '': const [
            RepoEntry(
                name: 'characters', path: 'characters', isDirectory: true),
          ],
          'characters': const [
            RepoEntry(
                name: 'frank.md',
                path: 'characters/frank.md',
                isDirectory: false),
            RepoEntry(
                name: 'frank.ru.md',
                path: 'characters/frank.ru.md',
                isDirectory: false),
          ],
        },
        fileContents: {
          'characters/frank.md': '# Frank\n',
          'characters/frank.ru.md': '# Frank\n',
        },
      );
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('entity-title-field')), 'Frank');
      await tester.tap(find.byKey(const Key('create-entity-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(find.text('An entity with this name already exists.'),
          findsOneWidget);
    });

    testWidgets('empty title → error, no write', (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('entity-title-field')), '   ');
      await tester.tap(find.byKey(const Key('create-entity-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(find.text('Title produces an invalid filename.'), findsOneWidget);
    });

    testWidgets('special-char-only title → error, no write', (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('entity-title-field')), '!!!');
      await tester.tap(find.byKey(const Key('create-entity-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(find.text('Title produces an invalid filename.'), findsOneWidget);
    });

    testWidgets('hyphen-only slug (e.g. "!! !!") → error, no write',
        (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('entity-title-field')), '!! !!');
      await tester.tap(find.byKey(const Key('create-entity-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(find.text('Title produces an invalid filename.'), findsOneWidget);
    });

    testWidgets('existing bare .md sibling is caught by clobber guard',
        (tester) async {
      final storage = FakeRepoStorage(
        '/storage/emulated/0/repo',
        dirEntries: {
          '': const [
            RepoEntry(
                name: 'characters', path: 'characters', isDirectory: true),
          ],
          'characters': const [
            RepoEntry(
                name: 'frank.md',
                path: 'characters/frank.md',
                isDirectory: false),
          ],
        },
        fileContents: {
          'characters/frank.md': '# Frank\n',
        },
      );
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('entity-title-field')), 'Frank');
      await tester.tap(find.byKey(const Key('create-entity-confirm')));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
      expect(find.text('An entity with this name already exists.'),
          findsOneWidget);
    });

    testWidgets('write failure → error snackbar, no editor navigation',
        (tester) async {
      final storage = _repo(failWrites: true);
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('entity-title-field')), 'New Guy');
      await tester.tap(find.byKey(const Key('create-entity-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Failed to create the entity.'), findsOneWidget);
      expect(find.byType(EditorPage), findsNothing);
    });

    testWidgets('cancel dialog → no write', (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('entity-title-field')), 'Some Entity');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(storage.writeCalls, isEmpty);
    });
  });

  group('Create entity in new category (Story 2.10, AC2)', () {
    testWidgets(
        'home FAB → dialog → ensureDir + writeAtomic for new category',
        (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);

      await _tapFab(tester);
      expect(find.text('New category & entity'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('category-name-field')), 'Races');
      await tester.enterText(
          find.byKey(const Key('new-cat-entity-title-field')),
          'Dark Elves');
      await tester.tap(find.byKey(const Key('create-new-category-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, ['races']);
      expect(storage.writeCalls, hasLength(1));
      expect(storage.writeCalls.first,
          ('races/dark-elves.ru.md', '# Dark Elves\n'));

      expect(find.byType(EditorPage), findsOneWidget);
    });

    testWidgets('existing category slug → info snackbar but still creates entity',
        (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('category-name-field')), 'Characters');
      await tester.enterText(
          find.byKey(const Key('new-cat-entity-title-field')), 'New Hero');
      await tester.tap(find.byKey(const Key('create-new-category-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Category already exists — adding entity to it.'),
          findsOneWidget);
      expect(storage.ensureDirCalls, ['characters']);
      expect(storage.writeCalls, hasLength(1));
      expect(storage.writeCalls.first,
          ('characters/new-hero.ru.md', '# New Hero\n'));
    });

    testWidgets('"media" category name is rejected as reserved',
        (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('category-name-field')), 'Media');
      await tester.enterText(
          find.byKey(const Key('new-cat-entity-title-field')), 'Some Entity');
      await tester.tap(find.byKey(const Key('create-new-category-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, isEmpty);
      expect(storage.writeCalls, isEmpty);
      expect(
          find.text(
              '"media" is reserved and cannot be used as a category name.'),
          findsOneWidget);
    });

    testWidgets('empty category name → error, no write', (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('category-name-field')), '   ');
      await tester.enterText(
          find.byKey(const Key('new-cat-entity-title-field')), 'Some Entity');
      await tester.tap(find.byKey(const Key('create-new-category-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, isEmpty);
      expect(storage.writeCalls, isEmpty);
      expect(find.text('Names produce invalid filenames.'), findsOneWidget);
    });

    testWidgets('empty entity title → error, no write', (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('category-name-field')), 'Races');
      await tester.enterText(
          find.byKey(const Key('new-cat-entity-title-field')), '');
      await tester.tap(find.byKey(const Key('create-new-category-confirm')));
      await tester.pumpAndSettle();

      expect(storage.ensureDirCalls, isEmpty);
      expect(storage.writeCalls, isEmpty);
      expect(find.text('Names produce invalid filenames.'), findsOneWidget);
    });

    testWidgets('write failure → error snackbar, no navigation',
        (tester) async {
      final storage = _repo(failWrites: true);
      await _pumpReady(tester, storage);

      await _tapFab(tester);
      await tester.enterText(
          find.byKey(const Key('category-name-field')), 'Races');
      await tester.enterText(
          find.byKey(const Key('new-cat-entity-title-field')), 'Dark Elves');
      await tester.tap(find.byKey(const Key('create-new-category-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Failed to create the entity.'), findsOneWidget);
      expect(find.byType(EditorPage), findsNothing);
    });
  });
}
