import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// The adapter is intentionally not exported from the barrel (only main.dart may
// name it) — a test legitimately reaches into the internal file under test.
import 'package:lore_and_story/storage/all_files_repo_storage.dart';
import 'package:lore_and_story/storage/storage.dart';

/// Exercises the adapter against a real temporary directory. `dart:io` is used
/// only in the test — never in the app outside the adapter (AD-3).
void main() {
  late Directory tmp;
  late AllFilesRepoStorage storage;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('repo_storage_test_');
    storage = AllFilesRepoStorage(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('rootPath is exposed and trailing separators are stripped', () {
    final s = AllFilesRepoStorage('${tmp.path}${Platform.pathSeparator}');
    expect(s.rootPath, tmp.path);
  });

  test('listDir returns entries with forward-slash-normalized repo paths',
      () async {
    Directory('${tmp.path}/characters/selena').createSync(recursive: true);
    File('${tmp.path}/characters/frank.md').writeAsStringSync('# Frank');

    final top = await storage.listDir('');
    expect(top.map((e) => e.name).toSet(), {'characters'});
    expect(top.single.isDirectory, isTrue);

    final chars = await storage.listDir('characters');
    final byName = {for (final e in chars) e.name: e};
    expect(byName.keys.toSet(), {'selena', 'frank.md'});
    // Nested repo paths are forward-slash, never backslash (even on Windows).
    expect(byName['selena']!.path, 'characters/selena');
    expect(byName['selena']!.path, isNot(contains('\\')));
    expect(byName['frank.md']!.isDirectory, isFalse);
  });

  test('listDir of a missing directory yields empty, never throws', () async {
    expect(await storage.listDir('nope/missing'), isEmpty);
  });

  test('read returns UTF-8 content including Cyrillic', () async {
    File('${tmp.path}/selena.ru.md').writeAsStringSync('# Селена\nОписание.');
    expect(await storage.read('selena.ru.md'), '# Селена\nОписание.');
  });

  test('read of a missing file throws RepoStorageException (not dart:io)',
      () async {
    expect(
      () => storage.read('ghost.md'),
      throwsA(isA<RepoStorageException>()),
    );
  });

  test('exists distinguishes files, directories, and absent paths', () async {
    Directory('${tmp.path}/world').createSync();
    File('${tmp.path}/world/intro.md').writeAsStringSync('x');
    expect(await storage.exists('world'), isTrue);
    expect(await storage.exists('world/intro.md'), isTrue);
    expect(await storage.exists('world/nope.md'), isFalse);
  });

  test('writeAtomic creates the file and leaves no temp artifacts', () async {
    await storage.writeAtomic('notes.md', 'hello');
    expect(await storage.read('notes.md'), 'hello');

    // No leftover *.tmp-* files from the temp+rename.
    final leftovers = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.lore-tmp-'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('writeAtomic overwrites existing content', () async {
    await storage.writeAtomic('notes.md', 'first');
    await storage.writeAtomic('notes.md', 'second');
    expect(await storage.read('notes.md'), 'second');
  });

  test('backslash and leading-slash inputs normalize to the same target',
      () async {
    Directory('${tmp.path}/a/b').createSync(recursive: true);
    File('${tmp.path}/a/b/c.md').writeAsStringSync('c');
    expect(await storage.read('a/b/c.md'), 'c');
    expect(await storage.read('/a/b/c.md'), 'c');
    expect(await storage.read(r'a\b\c.md'), 'c');
  });

  test('`..` segments cannot escape the repo root', () async {
    // A sibling file OUTSIDE the root must be unreachable via traversal.
    final outside = File('${tmp.parent.path}/outside-secret.md')
      ..writeAsStringSync('leaked');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });

    // '..' is stripped, so this resolves to <root>/outside-secret.md (absent),
    // never the real file one level up.
    expect(await storage.exists('../outside-secret.md'), isFalse);
    expect(
      () => storage.read('../outside-secret.md'),
      throwsA(isA<RepoStorageException>()),
    );

    // A write with traversal stays inside the root too.
    await storage.writeAtomic('../escapee.md', 'x');
    expect(File('${tmp.parent.path}/escapee.md').existsSync(), isFalse);
    expect(File('${tmp.path}/escapee.md').existsSync(), isTrue);
  });

  test('writeAtomic → read round-trips Cyrillic UTF-8 byte-for-byte', () async {
    const cyrillic = '# Селена\n«Тест» — реплика.\n';
    await storage.writeAtomic('selena.ru.md', cyrillic);
    expect(await storage.read('selena.ru.md'), cyrillic);
  });

  test('writeAtomic into a missing parent directory throws RepoStorageException',
      () async {
    expect(
      () => storage.writeAtomic('no-such-dir/file.md', 'x'),
      throwsA(isA<RepoStorageException>()),
    );
  });

  // --- Story 1.2: byte-exactness, malformed reads, temp lifecycle ----------

  // read -> writeAtomic(read result) -> raw bytes on disk must equal the
  // original bytes exactly, for every well-formed UTF-8 shape.
  Future<void> expectByteExactRoundTrip(List<int> original, String name) async {
    await File('${tmp.path}/$name').writeAsBytes(original, flush: true);
    final s = await storage.read(name);
    await storage.writeAtomic(name, s);
    final after = await File('${tmp.path}/$name').readAsBytes();
    expect(after, orderedEquals(original), reason: 'round-trip changed bytes: $name');
  }

  test('byte-exact round-trip preserves LF line endings', () async {
    await expectByteExactRoundTrip(utf8.encode('a\nb\nc\n'), 'lf.md');
  });

  test('byte-exact round-trip preserves CRLF line endings', () async {
    await expectByteExactRoundTrip(utf8.encode('a\r\nb\r\nc\r\n'), 'crlf.md');
  });

  test('byte-exact round-trip preserves absence of a trailing newline', () async {
    await expectByteExactRoundTrip(utf8.encode('no trailing newline'), 'notrail.md');
  });

  test('byte-exact round-trip preserves a leading UTF-8 BOM', () async {
    final withBom = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('# Title\n')];
    await expectByteExactRoundTrip(withBom, 'bom.md');
  });

  test('byte-exact round-trip preserves Cyrillic content', () async {
    await expectByteExactRoundTrip(
      utf8.encode('# Селена\n«Тест» — реплика.\n'),
      'cyr.md',
    );
  });

  test('read of invalid UTF-8 bytes never throws (NFR7)', () async {
    // 0xFF/0xFE are invalid UTF-8 lead bytes.
    await File('${tmp.path}/bad.md').writeAsBytes([0xFF, 0xFE, 0x00, 0x41]);
    final s = await storage.read('bad.md');
    expect(s, contains('\u{FFFD}')); // decoded best-effort, did not throw
  });

  test('a stale temp file is swept on the next write to that directory',
      () async {
    // Stale temp must carry THIS target's scoped prefix to be swept.
    final stale = File('${tmp.path}/.lore-tmp-fresh.md-999-1');
    stale.writeAsStringSync('junk from an interrupted write');
    expect(stale.existsSync(), isTrue);

    await storage.writeAtomic('fresh.md', 'ok');

    expect(stale.existsSync(), isFalse);
    expect(await storage.read('fresh.md'), 'ok');
  });

  test('byte-exact round-trip preserves a doubled leading BOM', () async {
    final twoBoms = <int>[
      0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, //
      ...utf8.encode('# Title\n'),
    ];
    await expectByteExactRoundTrip(twoBoms, 'twobom.md');
  });

  test('byte-exact round-trip preserves empty (0-byte) content', () async {
    await expectByteExactRoundTrip(<int>[], 'empty.md');
    expect(await storage.read('empty.md'), '');
  });

  test('writeAtomic to an empty path (the root) throws, never touches the parent',
      () async {
    expect(
      () => storage.writeAtomic('', 'x'),
      throwsA(isA<RepoStorageException>()),
    );
    // No temp leaked into the parent of the root.
    final parentTemps = tmp.parent
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.lore-tmp-'))
        .toList();
    expect(parentTemps, isEmpty);
  });

  test('concurrent writes to different files in the same dir both succeed',
      () async {
    // Scoped-prefix sweep must not let one write delete another\'s in-flight
    // temp when they target different files in the same directory.
    await Future.wait([
      storage.writeAtomic('a.md', 'AAA'),
      storage.writeAtomic('b.md', 'BBB'),
    ]);
    expect(await storage.read('a.md'), 'AAA');
    expect(await storage.read('b.md'), 'BBB');
  });
}
