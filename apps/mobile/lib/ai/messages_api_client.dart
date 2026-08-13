// Constructor params below are the public API (`httpClient`, `keyStore`, ...)
// while the fields are private (`_keyStore`, ...) — an initializing formal
// (`this._keyStore`) would make the parameter's *name* private too, which
// Dart forbids passing by name from outside this file.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';
import 'ai_server_config.dart' show kDefaultAnthropicEndpoint;
import 'ai_transport.dart';
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
/// from, AC8). Retry/backoff/timeout mechanics live in the shared
/// [RetryingHttpSender] (Story 4.8) — this class owns only what's specific
/// to the Anthropic Messages wire format: headers, request/response body
/// shape, and SSE event parsing.
class MessagesApiClient implements AiClient {
  static final Uri _endpoint = Uri.parse(kDefaultAnthropicEndpoint);

  /// Anthropic API version header — pinned per the addendum's model choice.
  static const String _anthropicVersion = '2023-06-01';

  final KeyStore _keyStore;
  final String _model;
  final RetryingHttpSender _sender;

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
  })  : _keyStore = keyStore,
        _model = model,
        _sender = RetryingHttpSender(
          httpClient: httpClient,
          maxAttempts: maxAttempts,
          backoff: backoff,
          requestTimeout: requestTimeout,
          streamIdleTimeout: streamIdleTimeout,
        );

  @override
  Stream<String> sendMessage(AiRequest request) async* {
    final apiKey = await _keyStore.read();
    if (apiKey == null || apiKey.isEmpty) {
      throw const AiNotConfiguredException('No API key configured.');
    }

    final byteStream = await _sender.send(() => _buildRequest(request, apiKey));
    // (Review fix) A dropped connection or malformed UTF-8 mid-stream escapes
    // as a raw, untyped exception instead of the AiClientException every
    // caller is promised (AD-8). `handleError` — not a try/catch wrapped
    // around `yield*`, which does not reliably intercept errors delegated
    // from a sub-stream — is the correct Dart idiom for transforming a
    // stream's error events. An AiClientException thrown deliberately by
    // `_parseSse` (an in-stream `error` event, or an anomalous stop_reason)
    // passes through unchanged; anything else (a transport failure, a decode
    // failure, a `.timeout()`-injected TimeoutException from the sender) is
    // wrapped.
    yield* _parseSse(byteStream).handleError((Object error, StackTrace stackTrace) {
      if (error is AiClientException) throw error;
      throw AiNetworkException('Stream failed: ${error.runtimeType}');
    });
  }

  /// Resolves [origin] (a base/origin like `http://localhost:1234/v1`, or
  /// `null` for "use the default") to the complete Messages API endpoint —
  /// this adapter's own `/messages` path suffix, appended here rather than
  /// baked into `AiServerConfig.baseUrl` itself, so the *same* configured
  /// origin also works for the OpenAI-protocol adapter (Story 4.8), which
  /// appends its own `/chat/completions` suffix instead (Review fix, Story
  /// 4.7 code review Decision 2). Strips any trailing slash from [origin]'s
  /// path first so `.../v1` and `.../v1/` both produce `.../v1/messages`,
  /// never `.../v1//messages`.
  Uri _resolveEndpoint(Uri? origin) {
    if (origin == null) return _endpoint;
    final path = origin.path.endsWith('/')
        ? origin.path.substring(0, origin.path.length - 1)
        : origin.path;
    return origin.replace(path: '$path/messages');
  }

  http.Request _buildRequest(AiRequest request, String apiKey) {
    // Story 4.7: `request.baseUrl`/`request.model` (resolved fresh per call
    // from `lore-story.json`'s `ai` object) override this instance's own
    // configured defaults when present — `??`/`_resolveEndpoint` fall back
    // to today's hardcoded Anthropic endpoint/model unchanged when they're
    // null.
    final req = http.Request('POST', _resolveEndpoint(request.baseUrl))
      ..headers['x-api-key'] = apiKey
      ..headers['anthropic-version'] = _anthropicVersion
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({
        'model': request.model ?? _model,
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

  /// Parses the Messages API's SSE stream into text deltas, yielding each
  /// `content_block_delta`'s text as it arrives (never buffers the whole
  /// response first — AC6). An `error` event, or a `message_delta` reporting
  /// an anomalous `stop_reason`, maps to the AC7 exception hierarchy.
  /// Built on the shared [sseDataFrames] line-framing (Story 4.8) — this
  /// method owns only the Anthropic-specific per-event JSON shape.
  ///
  /// A frame that isn't valid/expected JSON is skipped, not a crash (AD-8) —
  /// `message_start`/`content_block_start`/`content_block_stop`/
  /// `message_stop`/`ping` events carry no text and are silently ignored.
  Stream<String> _parseSse(Stream<List<int>> byteStream) async* {
    await for (final frame in sseDataFrames(byteStream)) {
      final text = _handleFrame(frame);
      if (text != null) yield text;
    }
  }

  /// Decodes one already-joined SSE `data:` frame and returns the text delta
  /// to yield, or null for an event that carries no text (most event
  /// types). May throw an [AiClientException] for an `error` event or an
  /// anomalous `stop_reason` — the caller (`_parseSse`) lets that propagate
  /// as a stream error.
  String? _handleFrame(String frame) {
    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(frame);
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
