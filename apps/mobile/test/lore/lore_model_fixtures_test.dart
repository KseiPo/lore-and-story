import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/lore/lore.dart';
import 'package:lore_and_story/storage/all_files_repo_storage.dart';

import 'normalize.dart';

/// Conformance of the Dart loader against the **shared golden fixtures** — the
/// operative contract between this port and the JS reference (`lib/lore.js`).
/// Mirrors `test/lore-model.test.js` on the JS side.
///
/// If a case fails: the bug is in the port. Do NOT regenerate the goldens —
/// a golden diff is a contract change, and this is a conformance exercise.
void main() {
  // Fixtures live at the repo root; `flutter test` runs with CWD = apps/mobile.
  final casesDir = Directory('../../test/fixtures/lore-model/cases');

  test('fixture cases are discoverable', () {
    expect(
      casesDir.existsSync(),
      isTrue,
      reason: 'missing fixtures dir: ${casesDir.path} '
          '(expected to run from apps/mobile)',
    );
  });

  final caseDirs = casesDir.existsSync()
      ? (casesDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <Directory>[];

  test('at least one fixture case exists', () {
    // An empty glob must not masquerade as a passing suite.
    expect(caseDirs, isNotEmpty, reason: 'no fixture cases found');
  });

  for (final dir in caseDirs) {
    final name = dir.path.split(Platform.pathSeparator).last;

    test('lore-model: $name', () async {
      final goldenFile = File('${dir.path}/expected.json');
      expect(
        goldenFile.existsSync(),
        isTrue,
        reason: 'missing golden: ${goldenFile.path}',
      );

      final storage = AllFilesRepoStorage(dir.path);
      final entries = (await loadLore(storage, 'lore')).entries;

      // Round-trip through JSON so both sides are plain Map/List/String types
      // and the matcher reports a structural diff.
      final actual = jsonDecode(jsonEncode(normalize(entries)));
      final expected = jsonDecode(await goldenFile.readAsString());

      expect(actual, equals(expected));
    });
  }

  // Integration tests for behavior not pinned by the shared fixtures. These use
  // a temp dir (not the shared cases) so they never touch the contract.
  group('loadLore (beyond fixtures)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('loadlore_int_');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<LoreModel> load() =>
        loadLore(AllFilesRepoStorage(tmp.path), 'lore');

    test('a card sitting directly in loreDir has category "general"', () async {
      File('${tmp.path}/lore/frank.md').createSync(recursive: true);
      File('${tmp.path}/lore/frank.md').writeAsStringSync('# Frank\n');

      final entries = (await load()).entries;
      expect(entries.map((e) => e.id), contains('frank.md'));
      final frank = entries.firstWhere((e) => e.id == 'frank.md');
      expect(frank.category, 'general');
    });

    test('a directory literally named <name>.md does not abort the load',
        () async {
      // selena/selena.md is a DIRECTORY (a pathological/synthetic case) — the
      // reference would EISDIR-throw on it; the port must skip it, not crash,
      // and still load the sibling simple entity.
      Directory('${tmp.path}/lore/characters/selena/selena.md')
          .createSync(recursive: true);
      File('${tmp.path}/lore/characters/frank.md')
          .writeAsStringSync('# Frank\n');

      final entries = (await load()).entries; // must not throw
      expect(entries.map((e) => e.id), contains('characters/frank.md'));
    });

    test('an unreadable-directory loreDir yields an empty model', () async {
      // No lore/ at all → [] (never throws).
      expect((await load()).entries, isEmpty);
    });
  });

  // Syncer-aware walk (Story 2.1b). Dart-only behavior — deliberately NOT in the
  // shared fixtures, since the JS reference has no syncer awareness (addendum §E).
  group('syncer-aware walk', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('loadlore_sync_');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<LoreModel> load() =>
        loadLore(AllFilesRepoStorage(tmp.path), 'lore');

    void write(String relPath, String content) {
      final f = File('${tmp.path}/$relPath');
      f.createSync(recursive: true);
      f.writeAsStringSync(content);
    }

    test('skips .stversions — its .md version copies never become entities',
        () async {
      // .stversions holds dated copies of real files; parsing them would create
      // bogus duplicate entities.
      write('lore/.stversions/frank~20240101-120000.md', '# Frank (old)\n');
      write('lore/characters/frank.md', '# Frank\n');

      final model = await load();
      expect(model.entries.map((e) => e.id), ['characters/frank.md']);
      expect(
        model.entries.map((e) => e.id).where((id) => id.contains('.stversions')),
        isEmpty,
      );
    });

    test('skips .stfolder and .stignore', () async {
      Directory('${tmp.path}/lore/.stfolder').createSync(recursive: true);
      write('lore/.stignore', 'some-pattern\n');
      write('lore/characters/frank.md', '# Frank\n');

      final model = await load();
      expect(model.entries.map((e) => e.id), ['characters/frank.md']);
      expect(model.conflicts, isEmpty);
    });

    test('a conflict copy is surfaced, not parsed as an entity', () async {
      write('lore/characters/frank.md', '# Frank\n');
      write(
        'lore/characters/frank.sync-conflict-20240612-093000-K3F9AAA.md',
        '# Frank (conflicted)\n',
      );

      final model = await load();
      // Not an entity...
      expect(model.entries.map((e) => e.id), ['characters/frank.md']);
      // ...but surfaced.
      expect(model.conflicts.length, 1);
      expect(model.conflicts.single.id,
          'characters/frank.sync-conflict-20240612-093000-K3F9AAA.md');
      expect(model.conflicts.single.relDir, 'characters');
    });

    test('a conflict copy of a sub-entry never enters the entity tree',
        () async {
      write('lore/characters/selena/selena.md', '# Selena\n');
      write('lore/characters/selena/events/dock.md', '# Dock\n');
      write(
        'lore/characters/selena/events/dock.sync-conflict-20240612-093000-K3F9AAA.md',
        '# Dock (conflicted)\n',
      );

      final model = await load();
      final selena = model.entries.single;

      // The conflict copy is absent from children[] and from the events items.
      expect(
        selena.children.map((c) => c.id),
        ['characters/selena/events/dock.md'],
      );
      final events = selena.tree!.children.single;
      expect(events.items.map((i) => i.id), ['events/dock']);

      // And it is surfaced instead.
      expect(model.conflicts.length, 1);
      expect(model.conflicts.single.relDir, 'characters/selena/events');
    });

    test('a normal repo produces no conflicts', () async {
      write('lore/characters/frank.md', '# Frank\n');
      expect((await load()).conflicts, isEmpty);
    });

    test('skips .git / .github (any dot-dir), not just the .st* names',
        () async {
      write('lore/.git/config.md', '# not lore\n');
      write('lore/.github/ISSUE_TEMPLATE.md', '# template\n');
      write('lore/characters/frank.md', '# Frank\n');

      final model = await load();
      expect(model.entries.map((e) => e.id), ['characters/frank.md']);
    });

    test('skips a dot-dir even when its name is uppercase (.StVersions)',
        () async {
      write('lore/.StVersions/frank~20240101-120000.md', '# old\n');
      write('lore/characters/frank.md', '# Frank\n');
      expect((await load()).entries.map((e) => e.id), ['characters/frank.md']);
    });

    test('detects an uppercased conflict-copy name', () async {
      write('lore/characters/frank.md', '# Frank\n');
      write(
        'lore/characters/FRANK.SYNC-CONFLICT-20240612-093000-K3F9AAA.MD',
        '# conflicted\n',
      );
      final model = await load();
      expect(model.entries.map((e) => e.id), ['characters/frank.md']);
      expect(model.conflicts.length, 1);
    });

    test('an authored file merely containing ".sync-conflict-" is NOT a conflict',
        () async {
      // Anchored detection: no date/time, so this is a real entity, not junk.
      write('lore/notes/troubleshooting.sync-conflict-recovery.md', '# How to\n');

      final model = await load();
      expect(model.conflicts, isEmpty);
      expect(
        model.entries.map((e) => e.id),
        contains('notes/troubleshooting.sync-conflict-recovery.md'),
      );
    });

    test('a conflict copy at the lore root has relDir "." (matches LoreEntry)',
        () async {
      write('lore/frank.md', '# Frank\n');
      write('lore/frank.sync-conflict-20240612-093000-K3F9AAA.md', '# c\n');

      final c = (await load()).conflicts.single;
      expect(c.relDir, '.');
      expect(c.id, 'frank.sync-conflict-20240612-093000-K3F9AAA.md');
    });

    test('conflicts come back sorted by id (deterministic across runs)',
        () async {
      write('lore/frank.md', '# Frank\n');
      // Written out of order; expect sorted output.
      write('lore/zed.sync-conflict-20240101-000000-B.md', '# z\n');
      write('lore/aaa.sync-conflict-20240101-000000-A.md', '# a\n');
      write('lore/mid.sync-conflict-20240101-000000-M.md', '# m\n');

      final ids = (await load()).conflicts.map((c) => c.id).toList();
      final sorted = [...ids]..sort();
      expect(ids, sorted);
    });
  });
}
