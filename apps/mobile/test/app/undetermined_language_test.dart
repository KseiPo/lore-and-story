import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/editor_page.dart';
import 'package:lore_and_story/app/entity_detail_page.dart';
import 'package:lore_and_story/app/paired_editor_page.dart';
import 'package:lore_and_story/app/undetermined_language_page.dart';
import 'package:lore_and_story/lore/lore.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';
import 'editor_test_helpers.dart';

/// A bare `.md` sub-entry with no declared language — `langs == {'orig': ...}`
/// (mirrors `paired_editor_page_test.dart`'s direct-construction style, the
/// closer precedent: `UndeterminedLanguagePage` shares `PairedEditorPage`'s
/// constructor shape).
LoreItem undeterminedItem() => const LoreItem(
      id: 'events/first-meeting',
      title: 'First Meeting',
      group: 'events',
      passage: null,
      langs: {
        'orig': LoreLang(
          file: 'events/first-meeting.md',
          relDir: 'events',
          title: 'First Meeting',
          text: '# First Meeting\n',
        ),
      },
    );

FakeRepoStorage undeterminedStorage({bool failMove = false}) => FakeRepoStorage(
      '/repo',
      // `dirEntries` must know about `events/` even though this story never
      // calls `ensureDir` (it's a same-directory rename) — the fake's
      // `movePath` requires the destination's parent to be a registered
      // directory, mirroring the real adapter's ENOENT-on-missing-parent
      // behavior (Story 2.17's review fix). On a real filesystem `events/`
      // already exists because `first-meeting.md` is in it; the fake needs
      // that told to it explicitly.
      dirEntries: {
        'events': const [
          RepoEntry(
              name: 'first-meeting.md',
              path: 'events/first-meeting.md',
              isDirectory: false),
        ],
      },
      fileContents: {'events/first-meeting.md': '# First Meeting\n'},
      failMove: failMove,
    );

