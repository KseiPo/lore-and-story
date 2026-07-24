import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/app.dart';
import 'package:lore_and_story/storage/storage.dart';

import 'fakes.dart';

// Home-orchestration states (grant → choose-root → ready), the "Open a file"
// raw-picker fallback, conflict surfacing, rescan-on-refresh/resume, and the
// error state. The Categories → Entities browse itself is covered in
// test/app/browse_test.dart.
void main() {
  testWidgets('shows grant-access state when permission is not granted',
      (tester) async {
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(),
      permission: FakeStoragePermission(granted: false),
      storageFactory: (root) => FakeRepoStorage(root),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Grant access'), findsOneWidget);
    expect(find.text('Choose repo folder'), findsNothing);
  });

  testWidgets('shows choose-folder state when granted but no root stored',
      (tester) async {
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => FakeRepoStorage(root),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Choose repo folder'), findsOneWidget);
  });

  testWidgets(
      'full loop: Open a file -> pick from the picker -> the editor opens it (AC5)',
      (tester) async {
    // The picked folder IS the lore folder, so its files sit at the root.
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'frank.md', path: 'frank.md', isDirectory: false),
      ],
      fileContents: {'frank.md': '# Frank\n\n**bold**\n'},
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open a file'));
    await tester.pumpAndSettle();

    // Picker opened at the repo root (the lore folder itself).
    await tester.tap(find.text('frank.md'));
    await tester.pumpAndSettle();

    // The editor opened with the file's raw content.
    expect(find.widgetWithText(TextField, '# Frank\n\n**bold**\n'), findsOneWidget);
  });

  testWidgets('surfaces sync-conflict copies found by the walk (FR17)',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'lore', path: 'lore', isDirectory: true),
      ],
      dirEntries: {
        'lore': const [
          RepoEntry(name: 'frank.md', path: 'lore/frank.md', isDirectory: false),
          RepoEntry(
            name: 'frank.sync-conflict-20240612-093000-K3F9AAA.md',
            path: 'lore/frank.sync-conflict-20240612-093000-K3F9AAA.md',
            isDirectory: false,
          ),
        ],
      },
      fileContents: {'lore/frank.md': '# Frank\n'},
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conflict-banner')), findsOneWidget);
    expect(find.textContaining('1 sync-conflict copy —'), findsOneWidget);
    // The conflict copy is surfaced, not counted as a lore entity.
    expect(find.text('1 lore entity'), findsOneWidget);
  });

  testWidgets('Refresh re-scans from disk and reflects new state (FR3)',
      (tester) async {
    // A mutable listing lets the test change the repo between scans, proving
    // the refresh performs a real walk rather than reusing a cached model.
    final loreDir = <RepoEntry>[
      const RepoEntry(name: 'frank.md', path: 'lore/frank.md', isDirectory: false),
    ];
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'lore', path: 'lore', isDirectory: true),
      ],
      dirEntries: {'lore': loreDir},
      fileContents: {'lore/frank.md': '# Frank\n'},
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conflict-banner')), findsNothing);

    // The syncer drops a conflict copy while the app is open.
    loreDir.add(const RepoEntry(
      name: 'frank.sync-conflict-20240612-093000-K3F9AAA.md',
      path: 'lore/frank.sync-conflict-20240612-093000-K3F9AAA.md',
      isDirectory: false,
    ));

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conflict-banner')), findsOneWidget);
    expect(find.textContaining('1 sync-conflict copy —'), findsOneWidget);
  });

  testWidgets('resume re-scans from disk and reflects new state (FR3)',
      (tester) async {
    final loreDir = <RepoEntry>[
      const RepoEntry(name: 'frank.md', path: 'lore/frank.md', isDirectory: false),
    ];
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'lore', path: 'lore', isDirectory: true),
      ],
      dirEntries: {'lore': loreDir},
      fileContents: {'lore/frank.md': '# Frank\n'},
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conflict-banner')), findsNothing);

    loreDir.add(const RepoEntry(
      name: 'frank.sync-conflict-20240612-093000-K3F9AAA.md',
      path: 'lore/frank.sync-conflict-20240612-093000-K3F9AAA.md',
      isDirectory: false,
    ));

    // A lifecycle resume (not a button) must trigger the same rescan.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conflict-banner')), findsOneWidget);
  });

  testWidgets('a scan failure shows an error state with Retry, not a stuck spinner',
      (tester) async {
    // loreDir defaults to the repo root; loadLore('') walks it and listDir('')
    // throws (throwOnListDir), so an unexpected storage failure during a rescan
    // surfaces the error state instead of stranding a spinner.
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      throwOnListDir: true,
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
