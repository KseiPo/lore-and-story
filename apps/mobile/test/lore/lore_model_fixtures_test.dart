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
      final entries = await loadLore(storage, 'lore');

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

    Future<List<LoreEntry>> load() =>
        loadLore(AllFilesRepoStorage(tmp.path), 'lore');

    test('a card sitting directly in loreDir has category "general"', () async {
      File('${tmp.path}/lore/frank.md').createSync(recursive: true);
      File('${tmp.path}/lore/frank.md').writeAsStringSync('# Frank\n');

      final entries = await load();
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

      final entries = await load(); // must not throw
      expect(entries.map((e) => e.id), contains('characters/frank.md'));
    });

    test('an unreadable-directory loreDir yields an empty model', () async {
      // No lore/ at all → [] (never throws).
      expect(await load(), isEmpty);
    });
  });
}
