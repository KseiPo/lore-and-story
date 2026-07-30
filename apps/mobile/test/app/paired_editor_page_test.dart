import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}) async {
  await tester.pumpWidget(MaterialApp(
    home: PairedEditorPage(storage: storage, item: item, loreDir: loreDir),
  ));
  await tester.pumpAndSettle();
}

void main() {
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
                  storage: storage, item: pairItem(), loreDir: ''),
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
}
