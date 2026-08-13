// Constructor params below are the public API (`httpClient`, `keyStore`, ...)
// while the fields are private (`_keyStore`, ...) — an initializing formal
// (`this._keyStore`) would make the parameter's *name* private too, which
// Dart forbids passing by name from outside this file.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';
import 'ai_transport.dart';
import 'key_store.dart';

/// [AiClient] adapter for the OpenAI chat-completions wire format (Story
/// 4.8/FR28) — the second protocol adapter behind the [AiClient] port,
/// serving `server: "openrouter"` and a `server: "custom"` local server
/// (e.g. LM Studio) configured with `protocol: "openai"`.
///
/// Not exported from `ai/ai.dart`'s barrel (AD-12) — only `main.dart` (the
/// composition root) and this slice's own tests import this file directly,
/// exactly mirroring [MessagesApiClient]'s own withholding.
///
/// Retry/backoff/timeout mechanics live in the shared [RetryingHttpSender]
/// — this class owns only what's specific to the OpenAI wire format:
/// `Authorization: Bearer` (optional — AC3), the `messages` array shape
/// (system/user roles, not a separate top-level `system` field), and
/// `delta.content`/`[DONE]` SSE parsing.
///
/// Unlike [MessagesApiClient], a missing API key is **not** an error here
/// (AC3 — a local server on the LAN typically doesn't require one): the
/// `authorization` header is simply omitted when no key is configured, and
/// there is no `AiNotConfiguredException` path in this adapter at all. Also
/// unlike [MessagesApiClient], there is no hardcoded default model —
/// OpenRouter model ids and a local server's loaded model are both entirely
/// author-specific, so a `null` [AiRequest.model] is always a config error
/// here (see [_buildRequest]).
class OpenAiCompatibleClient implements AiClient {
  final KeyStore _keyStore;
  final RetryingHttpSender _sender;

  /// See [MessagesApiClient]'s constructor doc comment — [maxAttempts],
  /// [backoff], [requestTimeout], and [streamIdleTimeout] have identical
  /// meaning and defaults here, forwarded to the same shared
  /// [RetryingHttpSender] machinery.
  OpenAiCompatibleClient({
    required http.Client httpClient,
    required KeyStore keyStore,
    int maxAttempts = 3,
    Duration Function(int attempt)? backoff,
    Duration requestTimeout = const Duration(seconds: 30),
    Duration streamIdleTimeout = const Duration(seconds: 60),
  })  : _keyStore = keyStore,
        _sender = RetryingHttpSender(
          httpClient: httpClient,
          maxAttempts: maxAttempts,
          backoff: backoff,
          requestTimeout: requestTimeout,
          streamIdleTimeout: streamIdleTimeout,
        );

  @override
  Stream<String> sendMessage(AiRequest request) async* {
    // Unlike MessagesApiClient, a missing key is not fatal (AC3) — many
    // self-hosted OpenAI-compatible servers (e.g. LM Studio on a LAN) don't
    // require one. A server that does require a key will reject the
    // request with 401, mapped to AiAuthException same as any other
    // rejected credential.
    final apiKey = await _keyStore.read();

    final byteStream = await _sender.send(() => _buildRequest(request, apiKey));
    yield* _parseSse(byteStream).handleError((Object error, StackTrace stackTrace) {
      if (error is AiClientException) throw error;
      throw AiNetworkException('Stream failed: ${error.runtimeType}');
    });
  }

