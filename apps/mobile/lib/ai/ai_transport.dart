/// Shared, protocol-agnostic HTTP transport plumbing for the `ai/` slice's
/// two [AiClient] adapters ([MessagesApiClient], `OpenAiCompatibleClient`,
/// Story 4.8) — the retry/backoff/timeout/status-classification state
/// machine and the SSE line-framing mechanics are identical standard-HTTP
/// concerns either protocol adapter needs; only the request body shape and
/// the per-event payload meaning (Anthropic's `content_block_delta` vs.
/// OpenAI's `choices[0].delta.content`) differ, and those stay in each
/// adapter's own file.
///
/// Not exported from `ai/ai.dart`'s barrel (AD-12) — internal transport
/// plumbing both adapters import directly, mirroring why
/// `messages_api_client.dart` itself is withheld from the barrel.
library;

// Constructor params below are the public API (`httpClient`, ...) while the
// fields are private (`_httpClient`, ...) — an initializing formal
// (`this._httpClient`) would make the parameter's *name* private too, which
// Dart forbids passing by name from outside this file.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';

/// Splits [byteStream] into successive SSE `data:` payloads — one string per
/// blank-line-terminated event, joining consecutive `data:` lines within one
/// event with `\n` per the SSE spec (a payload split across multiple lines
/// must be recombined before parsing). Every other line (`event:`, `id:`,
/// `retry:`, `:`-prefixed comments) is ignored — callers only ever care
/// about `data:` payloads.
///
/// Purely mechanical framing; has **no** opinion on what a payload means —
/// no JSON decode, no event-type dispatch, no `[DONE]`-sentinel handling.
/// That's each protocol adapter's own job (its own `_parseSse`), since
/// Anthropic's and OpenAI's per-event JSON shapes differ completely.
Stream<String> sseDataFrames(Stream<List<int>> byteStream) async* {
  final lines = byteStream.transform(utf8.decoder).transform(const LineSplitter());
  final dataBuffer = StringBuffer();

  await for (final line in lines) {
    if (line.isEmpty) {
      if (dataBuffer.isNotEmpty) {
        yield dataBuffer.toString();
        dataBuffer.clear();
      }
      continue;
    }
    if (!line.startsWith('data:')) continue;
    if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
    dataBuffer.write(line.substring(5).trim());
  }
  if (dataBuffer.isNotEmpty) yield dataBuffer.toString();
}

/// Sends an HTTP request with retry/backoff/timeout and standard-HTTP status
/// classification, shared by every [AiClient] adapter in this slice — a
/// transient failure (network/429/5xx) is retried with bounded backoff; an
/// auth/invalid-request failure fails immediately, never retried. Neither of
/// these rules is Anthropic- or OpenAI-specific; both providers (and any
/// OpenAI-compatible server) use conventional HTTP semantics for them.
class RetryingHttpSender {
  final http.Client _httpClient;
  final int _maxAttempts;
  final Duration Function(int attempt) _backoff;
  final Duration _requestTimeout;
  final Duration _streamIdleTimeout;

  /// [maxAttempts] and [backoff] cover only the retryable failures (network
  /// errors, HTTP 429 without a usable `retry-after`, HTTP 5xx) —
  /// auth/invalid-request failures are never retried regardless of these
  /// values. [requestTimeout] bounds how long establishing the response
  /// (headers) may take; [streamIdleTimeout] bounds how long the stream may
  /// go without a new chunk once streaming starts.
  RetryingHttpSender({
    required http.Client httpClient,
    int maxAttempts = 3,
    Duration Function(int attempt)? backoff,
    Duration requestTimeout = const Duration(seconds: 30),
    Duration streamIdleTimeout = const Duration(seconds: 60),
  })  : _httpClient = httpClient,
        _maxAttempts = maxAttempts,
        _backoff = backoff ?? _defaultBackoff,
        _requestTimeout = requestTimeout,
        _streamIdleTimeout = streamIdleTimeout;

  static Duration _defaultBackoff(int attempt) =>
      Duration(milliseconds: 500 * (1 << attempt));

  /// Upper bound applied to a provider-supplied `retry-after` value, so a
  /// broken or hostile header can't stall the client far longer than the
  /// default policy ever would.
  static const Duration _maxRetryAfter = Duration(seconds: 30);

  /// Maximum size (bytes) of an error response body to read — guards against
  /// memory exhaustion from a malicious/misconfigured server returning a
  /// multi-GB error response (especially harmful across retries).
  static const int _maxErrorBodySize = 1 << 20; // 1 MB

