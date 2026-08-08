import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/app/editor_page.dart' show kDirtyIndicatorKey;
import 'package:lore_and_story/app/paired_editor_page.dart';
import 'package:lore_and_story/lore/lore.dart';

import '../fakes.dart';
import 'editor_test_helpers.dart';

/// A RU/EN paired sub-entry (`events/scene.ru.md` + `events/scene.en.md`).
LoreItem pairItem() => const LoreItem(
      id: 'events/scene',
      title: 'Сцена — Scene',
      group: 'events',
      passage: null,
      langs: {
        'ru': LoreLang(
            file: 'events/scene.ru.md',
            relDir: 'events',
            title: 'Сцена',
            text: '# Сцена\n'),
        'en': LoreLang(
            file: 'events/scene.en.md',
            relDir: 'events',
            title: 'Scene',
            text: '# Scene\n'),
      },
    );

FakeRepoStorage pairStorage() => FakeRepoStorage(
      '/repo',
      fileContents: {
        'events/scene.ru.md': '# Сцена\n',
        'events/scene.en.md': '# Scene\n',
      },
    );

Future<void> pumpPaired(
  WidgetTester tester,
  FakeRepoStorage storage,
  LoreItem item, {
  String loreDir = '',
  AiClient? aiClient,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: PairedEditorPage(
      storage: storage,
      item: item,
      loreDir: loreDir,
      aiClient: aiClient ?? FakeAiClient(),
    ),
  ));
  await tester.pumpAndSettle();
}

/// A lone RU sub-entry with NO `.en.md` — the translation candidate (FR13).
LoreItem translationItem() => const LoreItem(
      id: 'events/scene',
      title: 'Сцена',
      group: 'events',
      passage: null,
      langs: {
        'ru': LoreLang(
            file: 'events/scene.ru.md',
            relDir: 'events',
            title: 'Сцена',
            text: '# Сцена\n'),
      },
    );

FakeRepoStorage translationStorage() => FakeRepoStorage(
      '/repo',
      fileContents: {'events/scene.ru.md': '# Сцена\n'},
    );

