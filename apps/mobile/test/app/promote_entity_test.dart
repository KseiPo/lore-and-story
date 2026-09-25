import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/app.dart';
import 'package:lore_and_story/app/editor_page.dart';
import 'package:lore_and_story/app/entity_detail_page.dart';
import 'package:lore_and_story/app/theme_mode_controller.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';
import 'test_image_fixtures.dart';

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

/// A `characters/` category with one simple entity, `characters/<fileName>`
/// (default `frank.md`; Story 5.6 also seeds `frank.ru.md` / `frank.en.md` /
/// `media.ru.md`), titled `# Frank`. When [withExistingCard] is set, a
/// pre-existing `frank/frank.md` exists — a genuine collision with what
/// promoting Frank would create; [withExistingIndexCard] seeds
/// `frank/index.md` instead, the loader's other card name (Story 5.6 AC3).
/// [withOrphanedFolder] seeds an *empty* `frank/` folder with no card inside
/// — simulating the aftermath of a previous failed promotion (Review fix
/// scenario) — which must NOT block a retry.
FakeRepoStorage _repo({
  String fileName = 'frank.md',
  bool withExistingCard = false,
  bool withExistingIndexCard = false,
  bool withOrphanedFolder = false,
  bool failMove = false,
}) {
  assert(!(withExistingCard && withExistingIndexCard));
  final hasExistingCard = withExistingCard || withExistingIndexCard;
  assert(!(hasExistingCard && withOrphanedFolder));
  final existingCardName = withExistingIndexCard ? 'index.md' : 'frank.md';
  return FakeRepoStorage(
    '/storage/emulated/0/repo',
    dirEntries: {
      '': const [
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
      ],
      'characters': [
        RepoEntry(
            name: fileName,
            path: 'characters/$fileName',
            isDirectory: false),
        if (hasExistingCard || withOrphanedFolder)
          const RepoEntry(
              name: 'frank', path: 'characters/frank', isDirectory: true),
      ],
      if (hasExistingCard)
        'characters/frank': [
          RepoEntry(
              name: existingCardName,
              path: 'characters/frank/$existingCardName',
              isDirectory: false),
        ],
      if (withOrphanedFolder) 'characters/frank': const [],
    },
    fileContents: {
      'characters/$fileName': '# Frank\n',
      if (hasExistingCard)
        'characters/frank/$existingCardName': '# Existing Frank\n',
    },
    failMove: failMove,
  );
}

/// Taps the (only) promote button, then confirms the dialog.
Future<void> _promoteAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('promote-entity-confirm')));
  await tester.pumpAndSettle();
}

