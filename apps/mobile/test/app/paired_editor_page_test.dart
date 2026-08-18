import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/app/editor_page.dart' show kDirtyIndicatorKey;
import 'package:lore_and_story/app/paired_editor_page.dart';
import 'package:lore_and_story/lore/lore.dart';

import '../fakes.dart';
import 'editor_test_helpers.dart';

/// The rendered text of the open context preview's `AI instructions` section
/// (index 0, per `context_preview.dart`) — used to pin down which
/// [TranslationDirection] actually fired, not just which source text was
/// read (Review fix — a direction-inversion bug could still pass a
/// source-only assertion).
String _previewInstructionsText(WidgetTester tester) => tester
    .widget<SelectableText>(find.descendant(
      of: find.byKey(const Key('context-preview-section-0')),
      matching: find.byType(SelectableText),
    ))
    .data ??
    '';

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
        '(Review decision, 2026-08-08) Translate is visible-but-disabled on '
        'the RU tab of the RU→EN create case (its EN counterpart is a blank '
        'synthetic tab) and enabled once viewing the EN tab', (tester) async {
      await pumpPaired(tester, translationStorage(), translationItem());
      final ruButton = tester
          .widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(ruButton.onPressed, isNull,
          reason: 'RU is the default active tab; its EN counterpart is a '
              'blank synthetic tab — visible (AC8), but nothing to '
              'translate from yet');

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      final enButton = tester
          .widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(enButton.onPressed, isNotNull,
          reason: 'RU has content to translate from');
    });

    testWidgets(
        '(Story 4.5/FR30) Translate appears on BOTH tabs of a real, '
        'already-paired item with content on both sides — superseding the '
        'old "never appears for an already-paired item" restriction',
        (tester) async {
      await pumpPaired(tester, pairStorage(), pairItem());
      expect(find.byKey(const Key('translate-action')), findsOneWidget,
          reason: 'RU is the default active tab; EN has content to '
              'translate from');
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('translate-action')), findsOneWidget,
          reason: 'RU has content to translate from');
    });

    testWidgets(
        '(Story 4.5/FR30) tapping Translate on each tab of an already-paired '
        'item fires the correct direction — RU→EN on the EN tab, EN→RU on '
        'the RU tab', (tester) async {
      final storage = pairStorage();
      final aiClient = FakeAiClient(response: 'Translated.');
      await pumpPaired(tester, storage, pairItem(), aiClient: aiClient);

      // RU is the default active tab: tapping Translate here runs EN→RU,
      // sourced from the live EN buffer. The RU tab already has saved
      // content, so the overwrite-confirm dialog (AC2) appears too.
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(aiClient.requests, isEmpty,
          reason: 'nothing is sent before the preview is confirmed (AD-11)');
      // Review fix: pin down the DIRECTION, not just the source text — a
      // direction-inversion bug would still pass a source-only assertion.
      expect(_previewInstructionsText(tester),
          contains('translating an English'),
          reason: 'RU is the target, so this must be EN→RU');
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(aiClient.requests.single.userContent, '# Scene\n');
      expect(find.widgetWithText(TextField, 'Translated.'), findsOneWidget,
          reason: 'the result landed on the active (RU) tab');

      // Switch to EN and translate from RU (now edited to a distinct value,
      // proving the source read is live, not a stale snapshot). EN also
      // already has saved content, so the overwrite confirm fires again.
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_previewInstructionsText(tester), contains('translating a Russian'),
          reason: 'EN is the target, so this must be RU→EN');
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(aiClient.requests.last.userContent, 'Translated.',
          reason: 'RU→EN translated from the RU tab\'s just-updated buffer');
    });

    testWidgets(
        '(Story 4.5/FR30) Translate is now available on Story 2.18\'s '
        'mirrored synthetic RU tab (EN→RU, a create) — Story 4.3\'s old AC5 '
        'restriction against it is superseded', (tester) async {
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
      final aiClient = FakeAiClient(response: '# Сцена\n\nПеревод.');
      await pumpPaired(tester, storage, item, aiClient: aiClient);

      // EN is the default active tab here; its counterpart (the synthetic RU
      // tab) is still empty, so Translate is visible (AC8) but disabled.
      final enButton = tester
          .widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(enButton.onPressed, isNull);

      await tester.tap(find.text('RU'));
      await tester.pumpAndSettle();
      final ruButton = tester
          .widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(ruButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_previewInstructionsText(tester), contains('translating an English'),
          reason: 'EN→RU-worded instructions, not the RU→EN default');
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.userContent, '# Scene\n');
      expect(find.widgetWithText(TextField, '# Сцена\n\nПеревод.'),
          findsOneWidget,
          reason: 'the RU tab (a create) received the translated result');
      expect(storage.writeCalls, isEmpty,
          reason: 'only the buffer changes; a save is still explicit');
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
        '(Story 4.5) Translate is disabled when the EN buffer is blank — the '
        'mirror of AC8 for the EN→RU direction', (tester) async {
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
              text: '   \n'),
        },
      );
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {'events/scene.en.md': '   \n'},
      );
      await pumpPaired(tester, storage, item);
      // EN is the default active tab; its counterpart is the synthetic RU
      // tab (visible per AC8, but blank) — disabled on both tabs.
      final enButton = tester
          .widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(enButton.onPressed, isNull);
      await tester.tap(find.text('RU'));
      await tester.pumpAndSettle();
      final ruButton = tester
          .widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(ruButton.onPressed, isNull);
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
      final aiClient = ControllableAiClient();
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

    testWidgets(
        '(Story 4.5) translates the EN tab\'s live unsaved buffer, not the '
        'file on disk — the EN→RU mirror of Design decision 3', (tester) async {
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
      final aiClient = FakeAiClient(response: 'ok');
      await pumpPaired(tester, storage, item, aiClient: aiClient);

      // Edit the EN buffer without saving — disk still holds the original.
      await enterEditMode(tester);
      await tester.enterText(find.byType(TextField), '# Scene v2\nNew text.\n');
      await tester.pump();

      await tester.tap(find.text('RU'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(aiClient.requests.single.userContent, '# Scene v2\nNew text.\n');
      expect(storage.writeCalls, isEmpty, reason: 'the EN edit was never saved');
    });

    testWidgets(
        '(Story 4.5) translate into the mirrored RU tab, then Save actually '
        'writes .ru.md — the EN→RU mirror of AC4', (tester) async {
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
      final aiClient = FakeAiClient(response: '# Сцена\n\nПеревод.');
      await pumpPaired(tester, storage, item, aiClient: aiClient);

      await tester.tap(find.text('RU'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save_outlined));
      await tester.pumpAndSettle();

      expect(storage.writeCalls,
          [('events/scene.ru.md', '# Сцена\n\nПеревод.')]);
    });

    testWidgets(
        '(Story 4.5) a failing EN→RU AI call shows a SnackBar and stays '
        'retryable — the mirror of AC6', (tester) async {
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
      final aiClient = FakeAiClient(error: const AiServerException('boom'));
      await pumpPaired(tester, storage, item, aiClient: aiClient);

      await tester.tap(find.text('RU'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('boom'), findsOneWidget);

      final button =
          tester.widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(button.onPressed, isNotNull,
          reason: 'must be retryable after a failure');
    });

    group('(Story 4.5/AC2) confirm-before-overwrite fires for SAVED, '
        'non-dirty target content, not just a dirty draft', () {
      testWidgets(
          'requesting a translate into a clean, already-saved target still '
          'asks to confirm — "Keep editing" preserves the saved content',
          (tester) async {
        final storage = pairStorage();
        final aiClient = FakeAiClient(response: 'Translated.');
        await pumpPaired(tester, storage, pairItem(), aiClient: aiClient);

        // EN tab: loaded from disk, never edited — not dirty.
        await tester.tap(find.text('EN'));
        await tester.pumpAndSettle();
        await enterEditMode(tester);
        expect(find.byKey(kDirtyIndicatorKey), findsNothing,
            reason: 'the target must be clean, not a dirty draft, to prove '
                'the guard is content-based, not dirty-based');

        await tester.tap(find.byKey(const Key('translate-action')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const Key('context-preview-confirm')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();

        // The saved content is untouched — the translation never landed.
        expect(find.widgetWithText(TextField, '# Scene\n'), findsOneWidget);
        expect(find.text('Translated.'), findsNothing);
      });

      testWidgets(
          'confirming the overwrite replaces the clean, already-saved target '
          'with the translation', (tester) async {
        final storage = pairStorage();
        final aiClient = FakeAiClient(response: 'Translated.');
        await pumpPaired(tester, storage, pairItem(), aiClient: aiClient);

        await tester.tap(find.text('EN'));
        await tester.pumpAndSettle();
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
        expect(storage.writeCalls, isEmpty,
            reason: 'only the buffer changes; a save is still explicit');
      });

      testWidgets(
          '(Review fix) an unsaved DELETION (dirty, but blank text) also '
          'asks to confirm — the guard is isDirty OR non-blank text, not '
          'non-blank text alone', (tester) async {
        final storage = pairStorage();
        final aiClient = FakeAiClient(response: 'Translated.');
        await pumpPaired(tester, storage, pairItem(), aiClient: aiClient);

        // Delete the EN tab's saved content without saving — dirty, but the
        // live buffer is now blank.
        await tester.tap(find.text('EN'));
        await tester.pumpAndSettle();
        await enterEditMode(tester);
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(find.byKey(kDirtyIndicatorKey), findsOneWidget);

        await tester.tap(find.byKey(const Key('translate-action')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const Key('context-preview-confirm')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Before the fix, `targetState.text.trim().isNotEmpty` alone would
        // be false here (blank buffer) and the deletion would be silently
        // overwritten with no confirmation.
        expect(find.text('Discard changes?'), findsOneWidget,
            reason: 'a dirty-but-blank target must still be protected, not '
                'silently overwritten');
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextField, 'Translated.'), findsNothing,
            reason: 'the deletion is preserved, not silently overwritten');
      });
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

  group('Review action (Story 4.6)', () {
    testWidgets(
        'available and working on both tabs of a real pair — not gated by '
        'a counterpart existing, unlike Translate', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {
          'events/scene.ru.md': '# Сцена\nRU line.\n',
          'events/scene.en.md': '# Scene\nEN line.\n',
        },
      );
      final aiClient = FakeAiClient(response: '[]');
      await pumpPaired(tester, storage, pairItem(), aiClient: aiClient);

      expect(find.byKey(const Key('review-action')), findsOneWidget);

      // RU is the default active tab (FR12).
      await tester.tap(find.byKey(const Key('review-action')));
      // Not pumpAndSettle: the AppBar spinner (_reviewing) animates
      // continuously while the preview sheet is open awaiting the user.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('grammar-no-issues')), findsOneWidget);
      expect(aiClient.requests.single.userContent, contains('RU line.'));

      // Dismiss the "no issues" sheet (nothing auto-pops it, unlike tapping
      // a finding) before interacting with the AppBar again.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Switch to EN and review again — targets the now-active tab, with no
      // counterpart-visibility gating (unlike Translate's `_canShowTranslate`).
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-action')), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('grammar-no-issues')), findsOneWidget);
      expect(aiClient.requests, hasLength(2));
      expect(aiClient.requests.last.userContent, contains('EN line.'));
    });

    testWidgets(
        'switching tabs mid-request bails rather than showing a panel for a '
        'buffer that is no longer on screen (mirrors the Lint action guard)',
        (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {
          'events/scene.ru.md': '# Сцена\n',
          'events/scene.en.md': '# Scene\n',
        },
      );
      final aiClient = ControllableAiClient();
      await pumpPaired(tester, storage, pairItem(), aiClient: aiClient);

      // RU is the default active tab.
      await tester.tap(find.byKey(const Key('review-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      // Not pumpAndSettle: _reviewing stays true (the AppBar spinner
      // animates continuously) until the in-flight request resolves below.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to EN before the RU-tab request resolves.
      await tester.tap(find.text('EN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      aiClient.complete('[]');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('grammar-no-issues')), findsNothing,
          reason: 'the RU-tab request landed after the author switched to '
              'EN — it must not pop up a panel for a tab no longer on '
              'screen');
      // Review fix: a completed (and billed) review must never vanish
      // silently — a SnackBar explains why no panel appeared.
      expect(find.text('Review ready, but that tab is no longer open — '
          'try again.'), findsOneWidget);
    });

    testWidgets(
        '(Review fix) the Review action is disabled when the active tab\'s '
        'buffer is blank', (tester) async {
      final storage = FakeRepoStorage(
        '/repo',
        fileContents: {
          'events/scene.ru.md': '   \n',
          'events/scene.en.md': '# Scene\n',
        },
      );
      await pumpPaired(tester, storage, pairItem());

      final button =
          tester.widget<IconButton>(find.byKey(const Key('review-action')));
      expect(button.onPressed, isNull);
    });

    testWidgets(
        '(Review fix) backing out while a review is in flight is blocked, '
        'not silently discarded — mirrors the Translate PopScope guard',
        (tester) async {
      final storage = pairStorage();
      final aiClient = ControllableAiClient();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) => PairedEditorPage(
                    storage: storage,
                    item: pairItem(),
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

      await tester.tap(find.byKey(const Key('review-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The review is now in flight.

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Still on the paired editor — the pop was blocked.
      expect(find.byKey(const Key('review-action')), findsOneWidget);
      expect(find.text('A review is still in progress.'), findsOneWidget);

      aiClient.complete('[]');
      await tester.pumpAndSettle();
    });

    testWidgets(
        '(Review fix) Translate is disabled while a review is in flight',
        (tester) async {
      final storage = pairStorage();
      final aiClient = ControllableAiClient();
      await pumpPaired(tester, storage, pairItem(), aiClient: aiClient);

      // Start a review on the active (RU) tab.
      await tester.tap(find.byKey(const Key('review-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Translate is disabled while the review is in flight.
      final translateButton = tester
          .widget<IconButton>(find.byKey(const Key('translate-action')));
      expect(translateButton.onPressed, isNull);

      aiClient.complete('[]');
      await tester.pumpAndSettle();
      // Dismiss the "no issues" sheet before the test ends (nothing
      // auto-pops it, unlike tapping a finding).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets(
        '(Review fix) Review is disabled while a translate is in flight',
        (tester) async {
      // Translate into the blank, create-only EN tab, so no
      // overwrite-confirm dialog complicates the assertion.
      final aiClient = ControllableAiClient();
      await pumpPaired(tester, translationStorage(), translationItem(),
          aiClient: aiClient);
      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('translate-action')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('context-preview-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final reviewButton =
          tester.widget<IconButton>(find.byKey(const Key('review-action')));
      expect(reviewButton.onPressed, isNull);

      aiClient.complete('Translated.');
      await tester.pumpAndSettle();
    });
  });
}
