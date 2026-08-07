import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/ai/messages_api_client.dart';

/// A [KeyStore] stand-in that always returns [key] without touching secure
/// storage — this file tests [MessagesApiClient] in isolation from [KeyStore]
/// (that's `key_store_test.dart`'s job).
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

/// Builds a well-formed Messages API SSE body from a list of text deltas.
String _sseBody(List<String> deltas) {
  final buffer = StringBuffer();
  buffer.write('event: message_start\n');
  buffer.write('data: {"type":"message_start"}\n\n');
  buffer.write('event: content_block_start\n');
  buffer.write('data: {"type":"content_block_start","index":0}\n\n');
  for (final delta in deltas) {
    buffer.write('event: content_block_delta\n');
    buffer.write(
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":${jsonEncode(delta)}}}\n\n');
  }
  buffer.write('event: content_block_stop\n');
  buffer.write('data: {"type":"content_block_stop","index":0}\n\n');
  buffer.write('event: message_delta\n');
  buffer.write('data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n');
  buffer.write('event: message_stop\n');
  buffer.write('data: {"type":"message_stop"}\n\n');
  return buffer.toString();
}

MessagesApiClient _clientWith(
  http.Client httpClient, {
  String? key = 'sk-ant-test-key',
  int maxAttempts = 3,
  Duration requestTimeout = const Duration(seconds: 30),
  Duration streamIdleTimeout = const Duration(seconds: 60),
}) {
  return MessagesApiClient(
    httpClient: httpClient,
    keyStore: _FakeKeyStore(key),
    maxAttempts: maxAttempts,
    // Near-zero backoff — these tests must not sit through real delays
    // (Story 4.1's own testability requirement for the retry policy).
    backoff: (attempt) => Duration.zero,
    requestTimeout: requestTimeout,
    streamIdleTimeout: streamIdleTimeout,
  );
}

const _request = AiRequest(system: 'You are a translator.', userContent: 'Привет');

void main() {
  group('request shape', () {
    test('sends model/thinking/stream fields and the auth headers, never the '
        'key anywhere but the x-api-key header', () async {
      http.Request? captured;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        captured = request as http.Request;
        return http.StreamedResponse(
          Stream.value(utf8.encode(_sseBody(['ok']))),
          200,
        );
      }));

      await client.sendMessage(_request).toList();

      expect(captured, isNotNull);
      expect(captured!.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(captured!.headers['x-api-key'], 'sk-ant-test-key');
      expect(captured!.headers['anthropic-version'], '2023-06-01');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-opus-4-8');
      expect(body['thinking'], {'type': 'adaptive'});
      expect(body['stream'], isTrue);
      expect(body['system'], 'You are a translator.');
      expect(body['messages'], [
        {'role': 'user', 'content': 'Привет'},
      ]);
      // The key must never appear anywhere in the serialized body (AC8).
      expect(captured!.body.contains('sk-ant-test-key'), isFalse);
    });

    test('throws AiNotConfiguredException without sending a request when no '
        'key is configured — distinct from AiAuthException (a saved key '
        'the provider rejected)', () async {
      var sent = false;
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) async {
          sent = true;
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
        key: null,
      );

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiNotConfiguredException>()),
      );
      expect(sent, isFalse);
    });
  });

  group('SSE parsing', () {
    test('yields text deltas in order for a multi-chunk streamed response',
        () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        final body = _sseBody(['Hello', ', ', 'world', '!']);
        final bytes = utf8.encode(body);
        // Split into several chunks, deliberately NOT aligned to line
        // boundaries — the highest-risk case per this story's Dev Notes
        // ("partial-chunk boundaries, multi-line data: fields").
        final mid = bytes.length ~/ 2;
        return http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, mid), bytes.sublist(mid)]),
          200,
        );
      }));

      final deltas = await client.sendMessage(_request).toList();
      expect(deltas.join(), 'Hello, world!');
    });

    test('never buffers the whole response before yielding — the first '
        'delta arrives before the stream closes', () async {
      final controller = StreamController<List<int>>();
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(controller.stream, 200);
      }));

      final deltas = <String>[];
      final sub = client.sendMessage(_request).listen(deltas.add);

      controller.add(utf8.encode('event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"first"}}\n\n'));
      await Future<void>.delayed(Duration.zero);
      expect(deltas, ['first']); // observed BEFORE the stream is closed

      await controller.close();
      await sub.cancel();
    });

    test('a malformed SSE line is skipped, not a crash — valid deltas '
        'before and after still arrive', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        final body = 'event: content_block_delta\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"before"}}\n\n'
            'data: not valid json at all\n\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"after"}}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      final deltas = await client.sendMessage(_request).toList();
      expect(deltas, ['before', 'after']);
    });

    test('an in-stream error event maps to the right exception type and '
        'stops the stream', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        final body = 'event: content_block_delta\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}\n\n'
            'event: error\n'
            'data: {"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      final deltas = <String>[];
      await expectLater(
        client.sendMessage(_request).listen(deltas.add).asFuture<void>(),
        throwsA(isA<AiRateLimitException>()),
      );
      expect(deltas, ['partial']); // delivered before the error arrived
    });

    test('(review fix) a data: payload split across multiple consecutive '
        'lines within one event is joined before decoding, per the SSE spec',
        () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        // The single JSON object is deliberately split across two `data:`
        // lines — the story's own Dev Notes named this as one of the two
        // highest-risk SSE parsing cases.
        const body = 'event: content_block_delta\n'
            'data: {"type":"content_block_delta","index":0,\n'
            'data: "delta":{"type":"text_delta","text":"joined"}}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      final deltas = await client.sendMessage(_request).toList();
      expect(deltas, ['joined']);
    });

    test('(review fix) message_delta with stop_reason max_tokens throws '
        'instead of silently completing a truncated response', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        const body = 'event: content_block_delta\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}\n\n'
            'event: message_delta\n'
            'data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      final deltas = <String>[];
      await expectLater(
        client.sendMessage(_request).listen(deltas.add).asFuture<void>(),
        throwsA(isA<AiInvalidRequestException>()),
      );
      expect(deltas, ['partial']); // whatever streamed before truncation
    });

    test('(review fix) message_delta with stop_reason refusal throws '
        'instead of silently completing an empty response', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        const body = 'event: message_delta\n'
            'data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}\n\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      }));

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiInvalidRequestException>()),
      );
    });

    test('a normal stop_reason (end_turn) completes cleanly with no error',
        () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(utf8.encode(_sseBody(['fine']))), 200);
      }));

      final deltas = await client.sendMessage(_request).toList();
      expect(deltas, ['fine']);
    });

    test('(review fix) a mid-stream connection failure surfaces as a typed '
        'AiNetworkException, not a raw/unclassified exception', () async {
      final controller = StreamController<List<int>>();
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(controller.stream, 200);
      }));

      final deltas = <String>[];
      final done = client.sendMessage(_request).listen(deltas.add).asFuture<void>();

      controller.add(utf8.encode('event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}\n\n'));
      await Future<void>.delayed(Duration.zero);
      controller.addError(const SocketExceptionStub());

      await expectLater(done, throwsA(isA<AiNetworkException>()));
      expect(deltas, ['partial']);
    });

    test('(review fix) malformed UTF-8 mid-stream surfaces as a typed '
        'AiNetworkException, not a raw FormatException', () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        // 0xFF is never valid as a UTF-8 lead byte.
        return http.StreamedResponse(Stream.value([0xFF, 0xFE, 0xFD]), 200);
      }));

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiNetworkException>()),
      );
    });
  });

  group('timeouts', () {
    test('a request that never gets a response times out as '
        'AiNetworkException', () async {
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) => Completer<http.StreamedResponse>().future),
        requestTimeout: const Duration(milliseconds: 20),
        maxAttempts: 1,
      );

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('a stream that stalls mid-response (no new chunk) times out as '
        'AiNetworkException', () async {
      final controller = StreamController<List<int>>();
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(controller.stream, 200);
        }),
        streamIdleTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(controller.close);

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiNetworkException>()),
      );
    });
  });

  group('HTTP error mapping and retry', () {
    test('401 throws AiAuthException immediately, never retried', () async {
      var attempts = 0;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        attempts++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"invalid x-api-key"}}')),
          401,
        );
      }));

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiAuthException>()),
      );
      expect(attempts, 1);
    });

    test('400 throws AiInvalidRequestException immediately, never retried',
        () async {
      var attempts = 0;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        attempts++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"bad request"}}')),
          400,
        );
      }));

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiInvalidRequestException>()),
      );
      expect(attempts, 1);
    });

    test('(review fix) 403/404/413 all throw AiInvalidRequestException '
        'immediately, never retried and never mistyped as a server error',
        () async {
      for (final status in [403, 404, 413]) {
        var attempts = 0;
        final client = _clientWith(MockClient.streaming((request, bodyStream) async {
          attempts++;
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"nope"}}')),
            status,
          );
        }));

        await expectLater(
          client.sendMessage(_request).toList(),
          throwsA(isA<AiInvalidRequestException>()),
          reason: 'status $status',
        );
        expect(attempts, 1, reason: 'status $status must not be retried');
      }
    });

    test('429 retries up to maxAttempts, then throws AiRateLimitException',
        () async {
      var attempts = 0;
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) async {
          attempts++;
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"rate limited"}}')),
            429,
          );
        }),
        maxAttempts: 3,
      );

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiRateLimitException>()),
      );
      expect(attempts, 3);
    });

    test('a 429 that succeeds on a later attempt returns the successful '
        'response — retry actually recovers', () async {
      var attempts = 0;
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        attempts++;
        if (attempts < 2) {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"rate limited"}}')),
            429,
          );
        }
        return http.StreamedResponse(Stream.value(utf8.encode(_sseBody(['ok']))), 200);
      }));

      final deltas = await client.sendMessage(_request).toList();
      expect(deltas, ['ok']);
      expect(attempts, 2);
    });

    test('5xx retries then throws AiServerException', () async {
      var attempts = 0;
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) async {
          attempts++;
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
        }),
        maxAttempts: 2,
      );

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiServerException>()),
      );
      expect(attempts, 2);
    });

    test('a connection failure retries then throws AiNetworkException',
        () async {
      var attempts = 0;
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) async {
          attempts++;
          throw const SocketExceptionStub();
        }),
        maxAttempts: 2,
      );

      await expectLater(
        client.sendMessage(_request).toList(),
        throwsA(isA<AiNetworkException>()),
      );
      expect(attempts, 2);
    });

    test('(review fix) a 429 with a retry-after header waits that long '
        'instead of the default backoff, then succeeds', () async {
      var attempts = 0;
      final waits = <Duration>[];
      final client = MessagesApiClient(
        httpClient: MockClient.streaming((request, bodyStream) async {
          attempts++;
          if (attempts < 2) {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{}')),
              429,
              headers: {'retry-after': '5'},
            );
          }
          return http.StreamedResponse(Stream.value(utf8.encode(_sseBody(['ok']))), 200);
        }),
        keyStore: const _FakeKeyStore('sk-ant-test-key'),
        backoff: (attempt) {
          waits.add(const Duration(seconds: 999)); // would prove the header was ignored
          return Duration.zero;
        },
      );

      final deltas = await client.sendMessage(_request).toList();
      expect(deltas, ['ok']);
      // The default backoff was never consulted — the retry-after header
      // was used instead. (The actual wait itself isn't timed here; the
      // constructor's fake `Future.delayed(Duration(seconds: 5))` would
      // make this test slow, so this asserts the *decision*, not the
      // clock — see the request-shape/timeout groups for real Duration
      // assertions elsewhere in this file.)
      expect(waits, isEmpty);
      expect(attempts, 2);
    });
  });

  group('AC8 — the key never appears in an exception message', () {
    test('a connection failure exception message contains no key', () async {
      final client = _clientWith(
        MockClient.streaming((request, bodyStream) async {
          throw const SocketExceptionStub();
        }),
        maxAttempts: 1,
      );

      try {
        await client.sendMessage(_request).toList();
        fail('expected AiNetworkException');
      } on AiClientException catch (e) {
        expect(e.message.contains('sk-ant-test-key'), isFalse);
        expect(e.toString().contains('sk-ant-test-key'), isFalse);
      }
    });

    test('a 401 response error message (from a realistic provider body) '
        'contains no key — the provider never receives the key anywhere it '
        'could echo it back (only the x-api-key header carries it)',
        () async {
      final client = _clientWith(MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"invalid x-api-key"}}')),
          401,
        );
      }));

      try {
        await client.sendMessage(_request).toList();
        fail('expected AiAuthException');
      } on AiClientException catch (e) {
        expect(e.message.contains('sk-ant-test-key'), isFalse);
      }
    });
  });
}

/// A stand-in for a real `SocketException` — this file doesn't import
/// `dart:io` (matching AD-9's I/O-isolation spirit even in a test), so a
/// plain [Exception] implementation exercises the same "any thrown error
/// during send() is a network failure" path in [MessagesApiClient].
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketExceptionStub: connection refused';
}
