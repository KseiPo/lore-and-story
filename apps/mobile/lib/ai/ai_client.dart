/// The `ai/` slice's public port.
///
/// Pure Dart — **no** `dart:io`, no `package:http`, no Flutter imports live
/// here (AD-9). Everything that needs the network depends on [AiClient],
/// never on `package:http` or the Messages API shape directly — the same
/// seam `storage/repo_storage.dart` draws around the filesystem.
library;

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
  /// `resolveCustomOrigin(AiServerConfig)`, only non-null for
  /// `server: "custom"` with a valid `baseUrl`). This is a base/origin
  /// (e.g. `http://localhost:1234/v1`), not a complete endpoint — each
  /// protocol-specific adapter appends its own known path suffix (the
  /// Anthropic adapter appends `/messages`), so one configured origin can
  /// serve whichever protocol adapter it's paired with. `null` means "use
  /// the client's own configured default."
  final Uri? baseUrl;

  const AiRequest({
    required this.system,
    required this.userContent,
    this.maxTokens = 8192,
    this.model,
    this.baseUrl,
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
/// `baseUrl`, `server: "openrouter"` (not yet functional, Story 4.8), or a
/// `baseUrl` set without `server: "custom"` (an inconsistent config, never
/// silently ignored). Diagnosed locally from config alone, before any
/// request is built or sent — distinct from every other exception here,
/// which reports a transport/provider outcome.
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
