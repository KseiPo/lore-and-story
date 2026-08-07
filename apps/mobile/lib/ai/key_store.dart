import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the user's AI provider API key in secure device storage (Android
/// Keystore via `flutter_secure_storage`) — never `shared_preferences`, which
/// is reserved for non-secret config like [RepoRootStore]'s root path (see
/// that class's own doc comment, which forward-references this one).
///
/// [isConfigured] is the only way a caller should check "is a key already
/// saved" — it never returns the plaintext value, unlike [read]. This keeps
/// the real secret out of any widget-local variable that doesn't strictly
/// need it, narrowing the surface for an accidental log/print/interpolation
/// leak (NFR5).
class KeyStore {
  static const String _key = 'ai_api_key';

  const KeyStore();

  static const _storage = FlutterSecureStorage();

  /// Whether a key has been saved. Never exposes the key itself.
  Future<bool> isConfigured() async {
    final value = await _storage.read(key: _key);
    return value != null && value.isNotEmpty;
  }

  /// Returns the stored API key, or null if none has been saved. Callers
  /// must never log, print, or otherwise surface the returned value.
  Future<String?> read() => _storage.read(key: _key);

  /// A control character (e.g. a newline from a copy-paste artifact) would
  /// later break the HTTP header the key is placed into ([MessagesApiClient]
  /// sends it as `x-api-key`) — rejected here so that surfaces as an
  /// immediate, obvious save failure instead of a confusing request failure
  /// later.
  static final RegExp _containsControlChar = RegExp(r'[\x00-\x1F\x7F]');

  /// Stores [apiKey], replacing any previously saved key. Throws
  /// [ArgumentError] for an empty key or one containing a control character
  /// — delivered as a `Future` rejection (this is `async`, not a bare
  /// `Future`-returning function), so it's caught the same way any other
  /// failure from this method would be, never as a synchronous throw a
  /// caller's `try`/`await` might not expect.
  Future<void> write(String apiKey) async {
    // Deliberately ArgumentError(message) rather than ArgumentError.value(...)
    // — the latter would embed apiKey's own text in the exception (AC8: never
    // in an exception message), even though it's the value being rejected.
    if (apiKey.isEmpty || _containsControlChar.hasMatch(apiKey)) {
      throw ArgumentError('apiKey must be non-empty with no control characters');
    }
    return _storage.write(key: _key, value: apiKey);
  }

  /// Deletes the stored key, if any.
  Future<void> clear() => _storage.delete(key: _key);
}
