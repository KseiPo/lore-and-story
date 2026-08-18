/// The `ai/` slice's public port.
///
/// Pure Dart — **no** `dart:io`, no `package:http`, no Flutter imports live
/// here (AD-9). Everything that needs the network depends on [AiClient],
/// never on `package:http` or the Messages API shape directly — the same
/// seam `storage/repo_storage.dart` draws around the filesystem.
library;

// `ProtocolRoutingAiClient`'s constructor params (`anthropicClient`,
// `openAiClient`) are the public API while its fields are private
// (`_anthropicClient`, `_openAiClient`) — an initializing formal would make
// the parameter's *name* private too, which Dart forbids passing by name
// from outside this file (same reasoning as `messages_api_client.dart`'s
// own file-level ignore). Covers `WakeLockAiClient` (Story 5.4) too — same
// shape, `inner`/`screenWakeLock` public, `_inner`/`_screenWakeLock` private.
// ignore_for_file: prefer_initializing_formals

import 'screen_wake_lock.dart';

/// Which wire format a request uses (Story 4.7/FR27, made functional by
/// Story 4.8/FR28). A **port-level** concept — [AiRequest.protocol] routes a
/// request to the right adapter via [ProtocolRoutingAiClient] — so it lives
/// here rather than in `ai_server_config.dart` (which imports it from this
/// file instead, never the reverse; the port must never depend on the
/// config-parsing file).
enum AiProtocol { anthropic, openai }

/// One request to the AI provider: a system prompt plus the user content to
/// act on. Deliberately generic — this story only stands up the transport;
/// assembling a real translation/grammar prompt is Stories 4.3/4.4's job.
class AiRequest {
  /// The system prompt (instructions, glossary, conventions — whatever the
  /// caller assembles).
  final String system;

  /// The user-turn content (e.g. the file being translated).
  final String userContent;

  /// Upper bound on the model's response length.
  final int maxTokens;

  /// Overrides the adapter's own configured model, when set (Story 4.7 —
  /// `AiServerConfig.model`, resolved fresh per call from `lore-story.json`).
  /// `null` means "use the client's own configured default."
  final String? model;

  /// Overrides the adapter's own configured endpoint **origin** (Story 4.7 —
  /// `resolveOrigin(AiServerConfig)`, non-null for `server: "custom"` with a
  /// valid `baseUrl` or `server: "openrouter"`'s fixed endpoint, Story 4.8).
  /// This is a base/origin (e.g. `http://localhost:1234/v1`), not a complete
  /// endpoint — each protocol-specific adapter appends its own known path
  /// suffix (the Anthropic adapter appends `/messages`, the OpenAI-compatible
  /// adapter appends `/chat/completions`), so one configured origin can serve
  /// whichever protocol adapter it's paired with. `null` means "use the
  /// client's own configured default."
  final Uri? baseUrl;

  /// Which protocol adapter should handle this request (Story 4.8), resolved
  /// fresh per call from `lore-story.json` via `resolveEffectiveProtocol`.
  /// `null` and [AiProtocol.anthropic] both route to the Anthropic adapter
  /// (today's existing default); only [AiProtocol.openai] routes elsewhere.
  /// Only meaningful when [AiClient] is a [ProtocolRoutingAiClient] — a
  /// single-protocol adapter used directly (as every test does) ignores it.
  final AiProtocol? protocol;

  const AiRequest({
    required this.system,
    required this.userContent,
    this.maxTokens = 8192,
    this.model,
    this.baseUrl,
    this.protocol,
  });
}

/// Base for every failure [AiClient.sendMessage] can produce. Typed so
/// callers can branch on failure kind without string-matching a message
/// (AD-8 — total, never a bare/unclassified throw).
sealed class AiClientException implements Exception {
  /// Human-readable description. Never contains the API key (AC8).
  final String message;

