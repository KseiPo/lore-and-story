// Constructor params below are the public API (`httpClient`, `keyStore`, ...)
// while the fields are private (`_httpClient`, `_keyStore`, ...) — an
// initializing formal (`this._httpClient`) would make the parameter's *name*
// private too, which Dart forbids passing by name from outside this file.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';
import 'key_store.dart';

/// [AiClient] adapter for Anthropic's Messages API (no official Dart SDK, so
/// this is a raw HTTPS JSON POST + hand-rolled SSE parsing — addendum §C).
///
/// Not exported from `ai.dart`'s barrel (AD-12) — only `main.dart` (the
/// composition root) and this slice's own tests may import this file
/// directly, mirroring `storage/`'s `AllFilesRepoStorage`.
///
/// The underlying [http.Client] is injected so tests never touch the real
/// network (AC10); [KeyStore] is injected so the key is read fresh per call,
/// never cached in this object's own state (one less place it could leak
/// from, AC8).
class MessagesApiClient implements AiClient {
  static final Uri _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  /// Anthropic API version header — pinned per the addendum's model choice.
  static const String _anthropicVersion = '2023-06-01';

  final http.Client _httpClient;
  final KeyStore _keyStore;
  final String _model;
  final int _maxAttempts;
  final Duration Function(int attempt) _backoff;
  final Duration _requestTimeout;
  final Duration _streamIdleTimeout;

  /// [maxAttempts] and [backoff] cover only the retryable failures (network
  /// errors, HTTP 429 without a usable `retry-after`, HTTP 5xx) —
  /// auth/invalid-request failures are never retried regardless of these
  /// values. The default backoff (500ms, 1s, 2s, ...) is this story's own
  /// reasoned default; no source doc specifies exact numbers. [backoff] is
  /// overridable so tests don't sit through real delays.
  ///
  /// [requestTimeout] bounds how long establishing the response (headers)
  /// may take; [streamIdleTimeout] bounds how long the SSE stream may go
  /// without a new chunk once streaming starts — both guard against a
  /// stalled mobile connection (e.g. a Wi-Fi→cellular handoff) hanging
  /// `sendMessage` forever, since neither `http.Client.send()` nor a byte
  /// stream has a deadline of its own.
  MessagesApiClient({
    required http.Client httpClient,
    required KeyStore keyStore,
    String model = 'claude-opus-4-8',
    int maxAttempts = 3,
    Duration Function(int attempt)? backoff,
    Duration requestTimeout = const Duration(seconds: 30),
    Duration streamIdleTimeout = const Duration(seconds: 60),
  })  : _httpClient = httpClient,
        _keyStore = keyStore,
        _model = model,
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