  /// Sends the request built by [buildRequest] (called once per attempt — a
  /// [http.StreamedResponse]'s request/body can't be replayed after being
  /// read), retrying transient failures per the constructor's policy. On a
  /// 200 response, returns the raw byte stream, idle-timeout-guarded — but
  /// **not yet parsed**; turning bytes into text deltas (and wrapping any
  /// stream-level parsing failure as an [AiClientException] itself) is each
  /// caller's own job, since this method has no protocol knowledge to do
  /// that.
  ///
  /// Returning a `Future<Stream<...>>` (not itself being a `Stream`) is
  /// deliberate: the retry decision has to fully resolve — reach a 200, or
  /// exhaust retries and throw — before there's a byte stream to hand back,
  /// keeping "did the request succeed" and "here are its bytes" as two
  /// clearly-sequenced steps.
  Future<Stream<List<int>>> send(http.Request Function() buildRequest) async {
    for (var attempt = 0; ; attempt++) {
      final isLastAttempt = attempt + 1 >= _maxAttempts;
      http.StreamedResponse response;
      try {
        response = await _httpClient.send(buildRequest()).timeout(_requestTimeout);
      } catch (e) {
        // A deliberately-thrown AiClientException from buildRequest() (e.g.
        // AiConfigException for a request the caller can't legally build —
        // OpenAiCompatibleClient's "no model set" guard) is a config
        // failure, not a transport failure — it must propagate unchanged,
        // never retried and never relabeled as a network error. Non-recoverable
        // Errors (NoSuchMethodError, StackOverflowError, etc.) must propagate
        // unchanged as well — they are not transient network failures.
        if (e is AiClientException || e is Error) rethrow;
        if (isLastAttempt) {
          throw AiNetworkException('Network request failed: ${e.runtimeType}');
        }
        await Future<void>.delayed(_backoff(attempt));
        continue;
      }

      if (response.statusCode == 200) {
        return response.stream.timeout(_streamIdleTimeout);
      }

      final bodyBytes = await response.stream.expand((chunk) => chunk).take(_maxErrorBodySize).toList();
      final bodyText = utf8.decode(bodyBytes);
      final errorMessage = _extractErrorMessage(bodyText) ?? 'HTTP ${response.statusCode}';

      if (response.statusCode == 401) {
        throw AiAuthException(errorMessage);
      }
      // 400/403/404/413 are all request-configuration problems (malformed
      // request, key lacks model access, unknown/retired model id, payload
      // too large) — none are transient, so none should ever be retried or
      // reported as a server fault.
      if (response.statusCode == 400 ||
          response.statusCode == 403 ||
          response.statusCode == 404 ||
          response.statusCode == 413) {
        throw AiInvalidRequestException(errorMessage);
      }
      final retryable = response.statusCode == 429 || response.statusCode >= 500;
      if (retryable && !isLastAttempt) {
        final wait = response.statusCode == 429
            ? (_retryAfter(response.headers) ?? _backoff(attempt))
            : _backoff(attempt);
        await Future<void>.delayed(wait);
        continue;
      }
      if (response.statusCode == 429) {
        throw AiRateLimitException(errorMessage);
      }
      throw AiServerException(errorMessage);
    }
  }

  /// Parses a `retry-after` response header (seconds form, e.g. `"30"`) into
  /// a bounded [Duration], or null if absent/unparseable — the caller falls
  /// back to the default backoff in that case. Never throws (AD-8). Bounds
  /// the parsed seconds to [0, 3600] to guard against integer overflow or
  /// hostile headers claiming a wait of years.
  Duration? _retryAfter(Map<String, String> headers) {
    final raw = headers['retry-after'];
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds < 0 || seconds > 3600) return null;
    final duration = Duration(seconds: seconds);
    return duration > _maxRetryAfter ? _maxRetryAfter : duration;
  }
}

/// Best-effort extraction of `{"error": {"message": "..."}}` from a
/// non-streaming error response body. Never throws (AD-8) — a body that
/// isn't the expected shape just yields null, falling back to the plain HTTP
/// status in the caller. Shared between both protocol adapters: Anthropic's
/// and OpenAI's error envelopes both nest the message under
/// `error.message`.
String? _extractErrorMessage(String bodyText) {
  try {
    final decoded = jsonDecode(bodyText);
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String) return message;
      }
    }
  } catch (_) {
    // Not JSON, or not the expected shape — fall through.
  }
  return null;
}
