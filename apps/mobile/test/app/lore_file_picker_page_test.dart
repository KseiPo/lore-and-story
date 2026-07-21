import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/app/lore_file_picker_page.dart';
import 'package:lore_and_story/storage/storage.dart';

import '../fakes.dart';

void main() {
  testWidgets('lists files and folders at the start path', (tester) async {
    final storage = FakeRepoStorage(
      '/repo',
      dirEntries: {
        'lore': const [
          RepoEntry(name: 'characters', path: 'lore/characters', isDirectory: true),
          RepoEntry(name: 'frank.md', path: 'lore/frank.md', isDirectory: false),
        ],
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: LoreFilePickerPage(storage: storage, startPath: 'lore'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('characters'), findsOneWidget);
    expect(find.text('frank.md'), findsOneWidget);
  });

  testWidgets('descending into a folder lists its children', (tester) async {
    final storage = FakeRepoStorage(
      '/repo',
      dirEntries: {
        'lore': const [
          RepoEntry(name: 'characters', path: 'lore/characters', isDirectory: true),
        ],
        'lore/characters': const [
          RepoEntry(name: 'selena.md', path: 'lore/characters/selena.md', isDirectory: false),
        ],
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: LoreFilePickerPage(storage: storage, startPath: 'lore'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();

    expect(find.text('selena.md'), findsOneWidget);
  });

  testWidgets('tapping a file pops with its repo-relative path', (tester) async {
    final storage = FakeRepoStorage(
      '/repo',
      dirEntries: {
        'lore': const [
          RepoEntry(name: 'frank.md', path: 'lore/frank.md', isDirectory: false),
        ],
      },
    );

    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            picked = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => LoreFilePickerPage(storage: storage, startPath: 'lore'),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('frank.md'));
    await tester.pumpAndSettle();

    expect(picked, 'lore/frank.md');
  });

  testWidgets('hides Syncthing technical folders at every level', (tester) async {
    final storage = FakeRepoStorage(
      '/repo',
      dirEntries: {
        'lore': const [
          RepoEntry(name: '.stfolder', path: 'lore/.stfolder', isDirectory: true),
          RepoEntry(name: '.stversions', path: 'lore/.stversions', isDirectory: true),
          RepoEntry(name: 'characters', path: 'lore/characters', isDirectory: true),
        ],
        'lore/characters': const [
          RepoEntry(name: '.stfolder', path: 'lore/characters/.stfolder', isDirectory: true),
          RepoEntry(
              name: 'selena.md', path: 'lore/characters/selena.md', isDirectory: false),
        ],
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: LoreFilePickerPage(storage: storage, startPath: 'lore'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('characters'), findsOneWidget);
    expect(find.text('.stfolder'), findsNothing);
    expect(find.text('.stversions'), findsNothing);

    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();

    expect(find.text('selena.md'), findsOneWidget);
    expect(find.text('.stfolder'), findsNothing);
  });

  testWidgets('hides every dot-prefixed entry, not just Syncthing folders',
      (tester) async {
    final storage = FakeRepoStorage(
      '/repo',
      dirEntries: {
        'lore': const [
          RepoEntry(name: '.stfolder', path: 'lore/.stfolder', isDirectory: true),
          RepoEntry(name: '.git', path: 'lore/.git', isDirectory: true),
          RepoEntry(name: '.gitignore', path: 'lore/.gitignore', isDirectory: false),
          RepoEntry(
              name: '.lore-tmp-x-1-2', path: 'lore/.lore-tmp-x-1-2', isDirectory: false),
          RepoEntry(name: 'frank.md', path: 'lore/frank.md', isDirectory: false),
        ],
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: LoreFilePickerPage(storage: storage, startPath: 'lore'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('frank.md'), findsOneWidget);
    expect(find.text('.stfolder'), findsNothing);
    expect(find.text('.git'), findsNothing);
    expect(find.text('.gitignore'), findsNothing);
    expect(find.text('.lore-tmp-x-1-2'), findsNothing);
  });

  testWidgets('the Up action returns to the parent level', (tester) async {
    final storage = FakeRepoStorage(
      '/repo',
      dirEntries: {
        'lore': const [
          RepoEntry(name: 'characters', path: 'lore/characters', isDirectory: true),
          RepoEntry(name: 'top.md', path: 'lore/top.md', isDirectory: false),
        ],
        'lore/characters': const [
          RepoEntry(
              name: 'selena.md', path: 'lore/characters/selena.md', isDirectory: false),
        ],
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: LoreFilePickerPage(storage: storage, startPath: 'lore'),
    ));
    await tester.pumpAndSettle();

    // No Up at the start level.
    expect(find.byIcon(Icons.arrow_upward), findsNothing);

    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();
    expect(find.text('selena.md'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(find.text('top.md'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
  });

  testWidgets('Up from a start path at the repo root returns to the root',
      (tester) async {
    // startPath '' exercises the _up() `i == -1` fallback branch.
    final storage = FakeRepoStorage(
      '/repo',
      dirEntries: {
        '': const [
          RepoEntry(name: 'characters', path: 'characters', isDirectory: true),
        ],
        'characters': const [
          RepoEntry(name: 'selena.md', path: 'characters/selena.md', isDirectory: false),
        ],
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: LoreFilePickerPage(storage: storage, startPath: ''),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('characters'));
    await tester.pumpAndSettle();
    expect(find.text('selena.md'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(find.text('characters'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
  });

  testWidgets('an empty/missing loreDir shows the empty state without throwing',
      (tester) async {
    final storage = FakeRepoStorage('/repo'); // 'lore' not in dirEntries at all
    await tester.pumpWidget(MaterialApp(
      home: LoreFilePickerPage(storage: storage, startPath: 'lore'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No files found.'), findsOneWidget);
  });
}