  http.Request _buildRequest(AiRequest request, String? apiKey) {
    if (request.model == null) {
      throw const AiConfigException(
          'OpenAI-protocol requests need a model — set "model" in '
          "lore-story.json's ai object.");
    }
    if (request.system.isEmpty) {
      throw const AiConfigException(
          'OpenAI-protocol requests need a system prompt — system cannot be empty.');
    }
    if (request.userContent.isEmpty) {
      throw const AiConfigException(
          'OpenAI-protocol requests need user content — userContent cannot be empty.');
    }

    final req = http.Request('POST', _resolveEndpoint(request.baseUrl))
      ..headers['content-type'] = 'application/json';
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      req.headers['authorization'] = 'Bearer $apiKey';
    }
    // OpenAI chat-completions has no separate top-level `system` field the
    // way Anthropic's Messages API does — the system prompt is
    // `messages[0]` with `role: "system"`.
    req.body = jsonEncode({
      'model': request.model,
      'max_tokens': request.maxTokens,
      'stream': true,
      'messages': [
        {'role': 'system', 'content': request.system},
        {'role': 'user', 'content': request.userContent},
      ],
    });
    return req;
  }

  /// [origin] must be non-null whenever this adapter is actually reached in
  /// the real app flow — `ai_server_config.dart`'s `resolveOrigin` either
  /// throws an [AiConfigException] or returns a non-null origin whenever the
  /// effective protocol is OpenAI. Defensively (e.g. a hand-built
  /// [AiRequest] bypassing the normal resolve path), throw rather than guess
  /// a default. When non-null, strips a trailing slash from [origin]'s path
  /// and appends `/chat/completions` — mirrors [MessagesApiClient]
  /// `_resolveEndpoint`'s exact trailing-slash handling, so `.../v1` and
  /// `.../v1/` both produce `.../v1/chat/completions`, never a double
  /// slash.
  Uri _resolveEndpoint(Uri? origin) {
    if (origin == null) {
      throw const AiConfigException(
          'OpenAI-protocol requests need a server address (ai.baseUrl for '
          'a custom server, or ai.server: "openrouter").');
    }
    final path = origin.path.endsWith('/')
        ? origin.path.substring(0, origin.path.length - 1)
        : origin.path;
    return origin.replace(path: '$path/chat/completions');
  }

  /// Parses the OpenAI chat-completions SSE stream into text deltas,
  /// yielding each `choices[0].delta.content` as it arrives. Built on the
  /// shared [sseDataFrames] line-framing — this method owns only the
  /// OpenAI-specific per-event JSON shape and the `[DONE]` sentinel.
  Stream<String> _parseSse(Stream<List<int>> byteStream) async* {
    await for (final frame in sseDataFrames(byteStream)) {
      // The trimmed frame is `[DONE]` (no surrounding quotes — not JSON) at
      // the end of a successful stream. An explicit, readable early-exit
      // rather than relying on decode-failure-and-skip.
      if (frame.trim() == '[DONE]') return;
      final text = _handleFrame(frame);
      if (text != null) yield text;
    }
  }

  /// Decodes one already-joined SSE `data:` frame and returns the text
  /// delta to yield, or null for a frame that carries no text. May throw an
  /// [AiClientException] for an `error` frame or a truncating/declining
  /// `finish_reason` — the caller (`_parseSse`) lets that propagate as a
  /// stream error. A malformed/non-JSON frame is skipped, not a crash
  /// (AD-8), mirroring [MessagesApiClient]'s own "unparseable line is
  /// skipped, not fatal" discipline.
  String? _handleFrame(String frame) {
    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(frame);
      if (decoded is! Map<String, dynamic>) return null;
      data = decoded;
    } catch (_) {
      return null;
    }

    if (data['error'] != null) {
      throw _mapErrorEvent(data['error']);
    }

    final choices = data['choices'];
    if (choices is! List) return null;
    if (choices.isEmpty) {
      throw const AiServerException(
          'Provider returned empty choices array — no text to stream.');
    }
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) return null;

    final finishReason = choice['finish_reason'];
    if (finishReason == 'length') {
      throw const AiInvalidRequestException(
          'Response truncated at max_tokens — increase max_tokens or shorten the request.');
    }
    if (finishReason == 'content_filter') {
      throw const AiInvalidRequestException(
          'The provider declined to respond to this request.');
    }

    final delta = choice['delta'];
    if (delta is Map<String, dynamic>) {
      final content = delta['content'];
      if (content is String) return content;
    }
    return null;
  }

  AiClientException _mapErrorEvent(Object? error) {
    final type = error is Map<String, dynamic> ? error['type'] as String? : null;
    // Preserve any available context — if message is missing or null, include the type in the error.
    final message = error is Map<String, dynamic> && error['message'] is String
        ? error['message'] as String
        : 'Provider error${type != null ? ' (type: $type)' : ''}.';
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
