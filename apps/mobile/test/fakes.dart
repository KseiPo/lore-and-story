import 'dart:typed_data';

import 'package:lore_and_story/ai/ai.dart';
import 'package:lore_and_story/storage/storage.dart';

/// In-memory [RepoRootStore] for widget tests (no plugin channel).
class FakeRepoRootStore extends RepoRootStore {
  String? _root;

  FakeRepoRootStore({String? initial}) : _root = initial;

  @override
  Future<String?> read() async => _root;

  @override
  Future<void> write(String rootPath) async => _root = rootPath;

  @override
  Future<void> clear() async => _root = null;
}

/// In-memory [KeyStore] for widget tests (no `flutter_secure_storage`
/// platform channel) — replaces `MessagesApiClient`/`SettingsPage` tests'
/// previous hand-rolled `implements KeyStore` doubles with the one shared
/// double every other port already gets here.
///
/// [failing] makes every operation throw (mirrors [FakeRepoStorage]'s
/// `failWrites`/`failMove` flags) — for exercising the AD-8 never-crash
/// paths. [failWrites] fails only [write], for the narrower "load succeeded,
/// but secure storage became unavailable before the save" case.
class FakeKeyStore extends KeyStore {
  String? _key;
  final bool failing;
  final bool failWrites;

  FakeKeyStore({String? initial, this.failing = false, this.failWrites = false})
      : _key = initial;

  @override
  Future<bool> isConfigured() async {
    if (failing) throw Exception('secure storage unavailable (fake)');
    return _key != null && _key!.isNotEmpty;
  }

  @override
  Future<String?> read() async {
    if (failing) throw Exception('secure storage unavailable (fake)');
    return _key;
  }

  @override
  Future<void> write(String apiKey) async {
    if (failing || failWrites) throw Exception('secure storage unavailable (fake)');
    _key = apiKey;
  }

  @override
  Future<void> clear() async {
    if (failing) throw Exception('secure storage unavailable (fake)');
    _key = null;
  }
}

/// In-memory [AiClient] for widget tests (no real network) — the one shared
/// double every other port already gets here.
///
/// [response] is streamed back as a single chunk when set; [error] is thrown
/// from the stream instead when set (mirrors [FakeRepoStorage]'s
/// `failWrites`/`failMove` flags for exercising the AD-8 never-crash paths —
/// only one of [response]/[error] should be set for a given fake). Every
/// request passed to [sendMessage] is recorded in [requests], in call order,
/// so tests can assert on exactly what was sent (e.g. Story 4.3's translate
/// action, AD-11).
class FakeAiClient implements AiClient {
  final String? response;
  final AiClientException? error;
  final List<AiRequest> requests = [];

  FakeAiClient({this.response, this.error});

  @override
  Stream<String> sendMessage(AiRequest request) async* {
    requests.add(request);
    if (error != null) throw error!;
    if (response != null) yield response!;
  }
}

/// [StoragePermission] whose grant state is set by the test, avoiding the real
/// platform channel.
class FakeStoragePermission extends StoragePermission {
  bool granted;

  FakeStoragePermission({required this.granted});

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    granted = true;
    return granted;
  }

  @override
  Future<bool> openSettings() async => true;
}

/// In-memory [RepoStorage] for widget tests.
///
/// Models a small virtual filesystem: [entries] is the root listing (kept for
/// backward compatibility with existing tests); [dirEntries] gives the
/// listing for any other repo-relative path; [fileContents] seeds initial file
/// content read by [read]. Every [writeAtomic] call is recorded in
/// [writeCalls] and updates the in-memory content so a subsequent [read]
/// reflects the write — letting tests assert both "was written" and "reads
/// back the saved content."
class FakeRepoStorage implements RepoStorage {
  @override
  final String rootPath;
  final List<RepoEntry> _entries;
  final Map<String, List<RepoEntry>> _dirEntries;
  final Map<String, String> _fileContents = {};

  /// Seeded binary content read by [readBytes], keyed the same way as
  /// [fileContents] but separate — image bytes are never text.
  final Map<String, Uint8List> fileBytes;

  /// Every `(path, contents)` passed to [writeAtomic], in call order. A Dart
  /// record (not `MapEntry`, which uses identity equality) so tests can assert
  /// on it with plain `==`/`orderedEquals`.
  final List<(String path, String contents)> writeCalls = [];

  /// Every path passed to [ensureDir], in call order.
  final List<String> ensureDirCalls = [];

  /// Every `(from, to)` passed to [movePath], in call order.
  final List<(String from, String to)> moveCalls = [];

  /// When true, [writeAtomic] throws instead of recording — lets tests cover
  /// the save-failure path.
  final bool failWrites;

  /// When true, [movePath] throws instead of moving — lets tests cover the
  /// promotion-failure path (mirrors [failWrites]).
  final bool failMove;

  /// When true, [listDir] throws — lets tests cover the scan-failure/error-state
  /// path (an unexpected storage failure during a refresh).
  final bool throwOnListDir;

