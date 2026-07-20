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
        .where((f) => f.path.contains('.tmp-'))
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
}
