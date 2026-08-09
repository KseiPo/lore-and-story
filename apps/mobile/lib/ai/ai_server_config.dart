import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import '../lore/lore.dart' show kProjectConfigFile;
import '../storage/storage.dart';
import 'ai_client.dart' show AiConfigException;

/// Which AI provider a request goes to (Story 4.7/FR27). `custom` requires
/// [AiServerConfig.baseUrl]; `anthropic` and (once Story 4.8 ships an
/// OpenAI-protocol adapter) `openrouter` use a fixed, app-known endpoint —
/// an author never needs to supply one for either.
enum AiServer { anthropic, openrouter, custom }

/// Which wire format a request uses (Story 4.7/FR27). Read and stored here,
/// but not yet acted on — only the Anthropic-Messages-format
/// [MessagesApiClient] exists; an `openai`-protocol adapter is Story 4.8.
enum AiProtocol { anthropic, openai }

/// The default Anthropic Messages API endpoint — the single source of truth
/// for both [MessagesApiClient]'s own hardcoded default and this story's
/// context-preview "Server" section, so the two can never drift apart.
const String kDefaultAnthropicEndpoint = 'https://api.anthropic.com/v1/messages';

/// A `model`/`baseUrl` value longer than this is treated as not overridden
/// — guards against a pathological config value being read, sent in every
/// request, and rendered with no bound, mirroring `ProjectConfig`'s own
/// `_maxLoreDirLength` guard (`lore/project_config.dart`).
const int _kMaxFieldLength = 512;

/// Resolved AI server/protocol/model/baseUrl override, read from
/// [kProjectConfigFile]'s optional `ai` object (Story 4.7). Never the API
/// key — that stays in `KeyStore`'s secure storage, never in this
/// repo-synced file.
///
/// Each field is independently `null` when not overridden — the caller
/// applies its own hardcoded default in that case, the same "field absent →
/// caller's own default" shape `AiPromptConfig` already uses. Pure value
/// type — no I/O.
///
/// A deliberately separate parser from `lore/project_config.dart`'s
/// `ProjectConfig`, even though both read the same `lore-story.json` file:
/// this `ai` object is an `ai/`-slice concern (it configures `AiClient`),
/// while `loreDir` is a `lore/`-slice concern. Two independent,
/// single-key-owning parsers keep each simple and keep `ProjectConfig`'s own
/// tests completely unaffected by anything added here.
@immutable
class AiServerConfig {
  final AiServer? server;
  final AiProtocol? protocol;
  final String? model;
  final String? baseUrl;

  /// True only when `lore-story.json`'s underlying JSON could not be
  /// decoded **at all** (malformed syntax, or a non-object root) — never
  /// when the `ai` key is simply absent or wrong-typed, which is the
  /// ordinary, unremarkable "not configured yet" case (Review fix,
  /// Story 4.7 code review Decision 4). Distinct from every other field:
  /// this is a diagnostic for the UI to show a warning, not a resolved
  /// value a caller falls back from.
  final bool parseFailed;

  const AiServerConfig({
    this.server,
    this.protocol,
    this.model,
    this.baseUrl,
    this.parseFailed = false,
  });

  /// Config used when `lore-story.json` is missing, unreadable, or has no
  /// (or an invalid) `ai` object — every piece falls back to its hardcoded
  /// default (FR27 AC2 / AD-8). Distinct from a `parseFailed` result (the
  /// file exists but is broken) — see [parseFailed].
  static const AiServerConfig empty = AiServerConfig();

