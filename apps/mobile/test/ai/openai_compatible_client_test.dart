import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/ai/openai_compatible_client.dart';

/// A [KeyStore] stand-in that always returns [key] without touching secure
/// storage — mirrors `messages_api_client_test.dart`'s own `_FakeKeyStore`.
class _FakeKeyStore implements KeyStore {
  final String? key;
  const _FakeKeyStore(this.key);

  @override
  Future<String?> read() async => key;

  @override
  Future<bool> isConfigured() async => key != null && key!.isNotEmpty;

  @override
  Future<void> write(String apiKey) async {}

  @override
  Future<void> clear() async {}
}

/// Builds a well-formed OpenAI chat-completions SSE body from a list of text
/// deltas, terminated with the `[DONE]` sentinel.
String _sseBody(List<String> deltas) {
  final buffer = StringBuffer();
  for (final delta in deltas) {
    buffer.write('data: ${jsonEncode({
          'choices': [
            {
              'index': 0,
              'delta': {'content': delta},
              'finish_reason': null,
            }
          ]
        })}\n\n');
  }
  buffer.write('data: [DONE]\n\n');
  return buffer.toString();
}

OpenAiCompatibleClient _clientWith(
  http.Client httpClient, {
  String? key = 'sk-or-test-key',
  int maxAttempts = 3,
}) {
  return OpenAiCompatibleClient(
    httpClient: httpClient,
    keyStore: _FakeKeyStore(key),
    maxAttempts: maxAttempts,
    backoff: (attempt) => Duration.zero,
  );
}

final _origin = Uri.parse('http://192.168.1.50:1234/v1');

AiRequest _request({String? model = 'local-model', Uri? baseUrl}) => AiRequest(
      system: 'You are a helper.',
      userContent: 'Hello',
      model: model,
      baseUrl: baseUrl ?? _origin,
    );

