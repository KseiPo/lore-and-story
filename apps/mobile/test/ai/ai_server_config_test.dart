import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/lore/lore.dart' show kProjectConfigFile;

import '../fakes.dart';

void main() {
  group('AiServerConfig.parse', () {
    test('reads all four fields from a well-formed ai object', () {
      const raw = '{"ai":{"server":"custom","protocol":"openai",'
          '"model":"llama-3.1-70b","baseUrl":"http://192.168.1.50:1234/v1"}}';
      final config = AiServerConfig.parse(raw);
      expect(config.server, AiServer.custom);
      expect(config.protocol, AiProtocol.openai);
      expect(config.model, 'llama-3.1-70b');
      expect(config.baseUrl, 'http://192.168.1.50:1234/v1');
      expect(config.parseFailed, isFalse);
    });

    test('server: "anthropic" parses to AiServer.anthropic', () {
      expect(AiServerConfig.parse('{"ai":{"server":"anthropic"}}').server,
          AiServer.anthropic);
    });

    test('server: "openrouter" parses to AiServer.openrouter', () {
      expect(AiServerConfig.parse('{"ai":{"server":"openrouter"}}').server,
          AiServer.openrouter);
    });

    test('protocol: "anthropic" parses to AiProtocol.anthropic', () {
      expect(AiServerConfig.parse('{"ai":{"protocol":"anthropic"}}').protocol,
          AiProtocol.anthropic);
    });

    test('(Review fix) server/protocol are matched after trimming '
        'surrounding whitespace', () {
      const raw = '{"ai":{"server":"custom ","protocol":" openai\\n"}}';
      final config = AiServerConfig.parse(raw);
      expect(config.server, AiServer.custom,
          reason: 'a trailing space from a hand-edited file must not '
              'silently null out server');
      expect(config.protocol, AiProtocol.openai);
    });

    test(
        '(AC2) an unrecognized server string degrades that field to null '
        'without affecting sibling fields', () {
      const raw = '{"ai":{"server":"unknown-provider","protocol":"openai",'
          '"model":"some-model"}}';
      final config = AiServerConfig.parse(raw);
      expect(config.server, isNull,
          reason: 'unrecognized server value falls back to null, not a '
              'whole-config default');
      expect(config.protocol, AiProtocol.openai,
          reason: 'a bad server field must not null out protocol');
      expect(config.model, 'some-model',
          reason: 'a bad server field must not null out model');
    });

    test(
        '(AC2) an unrecognized protocol string degrades only that field to '
        'null', () {
      const raw = '{"ai":{"server":"custom","protocol":"grpc",'
          '"model":"some-model"}}';
      final config = AiServerConfig.parse(raw);
      expect(config.server, AiServer.custom);
      expect(config.protocol, isNull);
      expect(config.model, 'some-model');
    });

    test('missing "ai" key → empty (no server/protocol/model/baseUrl), not '
        'parseFailed', () {
      final config = AiServerConfig.parse('{"loreDir":"lore"}');
      expect(config, AiServerConfig.empty);
      expect(config.parseFailed, isFalse,
          reason: 'an absent ai key is the ordinary, unremarkable case — '
              'never a warning-worthy parse failure');
    });

    test('non-object "ai" value (string) → empty, not parseFailed', () {
      final config = AiServerConfig.parse('{"ai":"oops"}');
      expect(config, AiServerConfig.empty);
      expect(config.parseFailed, isFalse);
    });

    test('non-object "ai" value (array) → empty', () {
      expect(AiServerConfig.parse('{"ai":[1,2,3]}'), AiServerConfig.empty);
    });

    test('non-object "ai" value (number) → empty', () {
      expect(AiServerConfig.parse('{"ai":42}'), AiServerConfig.empty);
    });

    test('a partially-specified ai object populates only the given field', () {
      final config = AiServerConfig.parse('{"ai":{"model":"gpt-4o"}}');
      expect(config.model, 'gpt-4o');
      expect(config.server, isNull);
      expect(config.protocol, isNull);
      expect(config.baseUrl, isNull);
    });

    test('a non-String model value → null, not a throw', () {
      expect(AiServerConfig.parse('{"ai":{"model":123}}').model, isNull);
    });

    test('an empty or whitespace-only model/baseUrl → null', () {
      final config =
          AiServerConfig.parse('{"ai":{"model":"","baseUrl":"   "}}');
      expect(config.model, isNull);
      expect(config.baseUrl, isNull);
    });

    test('(Review fix) a model/baseUrl longer than the length cap → null, '
        'not sent verbatim in every request', () {
      final huge = 'a' * 600;
      final config = AiServerConfig.parse('{"ai":{"model":"$huge"}}');
      expect(config.model, isNull);
    });

    test('a model/baseUrl at exactly the length cap is accepted', () {
      final atCap = 'a' * 512;
      final config = AiServerConfig.parse('{"ai":{"model":"$atCap"}}');
      expect(config.model, atCap);
    });

    test('(Review fix) genuinely malformed JSON → parseFailed, never throws',
        () {
      expect(() => AiServerConfig.parse('{not json'), returnsNormally);
      final config = AiServerConfig.parse('{not json');
      expect(config.parseFailed, isTrue);
      expect(config.server, isNull);
      expect(config.model, isNull);
    });

    test('(Review fix) non-object top-level JSON → parseFailed', () {
      expect(AiServerConfig.parse('[]').parseFailed, isTrue);
      expect(AiServerConfig.parse('"hello"').parseFailed, isTrue);
    });

    test('(Review fix) empty input → parseFailed', () {
      expect(AiServerConfig.parse('').parseFailed, isTrue);
    });

    test('strips a leading BOM before decoding', () {
      const withBom = '\u{FEFF}{"ai":{"model":"bommed-model"}}';
      final config = AiServerConfig.parse(withBom);
      expect(config.model, 'bommed-model');
      expect(config.parseFailed, isFalse);
    });

    test('never throws on pathologically deep JSON nesting', () {
      final deep = ('[' * 100000) + (']' * 100000);
      expect(() => AiServerConfig.parse('{"ai":{"model":$deep}}'),
          returnsNormally);
      // Whether decoding itself succeeds or trips the pathological-input
      // catch-all, the outcome must be a safe, no-override result — never a
      // throw and never a populated model field (a nested array is not a
      // valid model string either way).
      final config = AiServerConfig.parse('{"ai":{"model":$deep}}');
      expect(config.model, isNull);
    });

    test('toString/==/hashCode cover all five fields, including parseFailed',
        () {
      const a = AiServerConfig(
        server: AiServer.custom,
        protocol: AiProtocol.openai,
        model: 'm',
        baseUrl: 'u',
      );
      const b = AiServerConfig(
        server: AiServer.custom,
        protocol: AiProtocol.openai,
        model: 'm',
        baseUrl: 'u',
      );
      const different = AiServerConfig(server: AiServer.anthropic);
      const malformed = AiServerConfig(parseFailed: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(different));
      expect(a, isNot(AiServerConfig.empty));
      expect(AiServerConfig.empty, AiServerConfig.empty);
      expect(malformed, isNot(AiServerConfig.empty),
          reason: 'parseFailed must be part of equality — otherwise a '
              'broken config and an absent one would be indistinguishable');
    });
  });

  group('resolveAiServerConfig', () {
    test('a missing lore-story.json resolves to AiServerConfig.empty '
        '(not parseFailed — a missing file is the ordinary case)', () async {
      final config = await resolveAiServerConfig(FakeRepoStorage('/repo'));
      expect(config, AiServerConfig.empty);
      expect(config.parseFailed, isFalse);
    });

    test('an existing lore-story.json with an ai object is read and parsed',
        () async {
      final storage = FakeRepoStorage('/repo', fileContents: {
        kProjectConfigFile:
            '{"loreDir":"lore","ai":{"server":"custom","model":"local-model",'
                '"baseUrl":"http://localhost:1234/v1"}}',
      });
      final config = await resolveAiServerConfig(storage);
      expect(config.server, AiServer.custom);
      expect(config.model, 'local-model');
      expect(config.baseUrl, 'http://localhost:1234/v1');
    });

    test('a lore-story.json with no ai object resolves to empty', () async {
      final storage = FakeRepoStorage('/repo', fileContents: {
        kProjectConfigFile: '{"loreDir":"lore"}',
      });
      expect(await resolveAiServerConfig(storage), AiServerConfig.empty);
    });

    test('a genuinely malformed lore-story.json resolves to parseFailed',
        () async {
      final storage = FakeRepoStorage('/repo', fileContents: {
        kProjectConfigFile: '{ broken',
      });
      final config = await resolveAiServerConfig(storage);
      expect(config.parseFailed, isTrue);
    });

    test('a read failure resolves to empty, never throws', () async {
      final storage = FakeRepoStorage('/repo'); // no content seeded → read throws
      expect(await resolveAiServerConfig(storage), AiServerConfig.empty);
    });
  });

  group('resolveEffectiveProtocol', () {
    test('an explicit protocol always wins, regardless of server', () {
      const config = AiServerConfig(
          server: AiServer.anthropic, protocol: AiProtocol.openai);
      expect(resolveEffectiveProtocol(config), AiProtocol.openai);
    });

    test('server: openrouter + no protocol set → defaults to openai '
        '(the only protocol OpenRouter speaks)', () {
      const config = AiServerConfig(server: AiServer.openrouter);
      expect(resolveEffectiveProtocol(config), AiProtocol.openai);
    });

    test('server: anthropic + no protocol set → defaults to anthropic '
        '(unchanged from Story 4.7)', () {
      const config = AiServerConfig(server: AiServer.anthropic);
      expect(resolveEffectiveProtocol(config), AiProtocol.anthropic);
    });

    test('server: custom + no protocol set → defaults to anthropic '
        '(a custom Anthropic-compatible endpoint, unaffected by Story 4.8)',
        () {
      const config = AiServerConfig(server: AiServer.custom);
      expect(resolveEffectiveProtocol(config), AiProtocol.anthropic);
    });

    test('no server, no protocol set → defaults to anthropic (today\'s '
        'unconfigured default)', () {
      expect(resolveEffectiveProtocol(AiServerConfig.empty), AiProtocol.anthropic);
    });
  });

  group('resolveOrigin', () {
    test('server: custom + a valid baseUrl → the parsed Uri', () {
      const config = AiServerConfig(
          server: AiServer.custom, baseUrl: 'http://192.168.1.50:1234/v1');
      expect(resolveOrigin(config),
          Uri.parse('http://192.168.1.50:1234/v1'));
    });

    test('server unset + no baseUrl → null (the ordinary, unconfigured '
        'case)', () {
      expect(resolveOrigin(AiServerConfig.empty), isNull);
    });

    test('server: anthropic + no baseUrl → null', () {
      const config = AiServerConfig(server: AiServer.anthropic);
      expect(resolveOrigin(config), isNull);
    });

    test(
        '(Review fix) server: anthropic + a baseUrl present anyway → throws '
        'AiConfigException rather than silently ignoring it', () {
      const config = AiServerConfig(
          server: AiServer.anthropic, baseUrl: 'http://192.168.1.50:1234/v1');
      expect(() => resolveOrigin(config),
          throwsA(isA<AiConfigException>()));
    });

    test(
        '(Story 4.8) server: openrouter + a model set → the fixed OpenRouter '
        'origin', () {
      const config =
          AiServerConfig(server: AiServer.openrouter, model: 'some-model');
      expect(resolveOrigin(config), Uri.parse(kDefaultOpenRouterEndpoint));
    });

    test('(Story 4.8) server: openrouter + a baseUrl also set → throws '
        '(OpenRouter has a fixed endpoint, a baseUrl is inconsistent)', () {
      const config = AiServerConfig(
          server: AiServer.openrouter,
          model: 'some-model',
          baseUrl: 'http://example.com/v1');
      expect(() => resolveOrigin(config), throwsA(isA<AiConfigException>()));
    });

    test('(Story 4.8) protocol: openai + server: anthropic → throws — no '
        'known OpenAI-format endpoint at the Anthropic address', () {
      const config = AiServerConfig(
          server: AiServer.anthropic, protocol: AiProtocol.openai, model: 'm');
      expect(() => resolveOrigin(config), throwsA(isA<AiConfigException>()));
    });

    test('(Story 4.8) protocol: openai + no server set → throws', () {
      const config = AiServerConfig(protocol: AiProtocol.openai, model: 'm');
      expect(() => resolveOrigin(config), throwsA(isA<AiConfigException>()));
    });

    test('(Story 4.8) protocol: openai + server: custom + a valid baseUrl + '
        'no model → throws (no default model for an arbitrary OpenAI-'
        'compatible server)', () {
      const config = AiServerConfig(
          server: AiServer.custom,
          protocol: AiProtocol.openai,
          baseUrl: 'http://192.168.1.50:1234/v1');
      expect(() => resolveOrigin(config), throwsA(isA<AiConfigException>()));
    });

    test('(Story 4.8) server: openrouter (protocol defaults to openai) + no '
        'model → throws', () {
      const config = AiServerConfig(server: AiServer.openrouter);
      expect(() => resolveOrigin(config), throwsA(isA<AiConfigException>()));
    });

    test('(Story 4.8) protocol: openai + server: custom + a valid baseUrl + '
        'a model → the parsed Uri (the full LM Studio-shaped success case)',
        () {
      const config = AiServerConfig(
          server: AiServer.custom,
          protocol: AiProtocol.openai,
          model: 'local-model',
          baseUrl: 'http://192.168.1.50:1234/v1');
      expect(resolveOrigin(config), Uri.parse('http://192.168.1.50:1234/v1'));
    });

    test(
        '(Review fix) no server set + baseUrl present → throws '
        'AiConfigException rather than silently ignoring the baseUrl', () {
      const config = AiServerConfig(baseUrl: 'http://192.168.1.50:1234/v1');
      expect(() => resolveOrigin(config),
          throwsA(isA<AiConfigException>()));
    });

    test(
        '(Review fix) server: custom + no baseUrl → throws AiConfigException '
        'rather than silently falling back to Anthropic with a key saved '
        'for a different vendor', () {
      const config = AiServerConfig(server: AiServer.custom);
      expect(() => resolveOrigin(config),
          throwsA(isA<AiConfigException>()));
    });

    test('server: custom + an unparseable baseUrl string → throws '
        'AiConfigException, never a silent fallback', () {
      const config =
          AiServerConfig(server: AiServer.custom, baseUrl: '::not a uri::');
      expect(() => resolveOrigin(config),
          throwsA(isA<AiConfigException>()));
    });

    test(
        '(Review fix) server: custom + a scheme-less baseUrl → throws, '
        'instead of reaching http.Request and surfacing as a misleading '
        'network failure', () {
      const config =
          AiServerConfig(server: AiServer.custom, baseUrl: 'localhost:1234/v1');
      expect(() => resolveOrigin(config),
          throwsA(isA<AiConfigException>()));
    });

    test('(Review fix) server: custom + a file: baseUrl → throws', () {
      const config = AiServerConfig(
          server: AiServer.custom, baseUrl: 'file:///etc/passwd');
      expect(() => resolveOrigin(config),
          throwsA(isA<AiConfigException>()));
    });

    test('(Review fix) server: custom + an ftp: baseUrl → throws', () {
      const config = AiServerConfig(
          server: AiServer.custom, baseUrl: 'ftp://evil.example.com/x');
      expect(() => resolveOrigin(config),
          throwsA(isA<AiConfigException>()));
    });

    test('(Review fix) server: custom + a protocol-relative baseUrl '
        '(no scheme) → throws', () {
      const config = AiServerConfig(
          server: AiServer.custom, baseUrl: '//evil.example.com/v1');
      expect(() => resolveOrigin(config),
          throwsA(isA<AiConfigException>()));
    });

    test('server: custom + http:// to a private LAN IP (192.168.x.x) → '
        'accepted', () {
      const config = AiServerConfig(
          server: AiServer.custom, baseUrl: 'http://192.168.1.50:1234/v1');
      expect(resolveOrigin(config),
          Uri.parse('http://192.168.1.50:1234/v1'));
    });

    test('server: custom + http:// to 10.x.x.x → accepted', () {
      const config =
          AiServerConfig(server: AiServer.custom, baseUrl: 'http://10.0.0.5:1234');
      expect(resolveOrigin(config), Uri.parse('http://10.0.0.5:1234'));
    });

    test('server: custom + http:// to 172.16-31.x.x → accepted, but '
        '172.32.x.x (outside the RFC 1918 range) → rejected', () {
      const inRange =
          AiServerConfig(server: AiServer.custom, baseUrl: 'http://172.20.0.5:1234');
      expect(resolveOrigin(inRange), Uri.parse('http://172.20.0.5:1234'));

      const outOfRange =
          AiServerConfig(server: AiServer.custom, baseUrl: 'http://172.32.0.5:1234');
      expect(() => resolveOrigin(outOfRange),
          throwsA(isA<AiConfigException>()));
    });

    test('server: custom + http:// to localhost/127.0.0.1 → accepted', () {
      const localhost = AiServerConfig(
          server: AiServer.custom, baseUrl: 'http://localhost:1234');
      expect(
          resolveOrigin(localhost), Uri.parse('http://localhost:1234'));

      const loopbackIp = AiServerConfig(
          server: AiServer.custom, baseUrl: 'http://127.0.0.1:1234');
      expect(resolveOrigin(loopbackIp), Uri.parse('http://127.0.0.1:1234'));
    });

    test(
        '(Review fix, Decision 3) server: custom + http:// to a PUBLIC host '
        '→ throws AiConfigException — the app-level enforcement standing in '
        'for the CIDR ranges Android\'s Network Security Config cannot '
        'express declaratively', () {
      const config = AiServerConfig(
          server: AiServer.custom, baseUrl: 'http://api.example.com/v1');
      expect(() => resolveOrigin(config),
          throwsA(isA<AiConfigException>()));
    });

    test('server: custom + https:// to a public host → accepted (TLS is '
        'always fine, regardless of host)', () {
      const config = AiServerConfig(
          server: AiServer.custom, baseUrl: 'https://api.example.com/v1');
      expect(resolveOrigin(config), Uri.parse('https://api.example.com/v1'));
    });
  });

  group('describeEndpoint (Story 5.3 review fix)', () {
    test('null origin (the Anthropic-default case) returns kDefaultAnthropicEndpoint '
        'verbatim — already a complete endpoint', () {
      expect(
        describeEndpoint(origin: null, protocol: AiProtocol.anthropic),
        kDefaultAnthropicEndpoint,
      );
    });

    test('a custom anthropic-protocol origin gets /messages appended', () {
      expect(
        describeEndpoint(
            origin: Uri.parse('http://localhost:1234/v1'),
            protocol: AiProtocol.anthropic),
        'http://localhost:1234/v1/messages',
      );
    });

    test('a custom openai-protocol origin gets /chat/completions appended '
        '(not /messages — the request path must match the real adapter)', () {
      expect(
        describeEndpoint(
            origin: Uri.parse('http://localhost:1234/v1'),
            protocol: AiProtocol.openai),
        'http://localhost:1234/v1/chat/completions',
      );
    });

    test('a trailing slash on origin never produces a double slash before '
        'the appended path', () {
      expect(
        describeEndpoint(
            origin: Uri.parse('http://localhost:1234/v1/'),
            protocol: AiProtocol.openai),
        'http://localhost:1234/v1/chat/completions',
      );
    });
  });
}
