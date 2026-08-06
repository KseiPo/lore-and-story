import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/app.dart';
import 'package:lore_and_story/app/editor_page.dart';
import 'package:lore_and_story/app/entity_detail_page.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';

/// A [FakeRepoStorage] whose [movePath] pauses until [releaseMove] is called.
/// The plain fake resolves every call near-instantly (no real I/O delay), so
/// there is no way to observe UI state *while a promotion is genuinely still
/// in flight* without this — used only by the re-entrancy-guard test.
class _SlowMoveStorage extends FakeRepoStorage {
  final Completer<void> _gate = Completer<void>();

  _SlowMoveStorage(
    super.rootPath, {
    super.dirEntries,
    super.fileContents,
  });

  void releaseMove() => _gate.complete();

  @override
  Future<void> movePath(String from, String to) async {
    await _gate.future;
    return super.movePath(from, to);
  }
}

/// A `characters/` category with one simple entity (`frank.md`) and, when
/// [withExistingCard] is set, a pre-existing `frank/frank.md` — a genuine
/// collision with what promoting Frank would create. [withOrphanedFolder]
/// seeds an *empty* `frank/` folder with no card inside — simulating the
/// aftermath of a previous failed promotion (Review fix scenario) — which
/// must NOT block a retry.
FakeRepoStorage _repo({
  bool withExistingCard = false,
  bool withOrphanedFolder = false,
  bool failMove = false,
}) {
  assert(!(withExistingCard && withOrphanedFolder));
  return FakeRepoStorage(
    '/storage/emulated/0/repo',
    dirEntries: {
      '': const [
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
      ],
      'characters': [
        const RepoEntry(
            name: 'frank.md', path: 'characters/frank.md', isDirectory: false),
        if (withExistingCard || withOrphanedFolder)
          const RepoEntry(
              name: 'frank', path: 'characters/frank', isDirectory: true),
      ],
      if (withExistingCard)
        'characters/frank': const [
          RepoEntry(
              name: 'frank.md',
              path: 'characters/frank/frank.md',
              isDirectory: false),
        ],
      if (withOrphanedFolder) 'characters/frank': const [],
    },
    fileContents: {
      'characters/frank.md': '# Frank\n',
      if (withExistingCard) 'characters/frank/frank.md': '# Existing Frank\n',
    },
    failMove: failMove,
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

void main() {
  group('Promote a simple entity to a folder (Story 2.17, FR26)', () {
    testWidgets(
        'tap promote → confirm → creates the folder and moves the card',
        (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Promote to folder?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      expect(storage.moveCalls, [
        ('characters/frank.md', 'characters/frank/frank.md'),
      ]);
      expect(storage.ensureDirCalls, ['characters/frank']);
      expect(await storage.exists('characters/frank.md'), isFalse);
      expect(await storage.read('characters/frank/frank.md'), '# Frank\n');
    });

    testWidgets('cancelling the confirm dialog leaves everything untouched',
        (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(storage.moveCalls, isEmpty);
      expect(storage.ensureDirCalls, isEmpty);
      expect(await storage.exists('characters/frank.md'), isTrue);
    });

    testWidgets('a folder entity shows no promote button', (tester) async {
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
          'characters/selena': const [
            RepoEntry(
                name: 'selena.md',
                path: 'characters/selena/selena.md',
                isDirectory: false),
          ],
        },
        fileContents: {
          'characters/selena/selena.md': '# Selena\n',
        },
      );
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      expect(find.text('Selena'), findsOneWidget);
      expect(find.byIcon(Icons.create_new_folder_outlined), findsNothing);
    });

    testWidgets(
        'promoting when the target card already exists shows an error and '
        'never calls ensureDir or movePath', (tester) async {
      final storage = _repo(withExistingCard: true);
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('A folder with this name already exists.'),
          findsOneWidget);
      expect(storage.ensureDirCalls, isEmpty);
      expect(storage.moveCalls, isEmpty);
    });

    testWidgets(
        'promoting when an orphaned empty target folder exists (e.g. from a '
        'previously failed attempt) succeeds instead of being permanently '
        'blocked (Review fix)', (tester) async {
      final storage = _repo(withOrphanedFolder: true);
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('A folder with this name already exists.'), findsNothing);
      expect(storage.moveCalls, [
        ('characters/frank.md', 'characters/frank/frank.md'),
      ]);
    });

    testWidgets(
        'a movePath failure (after ensureDir already succeeded) shows an '
        'error and leaves the original card intact (AC4, Review fix)',
        (tester) async {
      final storage = _repo(failMove: true);
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Failed to promote this entity.'), findsOneWidget);
      // ensureDir ran (the folder now orphaned, empty) but the move itself
      // never touched the original.
      expect(storage.ensureDirCalls, ['characters/frank']);
      expect(await storage.exists('characters/frank.md'), isTrue);
      expect(await storage.read('characters/frank.md'), '# Frank\n');
    });

    testWidgets(
        'the promote button disables itself once confirmed, so a second tap '
        'while the move is still in flight cannot launch a concurrent '
        'promotion of the same row (Review fix)', (tester) async {
      final storage = _SlowMoveStorage(
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
        fileContents: {'characters/frank.md': '# Frank\n'},
      );
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      // `movePath` is gated on `storage`'s completer, so the promotion is
      // genuinely still in flight here — the button must already be disabled.
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(find.widgetWithIcon(
          IconButton, Icons.create_new_folder_outlined));
      expect(button.onPressed, isNull);
      expect(storage.moveCalls, isEmpty);

      storage.releaseMove();
      await tester.pumpAndSettle();
      expect(storage.moveCalls, hasLength(1));
    });

    testWidgets(
        'after a successful promotion, tapping the row opens the detail-tree '
        'outline, not the plain editor', (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Frank'));
      await tester.pumpAndSettle();

      expect(find.byType(EntityDetailPage), findsOneWidget);
      expect(find.byType(EditorPage), findsNothing);
    });
  });
}
