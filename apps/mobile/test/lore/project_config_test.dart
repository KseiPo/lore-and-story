import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/lore/lore.dart';
import 'package:lore_and_story/storage/all_files_repo_storage.dart';

void main() {
  group('ProjectConfig.parse', () {
    test('reads loreDir from valid JSON', () {
      expect(ProjectConfig.parse('{"loreDir":"custom"}').loreDir, 'custom');
    });

    test('accepts the "./lore" form (leading ./ trimmed)', () {
      expect(ProjectConfig.parse('{"loreDir":"./stuff"}').loreDir, 'stuff');
    });

    test('fully strips a repeated leading "./" (not just one level)', () {
      expect(ProjectConfig.parse('{"loreDir":"././lore"}').loreDir, 'lore');
    });

    test('"./" alone (normalizes to empty) falls back to the default root', () {
      expect(ProjectConfig.parse('{"loreDir":"./"}').loreDir, '');
      expect(ProjectConfig.parse('{"loreDir":"././"}').loreDir, '');
    });

    test('a bare "." (the root) normalizes to empty, not a literal dot', () {
      expect(ProjectConfig.parse('{"loreDir":"."}').loreDir, '');
      // With surrounding whitespace, too.
      expect(ProjectConfig.parse('{"loreDir":" . "}').loreDir, '');
    });

    test('a loreDir longer than the length cap falls back to the default root', () {
      final huge = 'a' * 600;
      expect(ProjectConfig.parse('{"loreDir":"$huge"}').loreDir, '');
    });

    test('never throws on pathologically deep JSON nesting', () {
      final deep = ('[' * 100000) + (']' * 100000);
      // Must not throw (StackOverflowError or otherwise) — falls back to default.
      expect(() => ProjectConfig.parse('{"loreDir":$deep}'), returnsNormally);
      expect(ProjectConfig.parse('{"loreDir":$deep}').loreDir, '');
    });

    test('ignores unrelated keys (forward-compatible)', () {
      const raw =
          '{"storyDir":"src/twee","loreDir":"lore","codeDirs":["x"],"dynamicTags":["d"]}';
      expect(ProjectConfig.parse(raw).loreDir, 'lore');
    });

    test('strips a leading BOM before decoding', () {
      final withBom = '\u{FEFF}{"loreDir":"bommed"}';
      expect(ProjectConfig.parse(withBom).loreDir, 'bommed');
    });

    test('missing loreDir key → default root', () {
      expect(ProjectConfig.parse('{"storyDir":"x"}').loreDir, '');
    });

    test('invalid JSON → default root', () {
      expect(ProjectConfig.parse('{not json').loreDir, '');
      expect(ProjectConfig.parse('').loreDir, '');
    });

    test('non-object JSON → default root', () {
      expect(ProjectConfig.parse('[]').loreDir, '');
      expect(ProjectConfig.parse('"hello"').loreDir, '');
      expect(ProjectConfig.parse('42').loreDir, '');
    });

    test('non-String loreDir → default root', () {
      expect(ProjectConfig.parse('{"loreDir":123}').loreDir, '');
      expect(ProjectConfig.parse('{"loreDir":true}').loreDir, '');
      expect(ProjectConfig.parse('{"loreDir":null}').loreDir, '');
    });

    test('empty or whitespace loreDir → default root', () {
      // An explicit empty/whitespace loreDir means "the root is the lore folder"
      // — the same as the default. Normalizes to the root.
      expect(ProjectConfig.parse('{"loreDir":""}').loreDir, '');
      expect(ProjectConfig.parse('{"loreDir":"   "}').loreDir, '');
      expect(ProjectConfig.parse('{"loreDir":"./"}').loreDir, '');
    });
  });

  group('resolveProjectConfig', () {
    late Directory tmp;
    late AllFilesRepoStorage storage;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('project_config_test_');
      storage = AllFilesRepoStorage(tmp.path);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('resolves loreDir from a present lore-story.json', () async {
      File('${tmp.path}/lore-story.json').writeAsStringSync('{"loreDir":"myLore"}');
      final config = await resolveProjectConfig(storage);
      expect(config.loreDir, 'myLore');
    });

    test('falls back to the default root when the file is absent (never throws)',
        () async {
      final config = await resolveProjectConfig(storage);
      expect(config.loreDir, '');
    });

    test('resolves a BOM-written config (works with BOM-preserving read)',
        () async {
      // A config file written with a real UTF-8 BOM on disk.
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('{"loreDir":"withBom"}')];
      await File('${tmp.path}/lore-story.json').writeAsBytes(bytes);
      final config = await resolveProjectConfig(storage);
      expect(config.loreDir, 'withBom');
    });

    test('falls back to the default root on invalid JSON (never blocks)', () async {
      File('${tmp.path}/lore-story.json').writeAsStringSync('{ broken');
      final config = await resolveProjectConfig(storage);
      expect(config.loreDir, '');
    });

    test('falls back to the default root when the config path is a directory, not a file',
        () async {
      // A distinct FileSystemException origin from "missing file", exercising
      // the resolver's catch-all rather than just RepoStorageException-via-ENOENT.
      Directory('${tmp.path}/lore-story.json').createSync();
      final config = await resolveProjectConfig(storage);
      expect(config.loreDir, '');
    });
  });
}
