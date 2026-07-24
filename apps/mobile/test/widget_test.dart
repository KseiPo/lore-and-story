import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/app.dart';
import 'package:lore_and_story/storage/storage.dart';

import 'fakes.dart';

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

  testWidgets('shows the ready view (root + entries) when granted with a stored root',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
        RepoEntry(name: 'lore-story.json', path: 'lore-story.json', isDirectory: false),
      ],
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    expect(find.text('/storage/emulated/0/repo'), findsOneWidget);
    expect(find.text('characters'), findsOneWidget);
    expect(find.text('lore-story.json'), findsOneWidget);
  });

  testWidgets('hides Syncthing technical folders from the top-level entries',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: '.stfolder', path: '.stfolder', isDirectory: true),
        RepoEntry(name: '.stversions', path: '.stversions', isDirectory: true),
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
      ],
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    expect(find.text('characters'), findsOneWidget);
    expect(find.text('.stfolder'), findsNothing);
    expect(find.text('.stversions'), findsNothing);
  });

  testWidgets(
      'tapping a folder in the top-level entries opens the recursive picker',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
      ],
      dirEntries: {
        'characters': const [
          RepoEntry(
              name: 'selena.md', path: 'characters/selena.md', isDirectory: false),
        ],
      },
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();

    // Now inside the picker, rooted at 'characters' — its child is listed.
    expect(find.text('selena.md'), findsOneWidget);
  });

  testWidgets('tapping a file in the top-level entries opens it in the editor',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'frank.md', path: 'frank.md', isDirectory: false),
      ],
      fileContents: {'frank.md': '# Frank\n'},
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('frank.md'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '# Frank\n'), findsOneWidget);
  });

  testWidgets(
      '"Open a file" falls back to the true root when loreDir does not exist under it',
      (tester) async {
    // No 'lore-story.json' and no 'lore' entry in dirEntries -> loreDir
    // ('lore', the default) does not exist under this root (e.g. the user
    // pointed the repo root directly at their lore content folder).
    final storage = FakeRepoStorage(
      '/storage/emulated/0/mylore',
      entries: const [
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
      ],
      dirEntries: {
        'characters': const [
          RepoEntry(
              name: 'selena.md', path: 'characters/selena.md', isDirectory: false),
        ],
      },
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/mylore'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open a file'));
    await tester.pumpAndSettle();

    // Picker started at the true root ('') rather than the non-existent
    // 'lore' subfolder, so 'characters' is visible and navigable.
    expect(find.text('characters'), findsOneWidget);
  });

  testWidgets(
      'full loop: Open a file -> pick from the picker -> the editor opens it (AC5)',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'lore', path: 'lore', isDirectory: true),
      ],
      dirEntries: {
        'lore': const [
          RepoEntry(name: 'frank.md', path: 'lore/frank.md', isDirectory: false),
        ],
      },
      fileContents: {'lore/frank.md': '# Frank\n\n**bold**\n'},
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open a file'));
    await tester.pumpAndSettle();

    // Picker started at loreDir ('lore', which exists here).
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

  testWidgets('media/ is hidden from browsing (binary assets are not editable)',
      (tester) async {
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      entries: const [
        RepoEntry(name: 'media', path: 'media', isDirectory: true),
        RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
      ],
    );
    await tester.pumpWidget(LoreStoryApp(
      rootStore: FakeRepoRootStore(initial: '/storage/emulated/0/repo'),
      permission: FakeStoragePermission(granted: true),
      storageFactory: (root) => storage,
    ));
    await tester.pumpAndSettle();

    expect(find.text('characters'), findsOneWidget);
    expect(find.text('media'), findsNothing);
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
    final storage = FakeRepoStorage(
      '/storage/emulated/0/repo',
      // exists('') is true (root), but reading config/listing throws.
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