  /// Parses raw `lore-story.json` text, best-effort. **Never throws**: any
  /// failure or unexpected shape falls back to [empty] (or a `parseFailed`
  /// variant of it) for the affected piece(s), mirroring `ProjectConfig
  /// .parse`'s own contract.
  ///
  /// Each of the four resolvable fields degrades to `null`
  /// **independently** on a missing, wrong-type, or unrecognized value — an
  /// invalid `server` string, for example, never nulls out
  /// `model`/`protocol`/`baseUrl` too (FR27 AC2's "per missing/unset field"
  /// requirement).
  factory AiServerConfig.parse(String raw) {
    // The entire body is guarded by a catch-all (not just specific exception
    // types), mirroring `ProjectConfig.parse`'s own reasoning: an `Error`
    // subtype (e.g. `StackOverflowError` on pathological input) is not
    // caught by an `Exception`-typed clause, and this factory must never
    // throw regardless of what a malformed file produces. Pathological
    // input reaching this outer catch means the file genuinely could not be
    // understood — `parseFailed: true`, same as a `jsonDecode` failure.
    try {
      // Strip a single leading BOM before parsing — Windows editors/
      // PowerShell write one (see `ProjectConfig.parse`'s identical guard).
      final cleaned = raw.startsWith('\u{FEFF}') ? raw.substring(1) : raw;

      final Object? decoded;
      try {
        decoded = jsonDecode(cleaned);
      } catch (_) {
        return const AiServerConfig(parseFailed: true);
      }
      if (decoded is! Map) return const AiServerConfig(parseFailed: true);

      // An absent or wrong-typed `ai` key is the ordinary "not configured"
      // case, not a parse failure — most repos will never have one.
      final aiRaw = decoded['ai'];
      if (aiRaw is! Map) return empty;

      return AiServerConfig(
        server: _parseServer(aiRaw['server']),
        protocol: _parseProtocol(aiRaw['protocol']),
        model: _parseString(aiRaw['model']),
        baseUrl: _parseString(aiRaw['baseUrl']),
      );
    } catch (_) {
      return const AiServerConfig(parseFailed: true);
    }
  }

  static AiServer? _parseServer(Object? value) {
    if (value is! String) return null;
    return switch (value.trim()) {
      'anthropic' => AiServer.anthropic,
      'openrouter' => AiServer.openrouter,
      'custom' => AiServer.custom,
      _ => null,
    };
  }

  static AiProtocol? _parseProtocol(Object? value) {
    if (value is! String) return null;
    return switch (value.trim()) {
      'anthropic' => AiProtocol.anthropic,
      'openai' => AiProtocol.openai,
      _ => null,
    };
  }

  static String? _parseString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > _kMaxFieldLength) return null;
    return trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is AiServerConfig &&
      other.server == server &&
      other.protocol == protocol &&
      other.model == model &&
      other.baseUrl == baseUrl &&
      other.parseFailed == parseFailed;

  @override
  int get hashCode => Object.hash(server, protocol, model, baseUrl, parseFailed);

  @override
  String toString() => 'AiServerConfig(server: ${server ?? 'default'}, '
      'protocol: ${protocol ?? 'default'}, '
      'model: ${model ?? 'default'}, baseUrl: ${baseUrl ?? 'default'}, '
      'parseFailed: $parseFailed)';
}

/// Resolves [config] to the custom endpoint **origin** a request should use
/// (e.g. `http://localhost:1234/v1` — a base, not a complete endpoint; see
/// `AiRequest.baseUrl`'s own doc comment for why), or `null` meaning "no
/// override — the caller's own hardcoded default applies," the ordinary,
/// unconfigured case.
///
/// **Throws [AiConfigException]** — never silently falls back to the
/// default endpoint — whenever [config] signals intent to use something
/// other than plain Anthropic-direct that this app cannot actually honor
/// (Review fix, Story 4.7 code review): `server: "custom"` with a missing
/// or invalid `baseUrl`; `server: "openrouter"` (not yet functional, Story
/// 4.8); or a `baseUrl` set without `server: "custom"` (an inconsistent
/// config an author almost certainly didn't intend). Silently sending to
/// Anthropic with a key saved for a different vendor, or ignoring a
/// configured `baseUrl` outright, is exactly the failure mode this guards
/// against — an honest, typed error is safer than a wrong destination.
Uri? resolveCustomOrigin(AiServerConfig config) {
  final hasBaseUrl = config.baseUrl != null;
  switch (config.server) {
    case null:
      if (hasBaseUrl) {
        throw const AiConfigException(
            'lore-story.json sets ai.baseUrl but not ai.server: "custom" — '
            'add "server": "custom" to use it.');
      }
      return null;
    case AiServer.anthropic:
      if (hasBaseUrl) {
        throw const AiConfigException(
            'lore-story.json sets ai.baseUrl but ai.server is "anthropic" — '
            'set "server": "custom" to use a custom endpoint.');
      }
      return null;
    case AiServer.openrouter:
      throw const AiConfigException(
          'server: "openrouter" is not yet supported by this version of the '
          'app — requests would go to the wrong place.');
    case AiServer.custom:
      final origin = _validOrigin(config.baseUrl);
      if (origin == null) {
        throw const AiConfigException(
            'ai.server is "custom" but ai.baseUrl is missing or not a '
            'valid http(s) address.');
      }
      // Review fix (Story 4.7 code review Decision 3): Android's Network
      // Security Config can only allow cleartext for exact hostnames/IP
      // literals, never a CIDR range — there is no declarative way to
      // permit "any private-network address" for an author's not-yet-known
      // LAN IP. The Android manifest instead grants blanket cleartext
      // permission, and this app-level check is what actually restricts
      // where it's used: `http://` is only ever accepted for a
      // private/loopback host, matching the manifest's own doc comment.
      if (origin.scheme == 'http' && !_isPrivateOrLoopbackHost(origin.host)) {
        throw const AiConfigException(
            'ai.baseUrl uses http:// for a non-local address — only a '
            'private/LAN or loopback address (e.g. 192.168.x.x, 10.x.x.x, '
            'localhost) may use plain http; use https:// for anything else.');
      }
      return origin;
  }
}