void main() {
  group('request shape', () {
    test('Authorization: Bearer present when a key is configured', () async {
      http.Request? captured;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        captured = request as http.Request;
        return http.StreamedResponse(Stream.value(utf8.encode(_sseBody(['ok']))), 200);
      }));

      await client.sendMessage(_request()).toList();

      expect(captured!.headers['authorization'], 'Bearer sk-or-test-key');
    });

    test('(AC3) authorization header absent entirely when no key is '
        'configured — not sent empty, not omitted from the request', () async {
      http.Request? captured;
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) async {
          captured = request as http.Request;
          return http.StreamedResponse(Stream.value(utf8.encode(_sseBody(['ok']))), 200);
        }),
        key: null,
      );

      await client.sendMessage(_request()).toList();

      expect(captured!.headers.containsKey('authorization'), isFalse);
    });

    test('body has a messages array with system/user roles, not a top-level '
        'system field', () async {
      http.Request? captured;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        captured = request as http.Request;
        return http.StreamedResponse(Stream.value(utf8.encode(_sseBody(['ok']))), 200);
      }));

      await client
          .sendMessage(AiRequest(
              system: 'sys prompt',
              userContent: 'user text',
              model: 'local-model',
              baseUrl: _origin,
              maxTokens: 500))
          .toList();

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body.containsKey('system'), isFalse);
      expect(body['messages'], [
        {'role': 'system', 'content': 'sys prompt'},
        {'role': 'user', 'content': 'user text'},
      ]);
      expect(body['model'], 'local-model');
      expect(body['max_tokens'], 500);
      expect(body['stream'], isTrue);
      expect(body.containsKey('thinking'), isFalse);
    });

    test('URL is <origin>/chat/completions for a bare origin', () async {
      http.Request? captured;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        captured = request as http.Request;
        return http.StreamedResponse(Stream.value(utf8.encode(_sseBody(['ok']))), 200);
      }));

      await client
          .sendMessage(_request(baseUrl: Uri.parse('http://192.168.1.50:1234')))
          .toList();

      expect(captured!.url.toString(), 'http://192.168.1.50:1234/chat/completions');
    });

    test('a trailing slash on the origin still produces exactly one slash '
        'before "chat/completions"', () async {
      http.Request? captured;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        captured = request as http.Request;
        return http.StreamedResponse(Stream.value(utf8.encode(_sseBody(['ok']))), 200);
      }));

      await client
          .sendMessage(_request(baseUrl: Uri.parse('http://192.168.1.50:1234/v1/')))
          .toList();

      expect(captured!.url.toString(), 'http://192.168.1.50:1234/v1/chat/completions');
    });

    test('a request with model: null throws AiConfigException immediately, '
        'before ever calling httpClient.send', () async {
      var sent = false;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        sent = true;
        return http.StreamedResponse(const Stream.empty(), 200);
      }));

      await expectLater(
        client.sendMessage(_request(model: null)).toList(),
        throwsA(isA<AiConfigException>()),
      );
      expect(sent, isFalse);
    });

    test('a request with baseUrl: null throws AiConfigException immediately, '
        'before ever calling httpClient.send', () async {
      var sent = false;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        sent = true;
        return http.StreamedResponse(const Stream.empty(), 200);
      }));

      // Built directly (not via the `_request()` helper) so `baseUrl` is
      // genuinely omitted rather than falling back to `_origin`.
      const request = AiRequest(
        system: 'You are a helper.',
        userContent: 'Hello',
        model: 'local-model',
      );
      await expectLater(
        client.sendMessage(request).toList(),
        throwsA(isA<AiConfigException>()),
      );
      expect(sent, isFalse);
    });
  });

  group('SSE parsing', () {
    test('delta.content chunks accumulate in order across multiple lines',
        () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode(_sseBody(['Hello', ', ', 'world', '!']))),
          200,
        );
      }));

      final deltas = await client.sendMessage(_request()).toList();
      expect(deltas.join(), 'Hello, world!');
    });

    test('a trailing data: [DONE] line cleanly ends the stream with no '
        'error and no extra yielded text', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode(_sseBody(['only chunk']))),
          200,
        );
      }));

      final deltas = await client.sendMessage(_request()).toList();
      expect(deltas, ['only chunk']);
    });

    test('finish_reason: "length" throws the truncation '
        'AiInvalidRequestException', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        const body = 'data: {"choices":[{"delta":{"content":"partial"},'
            '"finish_reason":null}]}\n\n'
            'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      final deltas = <String>[];
      await expectLater(
        client.sendMessage(_request()).listen(deltas.add).asFuture<void>(),
        throwsA(isA<AiInvalidRequestException>()),
      );
      expect(deltas, ['partial']);
    });

    test('finish_reason: "content_filter" throws the refusal-equivalent '
        'AiInvalidRequestException', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        const body =
            'data: {"choices":[{"delta":{},"finish_reason":"content_filter"}]}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      await expectLater(
        client.sendMessage(_request()).toList(),
        throwsA(isA<AiInvalidRequestException>()),
      );
    });

    test('an in-stream {"error": {...}} frame maps to the right exception '
        'type per its type field', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        const body = 'data: {"choices":[{"delta":{"content":"partial"},'
            '"finish_reason":null}]}\n\n'
            'data: {"error":{"type":"rate_limit_error","message":"slow down"}}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      final deltas = <String>[];
      await expectLater(
        client.sendMessage(_request()).listen(deltas.add).asFuture<void>(),
        throwsA(isA<AiRateLimitException>()),
      );
      expect(deltas, ['partial']);
    });

    test('a malformed/non-JSON data: line is skipped, not a crash', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        const body = 'data: {"choices":[{"delta":{"content":"before"},'
            '"finish_reason":null}]}\n\n'
            'data: not valid json at all\n\n'
            'data: {"choices":[{"delta":{"content":"after"},'
            '"finish_reason":null}]}\n\n'
            'data: [DONE]\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      final deltas = await client.sendMessage(_request()).toList();
      expect(deltas, ['before', 'after']);
    });

    test('a normal finish_reason (stop) completes cleanly with no error',
        () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        const body = 'data: {"choices":[{"delta":{"content":"fine"},'
            '"finish_reason":"stop"}]}\n\n'
            'data: [DONE]\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      final deltas = await client.sendMessage(_request()).toList();
      expect(deltas, ['fine']);
    });
  });

  group('HTTP error mapping (thin smoke pass — full matrix in '
      'ai_transport_test.dart)', () {
    test('401 throws AiAuthException', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"invalid key"}}')),
          401,
        );
      }));

      await expectLater(
        client.sendMessage(_request()).toList(),
        throwsA(isA<AiAuthException>()),
      );
    });

    test('429 retries then throws AiRateLimitException', () async {
      var attempts = 0;
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) async {
          attempts++;
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"rate limited"}}')),
            429,
          );
        }),
        maxAttempts: 2,
      );

      await expectLater(
        client.sendMessage(_request()).toList(),
        throwsA(isA<AiRateLimitException>()),
      );
      expect(attempts, 2);
    });

    test('a connection failure surfaces as AiNetworkException', () async {
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) async {
          throw const _SocketExceptionStub();
        }),
        maxAttempts: 1,
      );

      await expectLater(
        client.sendMessage(_request()).toList(),
        throwsA(isA<AiNetworkException>()),
      );
    });
  });

  group('key never leaks', () {
    test('an exception message never contains the configured key', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"invalid key"}}')),
          401,
        );
      }));

      try {
        await client.sendMessage(_request()).toList();
        fail('expected AiAuthException');
      } on AiClientException catch (e) {
        expect(e.message.contains('sk-or-test-key'), isFalse);
        expect(e.toString().contains('sk-or-test-key'), isFalse);
      }
    });
  });
}

class _SocketExceptionStub implements Exception {
  const _SocketExceptionStub();
  @override
  String toString() => '_SocketExceptionStub: connection refused';
}
