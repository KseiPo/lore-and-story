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

    test('"./" alone (normalizes to empty) falls back to default', () {
      expect(ProjectConfig.parse('{"loreDir":"./"}').loreDir, 'lore');
      expect(ProjectConfig.parse('{"loreDir":"././"}').loreDir, 'lore');
    });

    test('a loreDir longer than the length cap falls back to default', () {
      final huge = 'a' * 600;
      expect(ProjectConfig.parse('{"loreDir":"$huge"}').loreDir, 'lore');
    });

    test('never throws on pathologically deep JSON nesting', () {
      final deep = ('[' * 100000) + (']' * 100000);
      // Must not throw (StackOverflowError or otherwise) — falls back to default.
      expect(() => ProjectConfig.parse('{"loreDir":$deep}'), returnsNormally);
      expect(ProjectConfig.parse('{"loreDir":$deep}').loreDir, 'lore');
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

    test('missing loreDir key → default', () {
      expect(ProjectConfig.parse('{"storyDir":"x"}').loreDir, 'lore');
    });

    test('invalid JSON → default', () {
      expect(ProjectConfig.parse('{not json').loreDir, 'lore');
      expect(ProjectConfig.parse('').loreDir, 'lore');
    });

    test('non-object JSON → default', () {
      expect(ProjectConfig.parse('[]').loreDir, 'lore');
      expect(ProjectConfig.parse('"hello"').loreDir, 'lore');
      expect(ProjectConfig.parse('42').loreDir, 'lore');
    });

    test('non-String loreDir → default', () {
      expect(ProjectConfig.parse('{"loreDir":123}').loreDir, 'lore');
      expect(ProjectConfig.parse('{"loreDir":true}').loreDir, 'lore');
      expect(ProjectConfig.parse('{"loreDir":null}').loreDir, 'lore');
    });

    test('empty or whitespace loreDir → default', () {
      expect(ProjectConfig.parse('{"loreDir":""}').loreDir, 'lore');
      expect(ProjectConfig.parse('{"loreDir":"   "}').loreDir, 'lore');
      expect(ProjectConfig.parse('{"loreDir":"./"}').loreDir, 'lore');
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

    test('falls back to defaults when the file is absent (never throws)',
        () async {
      final config = await resolveProjectConfig(storage);
      expect(config.loreDir, 'lore');
    });

    test('resolves a BOM-written config (works with BOM-preserving read)',
        () async {
      // A config file written with a real UTF-8 BOM on disk.
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('{"loreDir":"withBom"}')];
      await File('${tmp.path}/lore-story.json').writeAsBytes(bytes);
      final config = await resolveProjectConfig(storage);
      expect(config.loreDir, 'withBom');
    });

    test('falls back to defaults on invalid JSON (never blocks)', () async {
      File('${tmp.path}/lore-story.json').writeAsStringSync('{ broken');
      final config = await resolveProjectConfig(storage);
      expect(config.loreDir, 'lore');
    });

    test('falls back to defaults when the config path is a directory, not a file',
        () async {
      // A distinct FileSystemException origin from "missing file", exercising
      // the resolver's catch-all rather than just RepoStorageException-via-ENOENT.
      Directory('${tmp.path}/lore-story.json').createSync();
      final config = await resolveProjectConfig(storage);
      expect(config.loreDir, 'lore');
    });
  });
}