/// A [raw] string is a valid custom origin only when it parses as an
/// absolute `http`/`https` URI with a non-empty host (Review fix, Story
/// 4.7 code review) — `Uri.tryParse` alone accepts almost anything
/// (scheme-less strings, `file:`, `ftp:`, protocol-relative references),
/// which previously reached `http.Request` and surfaced as a misleading
/// "network failed" error after three retries instead of a clear,
/// immediate config error.
Uri? _validOrigin(String? raw) {
  if (raw == null) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.isAbsolute) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// True for `localhost`, IPv4 loopback (127.0.0.0/8), the three RFC 1918
/// private ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16), and IPv4
/// link-local (169.254.0.0/16, e.g. mDNS/auto-IP) — the actual set of
/// addresses `http://` (cleartext) is permitted to reach (Review fix, Story
/// 4.7 code review Decision 3). Anything else — a public hostname or IP —
/// requires `https://`.
bool _isPrivateOrLoopbackHost(String host) {
  if (host == 'localhost') return true;
  final match =
      RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
  if (match == null) return false;
  final octets = List.generate(4, (i) => int.parse(match.group(i + 1)!));
  if (octets.any((o) => o > 255)) return false;
  final a = octets[0], b = octets[1];
  if (a == 127) return true; // loopback
  if (a == 10) return true; // 10.0.0.0/8
  if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
  if (a == 192 && b == 168) return true; // 192.168.0.0/16
  if (a == 169 && b == 254) return true; // 169.254.0.0/16 (link-local)
  return false;
}

/// Reads and resolves [kProjectConfigFile]'s `ai` object from the repo root
/// via [storage].
///
/// A missing file, read error, or invalid content resolves to
/// [AiServerConfig.empty] (or a `parseFailed` variant of it for a genuinely
/// broken file — see [AiServerConfig.parseFailed]) — this **never throws
/// and never blocks** (AD-8), mirroring
/// `resolveProjectConfig`/`resolveAiPromptConfig`. Re-read on every call (no
/// caching), so an edited config takes effect on the very next AI action.
///
/// This independently re-reads and re-decodes the same `lore-story.json`
/// text `resolveProjectConfig` also reads — a deliberate choice, not an
/// oversight (see this file's class doc comment). It is called far less
/// often than `resolveProjectConfig` (only when an AI action actually
/// fires, not on every repo refresh), and every config resolver in this
/// codebase already re-reads with no caching (AD-1).
Future<AiServerConfig> resolveAiServerConfig(RepoStorage storage) async {
  try {
    final raw = await storage.read(kProjectConfigFile);
    return AiServerConfig.parse(raw);
  } catch (_) {
    // Missing file, I/O error, or any other read failure → empty (NOT
    // parseFailed — a missing file is the ordinary "not configured" case,
    // not a broken one). A catch-all (not just `on RepoStorageException`)
    // so a storage implementation that surfaces a different failure type
    // still can't break the "never blocks" guarantee.
    return AiServerConfig.empty;
  }
}