  FakeRepoStorage(
    this.rootPath, {
    List<RepoEntry> entries = const [],
    Map<String, List<RepoEntry>> dirEntries = const {},
    Map<String, String> fileContents = const {},
    this.fileBytes = const {},
    this.failWrites = false,
    this.failMove = false,
    this.throwOnListDir = false,
  })  : _entries = entries, // ignore: prefer_initializing_formals
        // A shallow copy: a fresh Map so ensureDir/movePath below can add or
        // replace *keys* without mutating the caller's map, but the *list*
        // values keep their original identity — some tests hold onto a seeded
        // list and `.add()` to it directly to simulate an external change
        // between scans (see widget_test.dart's "resume/refresh re-scans"
        // tests), which depends on that shared reference surviving.
        _dirEntries = Map.of(dirEntries) {
    _fileContents.addAll(fileContents);
  }

  @override
  Future<List<RepoEntry>> listDir(String path) async {
    if (throwOnListDir) {
      throw RepoStorageException('listDir failed (fake)', path);
    }
    // The root can be seeded either via `entries` (the original single-level
    // form) or via `dirEntries['']` — honour both, so seeding the root the
    // natural way through dirEntries isn't silently ignored. This matters now
    // that startPath: '' is a real production branch.
    if (path.isEmpty) {
      return List.of(_dirEntries[''] ?? _entries);
    }
    return List.of(_dirEntries[path] ?? const []);
  }

  @override
  Future<String> read(String path) async {
    final content = _fileContents[path];
    if (content == null) {
      throw RepoStorageException('not found (fake)', path);
    }
    return content;
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    final bytes = fileBytes[path];
    if (bytes == null) {
      throw RepoStorageException('not found (fake)', path);
    }
    return bytes;
  }

  @override
  Future<void> ensureDir(String path) async {
    ensureDirCalls.add(path);
    _dirEntries.putIfAbsent(path, () => []);
    // Register the new directory as a child of its parent's listing too, so a
    // subsequent listDir/rescan discovers it — mirrors a real filesystem.
    // Copy-on-write (never mutate the existing list in place): a seeded list
    // may be an immutable `const [...]` literal, and some tests hold their own
    // reference to a seeded list expecting it to stay untouched by the fake.
    _addSibling(path, isDirectory: true);
  }

  /// Adds a `RepoEntry` for [path] to its parent's listing in [_dirEntries],
  /// replacing that key's list rather than mutating it in place (see
  /// [ensureDir]'s comment). A no-op if an entry for [path] is already there.
  void _addSibling(String path, {required bool isDirectory}) {
    final parent = _parentOf(path);
    final siblings = _dirEntries[parent] ?? const [];
    if (siblings.any((e) => e.path == path)) return;
    _dirEntries[parent] = [
      ...siblings,
      RepoEntry(name: _basenameOf(path), path: path, isDirectory: isDirectory),
    ];
  }

  @override
  Future<void> writeAtomic(String path, String contents) async {
    if (failWrites) {
      throw RepoStorageException('write failed (fake)', path);
    }
    writeCalls.add((path, contents));
    _fileContents[path] = contents;
  }

  @override
  // The root ('') always exists; a directory "exists" if it has a seeded
  // listing (even an empty one, via dirEntries), a file if its content is
  // seeded. This lets tests exercise the "path is genuinely absent" branch
  // (e.g. a resolved loreDir that doesn't exist under the chosen root).
  Future<bool> exists(String path) async =>
      path.isEmpty || _dirEntries.containsKey(path) || _fileContents.containsKey(path);

  @override
  Future<void> movePath(String from, String to) async {
    if (failMove) {
      throw RepoStorageException('move failed (fake)', from);
    }
    if (!_fileContents.containsKey(from)) {
      throw RepoStorageException('not found (fake)', from);
    }
    // Mirrors AllFilesRepoStorage: the destination's parent directory must
    // already exist (a real OS rename throws ENOENT otherwise) — checked
    // before touching anything, so a caller that forgot to `ensureDir` first
    // fails the same way here as it would in production (Review fix).
    final toParent = _parentOf(to);
    if (toParent.isNotEmpty && !_dirEntries.containsKey(toParent)) {
      throw RepoStorageException('destination directory does not exist (fake)', to);
    }

    final content = _fileContents.remove(from)!;
    moveCalls.add((from, to));
    _fileContents[to] = content;

    // Keep listDir consistent with the move (mirrors a real filesystem), so a
    // rescan afterward sees the new shape instead of a stale, now-unreadable
    // entry. Copy-on-write, same reasoning as `_addSibling`.
    final fromParent = _parentOf(from);
    final fromSiblings = _dirEntries[fromParent];
    if (fromSiblings != null) {
      _dirEntries[fromParent] = fromSiblings.where((e) => e.path != from).toList();
    }
    _addSibling(to, isDirectory: false);
  }
}

String _parentOf(String path) {
  final i = path.lastIndexOf('/');
  return i == -1 ? '' : path.substring(0, i);
}

String _basenameOf(String path) {
  final i = path.lastIndexOf('/');
  return i == -1 ? path : path.substring(i + 1);
}