Future<void> pumpUndetermined(
  WidgetTester tester,
  FakeRepoStorage storage,
  LoreItem item, {
  String loreDir = '',
}) async {
  await tester.pumpWidget(MaterialApp(
    home: UndeterminedLanguagePage(storage: storage, item: item, loreDir: loreDir),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('assign a language to a bare .md file (Story 2.18)', () {
    testWidgets(
        'shows real RU/EN tabs and the actual file content — reading it '
        'never required declaring a language first', (tester) async {
      await pumpUndetermined(tester, undeterminedStorage(), undeterminedItem());

      expect(find.byKey(const Key('lang-tab-ru')), findsOneWidget);
      expect(find.byKey(const Key('lang-tab-en')), findsOneWidget);
      // The body is a real, live FileEditor over the bare file — content is
      // visible immediately (rendered by default, Story 2.7's preview-first).
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.textContaining('First Meeting'), findsWidgets);

      // Neither tab reads as "selected" — no controller-driven TabBarView, no
      // indicator color set.
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.indicatorColor, Colors.transparent);
      expect(tabBar.labelColor, tabBar.unselectedLabelColor);
    });

    testWidgets(
        'the file is genuinely editable before any language is declared',
        (tester) async {
      await pumpUndetermined(tester, undeterminedStorage(), undeterminedItem());
      await enterEditMode(tester);

      expect(find.widgetWithText(TextField, '# First Meeting\n'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '# First Meeting\nDraft text.');
      await tester.pump();

      expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
    });

    testWidgets('tapping the RU tab shows the Russian confirmation dialog '
        '(reading the content did not require this)', (tester) async {
      await pumpUndetermined(tester, undeterminedStorage(), undeterminedItem());

      await tester.tap(find.byKey(const Key('lang-tab-ru')));
      await tester.pumpAndSettle();

      expect(find.text('Is this file written in Russian?'), findsOneWidget);
    });

    testWidgets('tapping the EN tab shows the English confirmation dialog',
        (tester) async {
      await pumpUndetermined(tester, undeterminedStorage(), undeterminedItem());

      await tester.tap(find.byKey(const Key('lang-tab-en')));
      await tester.pumpAndSettle();

      expect(find.text('Is this file written in English?'), findsOneWidget);
    });

    testWidgets(
        'confirming RU renames the file and transitions in place to the '
        'standard paired-editor state (RU content + EN needs-translation tab)',
        (tester) async {
      final storage = undeterminedStorage();
      await pumpUndetermined(tester, storage, undeterminedItem());

      await tester.tap(find.byKey(const Key('lang-tab-ru')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-language-ru')));
      await tester.pumpAndSettle();

      expect(storage.moveCalls, [
        ('events/first-meeting.md', 'events/first-meeting.ru.md'),
      ]);
      expect(await storage.exists('events/first-meeting.md'), isFalse);

      // In-place transition: no navigation happened, this is still the same
      // screen, now delegating to PairedEditorPage.
      expect(find.byType(PairedEditorPage), findsOneWidget);
      expect(find.byType(UndeterminedLanguagePage), findsOneWidget);
      expect(find.text('RU'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
      // RU tab is active by default with the real content — the editor opens
      // in read-only preview by default (Story 2.7), so switch to the raw
      // editor to see the TextField.
      await enterEditMode(tester);
      expect(find.widgetWithText(TextField, '# First Meeting\n'), findsOneWidget);

      // EN tab is the Story 2.9 create-translation candidate.
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.translate), findsOneWidget);
    });

    testWidgets(
        'confirming EN renames the file and transitions in place to the '
        'standard paired-editor state (EN content + RU needs-translation '
        'tab) — the mirror of the RU case', (tester) async {
      final storage = undeterminedStorage();
      await pumpUndetermined(tester, storage, undeterminedItem());

      await tester.tap(find.byKey(const Key('lang-tab-en')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-language-en')));
      await tester.pumpAndSettle();

      expect(storage.moveCalls, [
        ('events/first-meeting.md', 'events/first-meeting.en.md'),
      ]);
      expect(await storage.exists('events/first-meeting.md'), isFalse);

      expect(find.byType(PairedEditorPage), findsOneWidget);
      expect(find.byType(UndeterminedLanguagePage), findsOneWidget);
      expect(find.text('RU'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);

      // EN — the real, confirmed content — is active by default.
      await enterEditMode(tester);
      expect(find.widgetWithText(TextField, '# First Meeting\n'), findsOneWidget);

      // RU is now the Story 2.9 create-translation candidate.
      await tester.tap(find.text('RU'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.translate), findsOneWidget);
    });

    testWidgets(
        'a dirty buffer that cannot be safely saved (a lossy load) blocks '
        'confirmation instead of assigning the language (AC5)',
        (tester) async {
      const lossy = 'caf\u{FFFD} content';
      final storage = FakeRepoStorage(
        '/repo',
        dirEntries: {
          'events': const [
            RepoEntry(
                name: 'first-meeting.md',
                path: 'events/first-meeting.md',
                isDirectory: false),
          ],
        },
        fileContents: {'events/first-meeting.md': lossy},
      );
      await pumpUndetermined(
        tester,
        storage,
        undeterminedItem(),
      );

      await enterEditMode(tester);
      await tester.enterText(find.byType(TextField), '${lossy}Draft');
      await tester.pump();

      await tester.tap(find.byKey(const Key('lang-tab-ru')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-language-ru')));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'This file cannot be saved (invalid UTF-8) — resolve that before assigning a language.'),
        findsOneWidget,
      );
      expect(storage.moveCalls, isEmpty);
      expect(storage.writeCalls, isEmpty);
      expect(await storage.exists('events/first-meeting.md'), isTrue);
    });

    testWidgets(
        'a failed save blocks the rename — never renames a file out from '
        'under a write that did not land (AD-10)', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        dirEntries: {
          'events': const [
            RepoEntry(
                name: 'first-meeting.md',
                path: 'events/first-meeting.md',
                isDirectory: false),
          ],
        },
        fileContents: {'events/first-meeting.md': '# First Meeting\n'},
        failWrites: true,
      );
      await pumpUndetermined(tester, storage, undeterminedItem());

      await enterEditMode(tester);
      await tester.enterText(
          find.byType(TextField), '# First Meeting\nDraft text.');
      await tester.pump();

      await tester.tap(find.byKey(const Key('lang-tab-ru')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-language-ru')));
      await tester.pumpAndSettle();

      expect(storage.moveCalls, isEmpty);
      expect(await storage.exists('events/first-meeting.md'), isTrue);
      expect(await storage.exists('events/first-meeting.ru.md'), isFalse);
    });

    testWidgets(
        'an edit made before declaring the language is saved first, then '
        'carried through the rename (AD-10 — never rename a dirty buffer '
        'out from under itself)', (tester) async {
      final storage = undeterminedStorage();
      await pumpUndetermined(tester, storage, undeterminedItem());

      await enterEditMode(tester);
      await tester.enterText(
          find.byType(TextField), '# First Meeting\nDraft text.');
      await tester.pump();
      expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);

      await tester.tap(find.byKey(const Key('lang-tab-ru')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-language-ru')));
      await tester.pumpAndSettle();

      // The edit was saved to the ORIGINAL path before the rename moved it.
      expect(storage.writeCalls, [
        ('events/first-meeting.md', '# First Meeting\nDraft text.'),
      ]);
      expect(storage.moveCalls, [
        ('events/first-meeting.md', 'events/first-meeting.ru.md'),
      ]);
      expect(
          await storage.read('events/first-meeting.ru.md'),
          '# First Meeting\nDraft text.');
    });

    testWidgets('cancelling the confirm dialog leaves everything untouched, '
        'including any unsaved edit', (tester) async {
      final storage = undeterminedStorage();
      await pumpUndetermined(tester, storage, undeterminedItem());

      await enterEditMode(tester);
      await tester.enterText(
          find.byType(TextField), '# First Meeting\nDraft text.');
      await tester.pump();

      await tester.tap(find.byKey(const Key('lang-tab-ru')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(storage.moveCalls, isEmpty);
      expect(storage.writeCalls, isEmpty);
      expect(find.byKey(const Key('lang-tab-ru')), findsOneWidget);
      expect(find.byKey(const Key('lang-tab-en')), findsOneWidget);
      // The edit survives the cancelled dialog — still there, still dirty.
      expect(find.widgetWithText(TextField, '# First Meeting\nDraft text.'),
          findsOneWidget);
      expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
    });

    testWidgets(
        'confirming when the target file already exists shows an error and '
        'never calls movePath', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        dirEntries: {
          'events': const [
            RepoEntry(
                name: 'first-meeting.md',
                path: 'events/first-meeting.md',
                isDirectory: false),
            RepoEntry(
                name: 'first-meeting.ru.md',
                path: 'events/first-meeting.ru.md',
                isDirectory: false),
          ],
        },
        fileContents: {
          'events/first-meeting.md': '# First Meeting\n',
          'events/first-meeting.ru.md': '# Already here\n',
        },
      );
      await pumpUndetermined(tester, storage, undeterminedItem());

      await tester.tap(find.byKey(const Key('lang-tab-ru')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-language-ru')));
      await tester.pumpAndSettle();

      expect(find.text('A file with this name already exists.'), findsOneWidget);
      expect(storage.moveCalls, isEmpty);
      // The original is never touched.
      expect(await storage.exists('events/first-meeting.md'), isTrue);
    });

    testWidgets(
        'a movePath failure shows an error and leaves the screen usable, '
        'still undetermined (AC5)', (tester) async {
      final storage = undeterminedStorage(failMove: true);
      await pumpUndetermined(tester, storage, undeterminedItem());

      await tester.tap(find.byKey(const Key('lang-tab-ru')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-language-ru')));
      await tester.pumpAndSettle();

      expect(find.text('Failed to set the language.'), findsOneWidget);
      expect(await storage.exists('events/first-meeting.md'), isTrue);
      // Not stranded: the tabs (and the editable content) are still there.
      expect(find.byKey(const Key('lang-tab-ru')), findsOneWidget);
      expect(find.byKey(const Key('lang-tab-en')), findsOneWidget);
    });
  });

  group('routing from the entity detail tree (Story 2.18)', () {
    testWidgets(
        'opening an orig-only sub-entry navigates to UndeterminedLanguagePage, '
        'not EditorPage or PairedEditorPage', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        dirEntries: {
          '': const [RepoEntry(name: 'selena', path: 'selena', isDirectory: true)],
          'selena': const [
            RepoEntry(
                name: 'selena.md', path: 'selena/selena.md', isDirectory: false),
            RepoEntry(
                name: 'events', path: 'selena/events', isDirectory: true),
          ],
          'selena/events': const [
            RepoEntry(
                name: 'first-meeting.md',
                path: 'selena/events/first-meeting.md',
                isDirectory: false),
          ],
        },
        fileContents: {
          'selena/selena.md': '# Selena\n',
          'selena/events/first-meeting.md': '# First Meeting\n',
        },
      );
      final model = await loadLore(storage, '');
      final selena = model.entries.firstWhere((e) => e.id == 'selena/selena.md');

      await tester.pumpWidget(MaterialApp(
        home: EntityDetailPage(storage: storage, entry: selena, loreDir: ''),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('First Meeting'));
      await tester.pumpAndSettle();

      expect(find.byType(UndeterminedLanguagePage), findsOneWidget);
      expect(find.byType(EditorPage), findsNothing);
      expect(find.byType(PairedEditorPage), findsNothing);
    });

    testWidgets(
        'opening the entity card itself (an entity-folder card, AC6) never '
        'reaches UndeterminedLanguagePage — it is not a LoreItem, so it '
        'never enters _openItem at all', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        dirEntries: {
          '': const [RepoEntry(name: 'selena', path: 'selena', isDirectory: true)],
          'selena': const [
            RepoEntry(
                name: 'selena.md', path: 'selena/selena.md', isDirectory: false),
          ],
        },
        fileContents: {'selena/selena.md': '# Selena\n'},
      );
      final model = await loadLore(storage, '');
      final selena = model.entries.firstWhere((e) => e.id == 'selena/selena.md');

      await tester.pumpWidget(MaterialApp(
        home: EntityDetailPage(storage: storage, entry: selena, loreDir: ''),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('entity-card')));
      await tester.pumpAndSettle();

      expect(find.byType(EditorPage), findsOneWidget);
      expect(find.byType(UndeterminedLanguagePage), findsNothing);
    });
  });
}
