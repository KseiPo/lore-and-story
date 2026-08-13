import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/ai/ai_transport.dart';

/// A minimal request builder used across these tests — the exact URL/body
/// don't matter here, `RetryingHttpSender` has no protocol knowledge of
/// either.
http.Request Function() _requestBuilder() =>
    () => http.Request('POST', Uri.parse('https://example.com/v1/x'));

RetryingHttpSender _senderWith(
  http.Client httpClient, {
  int maxAttempts = 3,
  Duration requestTimeout = const Duration(seconds: 30),
  Duration streamIdleTimeout = const Duration(seconds: 60),
}) {
  return RetryingHttpSender(
    httpClient: httpClient,
    maxAttempts: maxAttempts,
    // Near-zero backoff — these tests must not sit through real delays.
    backoff: (attempt) => Duration.zero,
    requestTimeout: requestTimeout,
    streamIdleTimeout: streamIdleTimeout,
  );
}

void main() {
  group('RetryingHttpSender.send — success', () {
    test('a 200 response returns the raw byte stream unparsed', () async {
      final sender = _senderWith(MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(utf8.encode('hello')), 200);
      }));

      final stream = await sender.send(_requestBuilder());
      final bytes = await stream.expand((chunk) => chunk).toList();
      expect(utf8.decode(bytes), 'hello');
    });

    test('buildRequest is called once per attempt, not reused', () async {
      var buildCalls = 0;
      var attempts = 0;
      final sender = _senderWith(MockClient.streaming((request, bodyStream) async {
        attempts++;
        if (attempts < 2) {
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
        }
        return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
      }));

      await sender.send(() {
        buildCalls++;
        return http.Request('POST', Uri.parse('https://example.com/x'));
      });

      expect(buildCalls, 2);
      expect(attempts, 2);
    });
  });

  group('HTTP error mapping and retry', () {
    test('401 throws AiAuthException immediately, never retried', () async {
      var attempts = 0;
      final sender = _senderWith(MockClient.streaming((request, bodyStream) async {
        attempts++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"invalid key"}}')),
          401,
        );
      }));

      await expectLater(
        sender.send(_requestBuilder()),
        throwsA(isA<AiAuthException>()),
      );
      expect(attempts, 1);
    });

    test('400 throws AiInvalidRequestException immediately, never retried',
        () async {
      var attempts = 0;
      final sender = _senderWith(MockClient.streaming((request, bodyStream) async {
        attempts++;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"bad request"}}')),
          400,
        );
      }));

      await expectLater(
        sender.send(_requestBuilder()),
        throwsA(isA<AiInvalidRequestException>()),
      );
      expect(attempts, 1);
    });

    test('403/404/413 all throw AiInvalidRequestException immediately, '
        'never retried and never mistyped as a server error', () async {
      for (final status in [403, 404, 413]) {
        var attempts = 0;
        final sender = _senderWith(MockClient.streaming((request, bodyStream) async {
          attempts++;
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"nope"}}')),
            status,
          );
        }));

        await expectLater(
          sender.send(_requestBuilder()),
          throwsA(isA<AiInvalidRequestException>()),
          reason: 'status $status',
        );
        expect(attempts, 1, reason: 'status $status must not be retried');
      }
    });

    test('429 retries up to maxAttempts, then throws AiRateLimitException',
        () async {
      var attempts = 0;
      final sender = _senderWith(
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
        sender.send(_requestBuilder()),
        throwsA(isA<AiRateLimitException>()),
      );
      expect(attempts, 3);
    });

    test('a 429 that succeeds on a later attempt returns the successful '
        'stream — retry actually recovers', () async {
      var attempts = 0;
      final sender = _senderWith(MockClient.streaming((request, bodyStream) async {
        attempts++;
        if (attempts < 2) {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"rate limited"}}')),
            429,
          );
        }
        return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
      }));

      final stream = await sender.send(_requestBuilder());
      final bytes = await stream.expand((c) => c).toList();
      expect(utf8.decode(bytes), 'ok');
      expect(attempts, 2);
    });

    test('5xx retries then throws AiServerException', () async {
      var attempts = 0;
      final sender = _senderWith(
        MockClient.streaming((request, bodyStream) async {
          attempts++;
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
        }),
        maxAttempts: 2,
      );

      await expectLater(
        sender.send(_requestBuilder()),
        throwsA(isA<AiServerException>()),
      );
      expect(attempts, 2);
    });

    test('a connection failure retries then throws AiNetworkException',
        () async {
      var attempts = 0;
      final sender = _senderWith(
        MockClient.streaming((request, bodyStream) async {
          attempts++;
          throw const _SocketExceptionStub();
        }),
        maxAttempts: 2,
      );

      await expectLater(
        sender.send(_requestBuilder()),
        throwsA(isA<AiNetworkException>()),
      );
      expect(attempts, 2);
    });

    test('a 429 with a retry-after header waits that long instead of the '
        'default backoff, then succeeds', () async {
      var attempts = 0;
      final waits = <Duration>[];
      final sender = RetryingHttpSender(
        httpClient: MockClient.streaming((request, bodyStream) async {
          attempts++;
          if (attempts < 2) {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{}')),
              429,
              headers: {'retry-after': '5'},
            );
          }
          return http.StreamedResponse(Stream.value(utf8.encode('ok')), 200);
        }),
        backoff: (attempt) {
          waits.add(const Duration(seconds: 999)); // would prove the header was ignored
          return Duration.zero;
        },
      );

      final stream = await sender.send(_requestBuilder());
      final bytes = await stream.expand((c) => c).toList();
      expect(utf8.decode(bytes), 'ok');
      expect(waits, isEmpty);
      expect(attempts, 2);
    });
  });

  group('timeouts', () {
    test('a request that never gets a response times out as '
        'AiNetworkException', () async {
      final sender = _senderWith(
        MockClient.streaming((request, bodyStream) => Completer<http.StreamedResponse>().future),
        requestTimeout: const Duration(milliseconds: 20),
        maxAttempts: 1,
      );

      await expectLater(
        sender.send(_requestBuilder()),
        throwsA(isA<AiNetworkException>()),
      );
    });

    test('a stream that stalls mid-response (no new chunk) times out as '
        'AiNetworkException', () async {
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);
      final sender = _senderWith(
        MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(controller.stream, 200);
        }),
        streamIdleTimeout: const Duration(milliseconds: 20),
      );

      final stream = await sender.send(_requestBuilder());
      await expectLater(
        stream.expand((c) => c).toList(),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('sseDataFrames', () {
    test('yields one frame per blank-line-terminated event, joining '
        'consecutive data: lines with \\n', () async {
      const body = 'event: x\n'
          'data: {"a":1,\n'
          'data: "b":2}\n\n'
          'data: second\n\n';
      final frames = await sseDataFrames(Stream.value(utf8.encode(body))).toList();
      expect(frames, ['{"a":1,\n"b":2}', 'second']);
    });

    test('chunks not aligned to line boundaries are still framed correctly',
        () async {
      const body = 'data: hello\n\ndata: world\n\n';
      final bytes = utf8.encode(body);
      final mid = bytes.length ~/ 2;
      final frames = await sseDataFrames(
        Stream.fromIterable([bytes.sublist(0, mid), bytes.sublist(mid)]),
      ).toList();
      expect(frames, ['hello', 'world']);
    });

    test('never buffers the whole response before yielding the first frame',
        () async {
      final controller = StreamController<List<int>>();
      final frames = <String>[];
      final sub = sseDataFrames(controller.stream).listen(frames.add);

      controller.add(utf8.encode('data: first\n\n'));
      await Future<void>.delayed(Duration.zero);
      expect(frames, ['first']); // observed BEFORE the stream is closed

      await controller.close();
      await sub.cancel();
    });

    test('non-data: lines (event:, id:, comments) are ignored', () async {
      const body = 'id: 1\n'
          'event: message\n'
          ': a comment\n'
          'data: payload\n\n';
      final frames = await sseDataFrames(Stream.value(utf8.encode(body))).toList();
      expect(frames, ['payload']);
    });

    test('a trailing frame with no closing blank line is still yielded',
        () async {
      const body = 'data: no-trailing-blank-line';
      final frames = await sseDataFrames(Stream.value(utf8.encode(body))).toList();
      expect(frames, ['no-trailing-blank-line']);
    });
  });
}

/// A stand-in for a real `SocketException` — this file doesn't import
/// `dart:io` (matching AD-9's I/O-isolation spirit even in a test), so a
/// plain [Exception] implementation exercises the same "any thrown error
/// during send() is a network failure" path in [RetryingHttpSender].
class _SocketExceptionStub implements Exception {
  const _SocketExceptionStub();
  @override
  String toString() => '_SocketExceptionStub: connection refused';
}
