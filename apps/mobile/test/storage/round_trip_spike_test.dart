import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/storage/all_files_repo_storage.dart';
import 'package:lore_and_story/storage/storage.dart';

void main() {
  late Directory tmp;
  late AllFilesRepoStorage storage;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('round_trip_spike_test_');
    storage = AllFilesRepoStorage(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('reports a byte-safe round-trip for a well-formed file', () async {
    File('${tmp.path}/scene.ru.md').writeAsStringSync('# Сцена\nРеплика.\n');
    final result = await RoundTripSpike(storage).run('scene.ru.md');
    expect(result.identical, isTrue);
    expect(result.detail, isNull);
    // The file survived unchanged.
    expect(await storage.read('scene.ru.md'), '# Сцена\nРеплика.\n');
  });

  test('skips the write for a malformed file — never throws, never corrupts',
      () async {
    final original = [0xFF, 0xFE, 0x41];
    await File('${tmp.path}/bad.ru.md').writeAsBytes(original);

    final result = await RoundTripSpike(storage).run('bad.ru.md');

    expect(result.identical, isFalse);
    expect(result.detail, contains('skipped')); // handled note, never thrown
    // The malformed bytes on disk are untouched — the spike must not corrupt them.
    expect(
      await File('${tmp.path}/bad.ru.md').readAsBytes(),
      orderedEquals(original),
    );
  });

  test('reports the handled error (never throws) for a missing file', () async {
    final result = await RoundTripSpike(storage).run('ghost.ru.md');
    expect(result.identical, isFalse);
    expect(result.detail, isNotNull);
  });

  test('findFirstMatching locates a nested .ru.md via BFS', () async {
    Directory('${tmp.path}/characters/selena').createSync(recursive: true);
    File('${tmp.path}/characters/selena/selena.ru.md').writeAsStringSync('x');
    final path = await findFirstMatching(storage, (n) => n.endsWith('.ru.md'));
    expect(path, 'characters/selena/selena.ru.md');
  });

  test('findFirstMatching returns null when nothing matches', () async {
    File('${tmp.path}/note.txt').writeAsStringSync('x');
    final path = await findFirstMatching(storage, (n) => n.endsWith('.ru.md'));
    expect(path, isNull);
  });

  test('findFirstMatching skips syncer metadata and media dirs', () async {
    Directory('${tmp.path}/.stversions').createSync();
    File('${tmp.path}/.stversions/old.ru.md').writeAsStringSync('archived');
    Directory('${tmp.path}/media').createSync();
    File('${tmp.path}/media/clip.ru.md').writeAsStringSync('media');
    Directory('${tmp.path}/characters').createSync();
    File('${tmp.path}/characters/real.ru.md').writeAsStringSync('real');

    final path = await findFirstMatching(storage, (n) => n.endsWith('.ru.md'));
    expect(path, 'characters/real.ru.md');
  });

  test('findFirstMatching returns null when matches live only in skipped dirs',
      () async {
    Directory('${tmp.path}/.stversions').createSync();
    File('${tmp.path}/.stversions/old.ru.md').writeAsStringSync('archived');

    final path = await findFirstMatching(storage, (n) => n.endsWith('.ru.md'));
    expect(path, isNull);
  });
}