  const AiClientException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// No API key has been saved yet — distinct from [AiAuthException] (a saved
/// key that the provider rejected) so a caller can route the two differently
/// (e.g. "send the user to Settings" vs. "your key was rejected") without
/// string-matching a message.
class AiNotConfiguredException extends AiClientException {
  const AiNotConfiguredException(super.message);
}

/// The configured key was rejected (HTTP 401). Not retried — a bad key
/// doesn't become a good one by trying again.
class AiAuthException extends AiClientException {
  const AiAuthException(super.message);
}

/// The request itself was malformed (HTTP 400). Not retried — the same
/// request would fail again identically.
class AiInvalidRequestException extends AiClientException {
  const AiInvalidRequestException(super.message);
}

/// The provider is rate-limiting (HTTP 429). Retryable; this is thrown only
/// once retries are exhausted.
class AiRateLimitException extends AiClientException {
  const AiRateLimitException(super.message);
}

/// The provider returned a server error (HTTP 5xx). Retryable; thrown once
/// retries are exhausted.
class AiServerException extends AiClientException {
  const AiServerException(super.message);
}

/// The request never reached the provider (DNS/connect/timeout/etc.).
/// Retryable; thrown once retries are exhausted.
class AiNetworkException extends AiClientException {
  const AiNetworkException(super.message);
}

/// The resolved `lore-story.json` `ai` object (Story 4.7) specifies a server
/// this app cannot currently reach — e.g. `server: "custom"` with no usable
/// `baseUrl`, an inconsistent `protocol`/`server` combination (Story 4.8 —
/// e.g. `protocol: "openai"` with `server: "anthropic"`, or `protocol:
/// "openai"` with no `model` set), or a `baseUrl` set without `server:
/// "custom"` (never silently ignored). Diagnosed locally from config alone,
/// before any request is built or sent — distinct from every other
/// exception here, which reports a transport/provider outcome.
class AiConfigException extends AiClientException {
  const AiConfigException(super.message);
}

/// Adapter contract for an AI provider's chat/messages endpoint.
///
/// Streams response text as it arrives (SSE) rather than buffering the whole
/// reply — a full scene translation is long output (addendum §C). A
/// transient failure (network/429/5xx) is retried internally with bounded
/// backoff before the stream errors; an auth/invalid-request failure errors
/// immediately, never retried.
abstract interface class AiClient {
  Stream<String> sendMessage(AiRequest request);
}

/// Composes two protocol-specific [AiClient]s behind the single port the
/// rest of the app is threaded with (Story 4.8) — a **pure**, zero-I/O
/// implementation of [AiClient] itself (it does no I/O of its own, only
/// delegates to whichever underlying client actually does), so it belongs
/// beside the interface it implements rather than in an adapter file
/// (AD-9).
///
/// `main.dart` (the composition root) builds the one long-lived instance of
/// this class and threads it through the whole app exactly as it threaded a
/// single [MessagesApiClient] before this story — which underlying adapter
/// actually handles a given call is decided per-request by
/// [AiRequest.protocol], mirroring exactly how `model`/`baseUrl` already
/// flow in per-request (Story 4.7) rather than by rebuilding the client.
class ProtocolRoutingAiClient implements AiClient {
  final AiClient _anthropicClient;
  final AiClient _openAiClient;

  const ProtocolRoutingAiClient({
    required AiClient anthropicClient,
    required AiClient openAiClient,
  })  : _anthropicClient = anthropicClient,
        _openAiClient = openAiClient;

  @override
  Stream<String> sendMessage(AiRequest request) {
    return switch (request.protocol) {
      AiProtocol.openai => _openAiClient.sendMessage(request),
      AiProtocol.anthropic || null => _anthropicClient.sendMessage(request),
    };
  }
}

/// Wraps any [AiClient] to hold the device screen awake for the exact span
/// of [sendMessage]'s stream (Story 5.4, AC1) — a slow local model (e.g. LM
/// Studio on a LAN) can legitimately take longer to respond than it takes
/// for the screen to lock, and once it does, Android's Doze/background
/// restrictions sever the in-flight connection out from under the request.
/// Keeping the screen on keeps the app in the foreground-active lifecycle
/// state, which is what actually prevents that.
///
/// A **pure**, zero-I/O implementation of [AiClient] itself — same reasoning
/// as [ProtocolRoutingAiClient]'s own doc comment for why it belongs beside
/// the interface it implements rather than in an adapter file: it does no
/// I/O of its own, only delegates to [_inner] and calls out to
/// [_screenWakeLock]. `main.dart` (the composition root) wraps the single
/// long-lived [AiClient] instance with this once, outermost — every current
/// and future caller (`runTranslate`, `runGrammarReview`,
/// `SettingsPage._testConnection`) gets the same protection transparently,
/// with nothing to remember to wrap individually (AC2).
///
/// `finally` on an `async*` generator runs on normal completion, on an
/// error propagating through, **and** on the subscription being cancelled
/// (documented Dart async-generator semantics) — so [_screenWakeLock]'s
/// [ScreenWakeLock.disable] is guaranteed to run exactly once no matter how
/// the stream ends, covering AC4's cancellation case (e.g.
/// `SettingsPage.dispose()`'s `_testSubscription?.cancel()`) with the same
/// code path as success/failure, not a separate one. [ScreenWakeLock]'s own
/// methods are total (never throw — see that class's doc comment), so a
/// wake-lock failure can never mask, or be mistaken for, the request's own
/// real outcome (AC3).
class WakeLockAiClient implements AiClient {
  final AiClient _inner;
  final ScreenWakeLock _screenWakeLock;

  const WakeLockAiClient({
    required AiClient inner,
    required ScreenWakeLock screenWakeLock,
  })  : _inner = inner,
        _screenWakeLock = screenWakeLock;

  @override
  Stream<String> sendMessage(AiRequest request) async* {
    await _screenWakeLock.enable();
    try {
      yield* _inner.sendMessage(request);
    } finally {
      await _screenWakeLock.disable();
    }
  }
}