Future<void> _pumpReady(WidgetTester tester, FakeRepoStorage storage) async {
  await tester.pumpWidget(LoreStoryApp(
    rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
    permission: FakeStoragePermission(granted: true),
    storageFactory: (root) => storage,
    keyStore: FakeKeyStore(),
    aiClient: FakeAiClient(),
    themeModeController: ThemeModeController(FakeThemeModeStore()),
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
      // Story 5.1 (AC2): nothing to rewrite here (no image references), so
      // no extra write beyond the plain move happens — today's behavior.
      expect(storage.writeCalls, isEmpty);
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

  group('Preserve image paths on promotion (Story 5.1, FR26)', () {
    testWidgets(
        'a promoted card with one relative image reference still renders '
        'the image afterwards (AC1 — verified by actually rendering, not '
        'string-diffing)', (tester) async {
      final storage = FakeRepoStorage(
        '/storage/emulated/0/repo',
        dirEntries: {
          '': const [
            RepoEntry(
                name: 'characters', path: 'characters', isDirectory: true),
          ],
          'characters': [
            const RepoEntry(
                name: 'frank.md', path: 'characters/frank.md', isDirectory: false),
          ],
        },
        fileContents: {
          'characters/frank.md': '# Frank\n\n![Frank](media/frank.jpg)\n',
        },
        // Seeded at the path the rewritten (../media/frank.jpg) src must
        // still resolve to from the card's new location.
        fileBytes: {'characters/media/frank.jpg': validPngFixture},
      );
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      expect(
        await storage.read('characters/frank/frank.md'),
        '# Frank\n\n![Frank](../media/frank.jpg)\n',
      );

      await tester.tap(find.text('Frank'));
      await tester.pumpAndSettle();

      expect(find.byType(EntityDetailPage), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets(
        'a card with multiple image references (plain-relative, already '
        '../-relative, and subfolder-relative) promotes with each src '
        'rewritten and nothing else changed (AC4)', (tester) async {
      const original = '# Frank\n\n'
          '![One](media/one.jpg)\n\n'
          'Some prose in between.\n\n'
          '![Two](../shared/two.png)\n\n'
          '![Three](media/sub/three.jpg)\n';
      const expected = '# Frank\n\n'
          '![One](../media/one.jpg)\n\n'
          'Some prose in between.\n\n'
          '![Two](../../shared/two.png)\n\n'
          '![Three](../media/sub/three.jpg)\n';
      final storage = _repo();
      // Overwrite the seeded card with one that has multiple images.
      await storage.writeAtomic('characters/frank.md', original);
      storage.writeCalls.clear();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      expect(await storage.read('characters/frank/frank.md'), expected);
    });

    testWidgets(
        'a card with no image references promotes unchanged, with no extra '
        'write beyond the move (AC2, AC4)', (tester) async {
      final storage = _repo();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      expect(await storage.read('characters/frank/frank.md'), '# Frank\n');
      expect(storage.writeCalls, isEmpty);
    });

    testWidgets(
        'a card with malformed/unparseable image markup still promotes '
        'successfully, with content left as-is (AC3 — rewrite failure never '
        'blocks the move)', (tester) async {
      const malformed = '# Frank\n\n![broken](media/x.jpg\n\nmore text after';
      final storage = _repo();
      await storage.writeAtomic('characters/frank.md', malformed);
      storage.writeCalls.clear();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Failed to promote this entity.'), findsNothing);
      expect(storage.moveCalls, [
        ('characters/frank.md', 'characters/frank/frank.md'),
      ]);
      expect(await storage.read('characters/frank/frank.md'), malformed);
    });

    testWidgets(
        'network and absolute image references are left untouched by '
        'promotion (AC2)', (tester) async {
      const original = '# Frank\n\n'
          '![Remote](https://example.com/hero.png)\n\n'
          '![Abs](/etc/hero.png)\n';
      final storage = _repo();
      await storage.writeAtomic('characters/frank.md', original);
      storage.writeCalls.clear();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('promote-entity-confirm')));
      await tester.pumpAndSettle();

      expect(await storage.read('characters/frank/frank.md'), original);
      expect(storage.writeCalls, isEmpty);
    });
  });

  group('Drop the language suffix on promotion (Story 5.6, FR26)', () {
    for (final fileName in ['frank.ru.md', 'frank.en.md']) {
      testWidgets(
          'promoting $fileName drops the suffix from both the folder and the '
          'card (AC1) — one move, no extra write', (tester) async {
        final storage = _repo(fileName: fileName);
        await _pumpReady(tester, storage);
        await _navigateToCategory(tester, 'characters');

        await _promoteAndConfirm(tester);

        expect(storage.moveCalls, [
          ('characters/$fileName', 'characters/frank/frank.md'),
        ]);
        expect(storage.ensureDirCalls, ['characters/frank']);
        expect(await storage.exists('characters/$fileName'), isFalse);
        expect(await storage.read('characters/frank/frank.md'), '# Frank\n');
        expect(storage.writeCalls, isEmpty);
      });
    }

    testWidgets(
        'after promoting a suffixed card, the loader recognizes the new '
        'folder: tapping the row opens the detail-tree outline (AC4)',
        (tester) async {
      final storage = _repo(fileName: 'frank.ru.md');
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _promoteAndConfirm(tester);
      await tester.tap(find.text('Frank'));
      await tester.pumpAndSettle();

      expect(find.byType(EntityDetailPage), findsOneWidget);
      expect(find.byType(EditorPage), findsNothing);
    });

    testWidgets(
        'a suffixed card whose suffix-free target card already exists is '
        'refused, never touching storage (AC3)', (tester) async {
      final storage =
          _repo(fileName: 'frank.ru.md', withExistingCard: true);
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _promoteAndConfirm(tester);

      expect(find.text('A folder with this name already exists.'),
          findsOneWidget);
      expect(storage.ensureDirCalls, isEmpty);
      expect(storage.moveCalls, isEmpty);
      expect(await storage.read('characters/frank.ru.md'), '# Frank\n');
    });

    testWidgets(
        'an existing index.md card in the target folder is a collision too '
        '(AC3) — index.md would win over the moved card', (tester) async {
      final storage = _repo(withExistingIndexCard: true);
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _promoteAndConfirm(tester);

      expect(find.text('A folder with this name already exists.'),
          findsOneWidget);
      expect(storage.ensureDirCalls, isEmpty);
      expect(storage.moveCalls, isEmpty);
      expect(await storage.exists('characters/frank.md'), isTrue);
    });

    testWidgets(
        'a card whose suffix-free folder name would be "media" is refused '
        'before anything is created (AC8) — the walk skips media/ folders',
        (tester) async {
      final storage = _repo(fileName: 'media.ru.md');
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pumpAndSettle();

      expect(
          find.text('"media" is reserved and cannot be used as a folder name.'),
          findsOneWidget);
      expect(storage.ensureDirCalls, isEmpty);
      expect(storage.moveCalls, isEmpty);
      expect(await storage.read('characters/media.ru.md'), '# Frank\n');
    });

    testWidgets(
        'a suffixed card with a relative image promotes with both the suffix '
        'dropped and the image path rewritten (AC1 + Story 5.1)',
        (tester) async {
      const original = '# Frank\n\n![Frank](media/frank.jpg)\n';
      final storage = _repo(fileName: 'frank.en.md');
      await storage.writeAtomic('characters/frank.en.md', original);
      storage.writeCalls.clear();
      await _pumpReady(tester, storage);
      await _navigateToCategory(tester, 'characters');

      await _promoteAndConfirm(tester);

      expect(storage.moveCalls, [
        ('characters/frank.en.md', 'characters/frank/frank.md'),
      ]);
      expect(await storage.read('characters/frank/frank.md'),
          '# Frank\n\n![Frank](../media/frank.jpg)\n');
    });
  });
}