void main() {
  group('create a translation from a missing EN (Story 2.9)', () {
    testWidgets('opens with RU (default) and an empty EN tab — no load error',
        (tester) async {
      await pumpPaired(tester, translationStorage(), translationItem());
      expect(find.text('RU'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      // The EN file doesn't exist yet: it opens as an empty edit surface, not
      // the "Could not open this file" error.
      expect(find.textContaining('Could not open'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('editing the empty EN tab and saving CREATES only .en.md '
        '(a create, never a merge; RU untouched)', (tester) async {
      final storage = translationStorage();
      await pumpPaired(tester, storage, translationItem());

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      // createIfMissing opens the empty EN tab in edit mode directly.
      await tester.enterText(find.byType(TextField), '# Scene\n');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();

      // Only the derived .en.md is written; the .ru.md is never touched and no
      // combined/base path is ever written.
      expect(storage.writeCalls, [('events/scene.en.md', '# Scene\n')]);
    });

    testWidgets('an unedited empty EN tab creates nothing (save disabled)',
        (tester) async {
      final storage = translationStorage();
      await pumpPaired(tester, storage, translationItem());

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();

      // Save is disabled with nothing dirty.
      final saveButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.save_outlined),
          matching: find.byType(IconButton),
        ),
      );
      expect(saveButton.onPressed, isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(storage.writeCalls, isEmpty);
    });
  });

  group('AI translate action (Story 4.3)', () {
    testWidgets(
        'Translate is visible only on the RU→EN synthetic tab — not the RU '
        'tab, not an already-paired item, not the mirrored EN→RU synthetic '
        'tab (AC5)', (tester) async {
      await pumpPaired(tester, translationStorage(), translationItem());
      expect(find.byKey(const Key('translate-action')), findsNothing,
          reason: 'RU is the default active tab');

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('translate-action')), findsOneWidget);
    });

    testWidgets('Translate never appears for an already-paired RU/EN item',
        (tester) async {
      await pumpPaired(tester, pairStorage(), pairItem());
      expect(find.byKey(const Key('translate-action')), findsNothing);
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('translate-action')), findsNothing);
    });

    testWidgets(
        'Translate never appears on the mirrored EN→RU synthetic tab '
        '(Story 2.18\'s case — FR21 is RU→EN only, AC5)', (tester) async {
      const item = LoreItem(
        id: 'events/scene',
        title: 'Scene',
        group: 'events',
        passage: null,
        langs: {
          'en': LoreLang(
              file: 'events/scene.en.md',
              relDir: 'events',
              title: 'Scene',
              text: '# Scene\n'),
        },
      );
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'events/scene.en.md': '# Scene\n'},
      );
      await pumpPaired(tester, storage, item);
      // The synthetic RU tab is the default active tab here.
      expect(find.byKey(const Key('translate-action')), findsNothing);
    });

    testWidgets('Translate is disabled when the RU buffer is blank (AC8)',
        (tester) async {
      const item = LoreItem(
        id: 'events/scene',
        title: 'Сцена',
        group: 'events',
        passage: null,
        langs: {
          'ru': LoreLang(
              file: 'events/scene.ru.md',
              relDir: 'events',
              title: 'Сцена',
              text: '   \n'),
        },
      );
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'events/scene.ru.md': '   \n'},
      );
      await pumpPaired(tester, storage, item);
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();

      final button =
          tester.widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(button.onPressed, isNull);
    });

    testWidgets(
        'confirming populates the EN buffer and marks it dirty, without '
        'writing anything to disk (AC3, AC4)', (tester) async {
      final storage = translationStorage();
      final aiClient =
          FakeAiClient(response: '# Scene\n\nTranslated prose.');
      await pumpPaired(tester, storage, translationItem(), aiClient: aiClient);

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      // Not pumpAndSettle: the AppBar spinner (_translating) animates
      // continuously for as long as the preview sheet is open awaiting the
      // user, so "settled" never occurs until after Confirm/Cancel — a
      // bounded pump lets the sheet's own open transition finish instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, '# Scene\n\nTranslated prose.'),
        findsOneWidget,
      );
      expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);
      expect(storage.writeCalls, isEmpty,
          reason: 'AC3 — only the buffer changes; a save is still explicit');
    });

    testWidgets('cancelling the preview leaves the EN tab untouched (AC2)',
        (tester) async {
      final aiClient = FakeAiClient(response: 'should never appear');
      await pumpPaired(tester, translationStorage(), translationItem(),
          aiClient: aiClient);

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('should never appear'), findsNothing);
      expect(find.byKey(kDirtyIndicatorKey), findsNothing);
    });

    testWidgets(
        'a failing AI call shows a SnackBar, leaves EN empty, and stays '
        'retryable (AC6)', (tester) async {
      final aiClient = FakeAiClient(error: const AiServerException('boom'));
      await pumpPaired(tester, translationStorage(), translationItem(),
          aiClient: aiClient);

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      // Not pumpAndSettle: the AppBar spinner (_translating) animates
      // continuously for as long as the preview sheet is open awaiting the
      // user, so "settled" never occurs until after Confirm/Cancel — a
      // bounded pump lets the sheet's own open transition finish instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('boom'), findsOneWidget);
      expect(find.byKey(kDirtyIndicatorKey), findsNothing);

      final button =
          tester.widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(button.onPressed, isNotNull,
          reason: 'must be retryable after a failure');
    });

    testWidgets(
        '(review fix) translates the RU tab\'s live unsaved buffer, not the '
        'file on disk (Design decision 3)', (tester) async {
      final storage = translationStorage();
      final aiClient = FakeAiClient(response: 'ok');
      await pumpPaired(tester, storage, translationItem(), aiClient: aiClient);

      // Edit the RU buffer without saving — disk still holds the original.
      await enterEditMode(tester);
      await tester.enterText(find.byType(TextField), '# Сцена v2\nНовый текст.\n');
      await tester.pump();

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.userContent, '# Сцена v2\nНовый текст.\n');
      expect(storage.writeCalls, isEmpty, reason: 'the RU edit was never saved');
    });

    testWidgets(
        '(review fix) translate, then Save actually writes .en.md with the '
        'translated content (AC4)', (tester) async {
      final storage = translationStorage();
      final aiClient = FakeAiClient(response: '# Scene\n\nTranslated prose.');
      await pumpPaired(tester, storage, translationItem(), aiClient: aiClient);

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();

      expect(storage.writeCalls,
          [('events/scene.en.md', '# Scene\n\nTranslated prose.')]);
    });

    testWidgets(
        '(review fix) translating over a manually-edited EN draft asks '
        'before overwriting it — "Keep editing" preserves the draft',
        (tester) async {
      final storage = translationStorage();
      final aiClient = FakeAiClient(response: 'Translated.');
      await pumpPaired(tester, storage, translationItem(), aiClient: aiClient);

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My own draft');
      await tester.pump();

      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      // Not pumpAndSettle: _translating is still true (the overwrite dialog
      // appears before the spinner clears) — same class of continuous-
      // animation deadlock as the context-preview sheet itself.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'My own draft'), findsOneWidget);
      expect(find.text('Translated.'), findsNothing);
    });

    testWidgets(
        '(review fix) confirming the overwrite replaces the manual draft '
        'with the translation', (tester) async {
      final storage = translationStorage();
      final aiClient = FakeAiClient(response: 'Translated.');
      await pumpPaired(tester, storage, translationItem(), aiClient: aiClient);

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My own draft');
      await tester.pump();

      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Translated.'), findsOneWidget);
    });

    testWidgets(
        '(review fix) backing out while a translation is in flight is '
        'blocked, not silently discarded', (tester) async {
      final storage = translationStorage();
      final aiClient = _ControllableAiClient();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) => PairedEditorPage(
                    storage: storage,
                    item: translationItem(),
                    loreDir: '',
                    aiClient: aiClient),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Translation is now in flight — the controllable stream never
      // completes until we tell it to.

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Still on the paired editor — the pop was blocked.
      expect(find.byKey(const Key('translate-action')), findsOneWidget);
      expect(find.text('A translation is still in progress.'), findsOneWidget);

      aiClient.complete('# Scene\n\nDone.');
      await tester.pumpAndSettle();
    });
  });

  testWidgets('shows [RU][EN] tabs with RU selected by default (FR12)',
      (tester) async {
    await pumpPaired(tester, pairStorage(), pairItem());
    expect(find.text('RU'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    // Both tabs' editors are alive (kept so a switch never reloads).
    expect(find.byType(TabBar), findsOneWidget);
  });

  testWidgets('saving the RU tab writes only the .ru.md file (FR14/AD-6)',
      (tester) async {
    final storage = pairStorage();
    await pumpPaired(tester, storage, pairItem());

    await enterEditMode(tester); // active tab (RU) → editor
    await tester.enterText(find.byType(TextField), '# Сцена edited\n');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();

    expect(storage.writeCalls, [('events/scene.ru.md', '# Сцена edited\n')]);
  });

  testWidgets('saving the EN tab writes only the .en.md file (FR14/AD-6)',
      (tester) async {
    final storage = pairStorage();
    await pumpPaired(tester, storage, pairItem());

    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    await enterEditMode(tester); // active tab (EN) → editor
    await tester.enterText(find.byType(TextField), '# Scene edited\n');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.save_outlined));
    await tester.pumpAndSettle();

    expect(storage.writeCalls, [('events/scene.en.md', '# Scene edited\n')]);
  });

  testWidgets('switching tabs preserves each tab\'s unsaved edits (AD-10)',
      (tester) async {
    await pumpPaired(tester, pairStorage(), pairItem());

    // Edit RU (do not save).
    await enterEditMode(tester);
    await tester.enterText(find.byType(TextField), '# RU work\n');
    await tester.pump();

    // Switch to EN and back.
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RU'));
    await tester.pumpAndSettle();

    // RU still shows the unsaved edit (kept alive, never reloaded).
    expect(find.widgetWithText(TextField, '# RU work\n'), findsOneWidget);
  });

  testWidgets('backing out saves a dirty tab; never writes a merged file',
      (tester) async {
    final storage = pairStorage();
    // Push the paired editor onto a route so there is a back button to pop.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => PairedEditorPage(
                  storage: storage,
                  item: pairItem(),
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
    await tester.enterText(find.byType(TextField), '# Сцена v2\n');
    await tester.pump();

    // Pop the route (back) — the dirty RU tab is saved.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(storage.writeCalls, [('events/scene.ru.md', '# Сцена v2\n')]);
    // Never a combined/base path.
    expect(
      storage.writeCalls.every((c) => c.$1.endsWith('.ru.md') || c.$1.endsWith('.en.md')),
      isTrue,
    );
  });

  testWidgets('backgrounding saves every dirty tab to its own file',
      (tester) async {
    final storage = pairStorage();
    await pumpPaired(tester, storage, pairItem());

    // Dirty the RU tab.
    await enterEditMode(tester);
    await tester.enterText(find.byType(TextField), '# RU bg\n');
    await tester.pump();
    // Dirty the EN tab.
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    await enterEditMode(tester);
    await tester.enterText(find.byType(TextField), '# EN bg\n');
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(storage.writeCalls, containsAll([
      ('events/scene.ru.md', '# RU bg\n'),
      ('events/scene.en.md', '# EN bg\n'),
    ]));
  });

  group('Lint action (Story 3.1)', () {
    testWidgets('lints the active tab only — a leaked-twee error on the RU '
        'tab shows; switching to EN (clean) and re-linting shows none',
        (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {
          'events/scene.ru.md': '# Сцена\n<<if \$x>>\n',
          'events/scene.en.md': '# Scene\n',
        },
      );
      await pumpPaired(tester, storage, pairItem());

      // RU is the default active tab (FR12) and has a leaked-twee error.
      await tester.tap(find.byKey(const Key('lint-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lint-finding-0')), findsOneWidget);

      await tester.tap(find.byKey(const Key('lint-finding-0')));
      await tester.pumpAndSettle();

      // Switch to EN (clean) and lint again — targets the now-active tab.
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lint-action')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lint-no-issues')), findsOneWidget);
    });
  });
}

/// An [AiClient] whose `sendMessage` stream stays open until [complete] is
/// called — lets a test hold a translation "in flight" deliberately, unlike
/// [FakeAiClient] which always resolves immediately.
class _ControllableAiClient implements AiClient {
  final _controller = StreamController<String>();

  @override
  Stream<String> sendMessage(AiRequest request) => _controller.stream;

  void complete(String text) {
    _controller
      ..add(text)
      ..close();
  }
}