  @override
  Stream<String> sendMessage(AiRequest request) async* {
    final apiKey = await _keyStore.read();
    if (apiKey == null || apiKey.isEmpty) {
      throw const AiNotConfiguredException('No API key configured.');
    }

    for (var attempt = 0; ; attempt++) {
      final isLastAttempt = attempt + 1 >= _maxAttempts;
      http.StreamedResponse response;
      try {
        response = await _httpClient
            .send(_buildRequest(request, apiKey))
            .timeout(_requestTimeout);
      } catch (e) {
        if (isLastAttempt) {
          throw AiNetworkException('Network request failed: ${e.runtimeType}');
        }
        await Future<void>.delayed(_backoff(attempt));
        continue;
      }

      if (response.statusCode == 200) {
        // (Review fix) Everything from here on used to be unguarded: a
        // dropped connection or malformed UTF-8 mid-stream escaped as a raw,
        // untyped exception instead of the AiClientException every caller is
        // promised (AD-8). `handleError` — not a try/catch wrapped around
        // `yield*`, which does not reliably intercept errors delegated from
        // a sub-stream — is the correct Dart idiom for transforming a
        // stream's error events. An AiClientException thrown deliberately by
        // _parseSse (an in-stream `error` event, or an anomalous
        // stop_reason) passes through unchanged; anything else (a transport
        // failure, a decode failure, a `.timeout()`-injected
        // TimeoutException) is wrapped.
        //
        // `.timeout()` is applied to the raw byte stream (the source fed
        // INTO `_parseSse`, an async* generator), not to `_parseSse`'s own
        // output — verified empirically that the latter ordering can hang
        // `.toList()` consumers indefinitely instead of delivering the
        // timeout error, when the source never emits before the deadline.
        // The two nested async* generators (this method and `_parseSse`)
        // plus a `.timeout()` sitting *between* them is the specific shape
        // that triggers it; `.timeout()` below the innermost generator does
        // not.
        yield* _parseSse(response.stream.timeout(_streamIdleTimeout))
            .handleError((Object error, StackTrace stackTrace) {
          if (error is AiClientException) throw error;
          throw AiNetworkException('Stream failed: ${error.runtimeType}');
        });
        return;
      }

      final bodyText = await response.stream.bytesToString();
      final errorMessage = _extractErrorMessage(bodyText) ?? 'HTTP ${response.statusCode}';

      if (response.statusCode == 401) {
        throw AiAuthException(errorMessage);
      }
      // (Review fix) 400/403/404/413 are all request-configuration problems
      // (malformed request, key lacks model access, unknown/retired model
      // id, payload too large) — none are transient, so none should ever be
      // retried or reported as a server fault.
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
  /// back to the default backoff in that case. Never throws (AD-8).
  Duration? _retryAfter(Map<String, String> headers) {
    final raw = headers['retry-after'];
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds < 0) return null;
    final duration = Duration(seconds: seconds);
    return duration > _maxRetryAfter ? _maxRetryAfter : duration;
  }

  http.Request _buildRequest(AiRequest request, String apiKey) {
    final req = http.Request('POST', _endpoint)
      ..headers['x-api-key'] = apiKey
      ..headers['anthropic-version'] = _anthropicVersion
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({
        'model': _model,
        'max_tokens': request.maxTokens,
        'thinking': {'type': 'adaptive'},
        'stream': true,
        'system': request.system,
        'messages': [
          {'role': 'user', 'content': request.userContent},
        ],
      });
    return req;
  }

  /// Best-effort extraction of `{"error": {"message": "..."}}` from a
  /// non-streaming error response body. Never throws (AD-8) — a body that
  /// isn't the expected shape just yields null, falling back to the plain
  /// HTTP status in the caller.
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

  /// Parses the Messages API's SSE stream into text deltas, yielding each
  /// `content_block_delta`'s text as it arrives (never buffers the whole
  /// response first — AC6). An `error` event, or a `message_delta` reporting
  /// an anomalous `stop_reason`, maps to the AC7 exception hierarchy.
  ///
  /// Per the SSE spec, consecutive `data:` lines within one event belong
  /// together and must be joined with `\n` before decoding — a blank line
  /// ends the event. Handled here by buffering (review fix: previously each
  /// `data:` line was decoded independently, silently dropping any delta
  /// whose JSON was split across lines).
  ///
  /// A line that still isn't valid/expected JSON after buffering is skipped,
  /// not a crash (AD-8) — `message_start`/`content_block_start`/
  /// `content_block_stop`/`message_stop`/`ping` events carry no text and are
  /// silently ignored.
  Stream<String> _parseSse(Stream<List<int>> byteStream) async* {
    final lines = byteStream.transform(utf8.decoder).transform(const LineSplitter());
    final dataBuffer = StringBuffer();

    await for (final line in lines) {
      if (line.isEmpty) {
        final text = _handleBufferedEvent(dataBuffer);
        if (text != null) yield text;
        continue;
      }
      if (!line.startsWith('data:')) continue;
      if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
      dataBuffer.write(line.substring(5).trim());
    }
    final text = _handleBufferedEvent(dataBuffer);
    if (text != null) yield text;
  }

  /// Decodes [dataBuffer]'s accumulated `data:` lines as one SSE event
  /// (clearing it either way) and returns the text delta to yield, or null
  /// for an event that carries no text (most event types). May throw an
  /// [AiClientException] for an `error` event or an anomalous `stop_reason`
  /// — the caller (`_parseSse`) lets that propagate as a stream error.
  String? _handleBufferedEvent(StringBuffer dataBuffer) {
    if (dataBuffer.isEmpty) return null;
    final dataStr = dataBuffer.toString();
    dataBuffer.clear();

    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(dataStr);
      if (decoded is! Map<String, dynamic>) return null;
      data = decoded;
    } catch (_) {
      return null;
    }

    if (data['type'] == 'error') {
      throw _mapErrorEvent(data['error']);
    }
    if (data['type'] == 'content_block_delta') {
      final delta = data['delta'];
      if (delta is Map<String, dynamic> && delta['type'] == 'text_delta') {
        final text = delta['text'];
        if (text is String) return text;
      }
      return null;
    }
    if (data['type'] == 'message_delta') {
      final stopReason = (data['delta'] as Map<String, dynamic>?)?['stop_reason'];
      if (stopReason == 'max_tokens') {
        throw const AiInvalidRequestException(
            'Response truncated at max_tokens — increase max_tokens or shorten the request.');
      }
      if (stopReason == 'refusal') {
        throw const AiInvalidRequestException(
            'The provider declined to respond to this request.');
      }
    }
    return null;
  }

  AiClientException _mapErrorEvent(Object? error) {
    final type = error is Map<String, dynamic> ? error['type'] as String? : null;
    final message = error is Map<String, dynamic> && error['message'] is String
        ? error['message'] as String
        : 'Provider error${type != null ? ' ($type)' : ''}.';
    switch (type) {
      case 'authentication_error':
        return AiAuthException(message);
      case 'invalid_request_error':
        return AiInvalidRequestException(message);
      case 'rate_limit_error':
        return AiRateLimitException(message);
      default:
        return AiServerException(message);
    }
  }
}
