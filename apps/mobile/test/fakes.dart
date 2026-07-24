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

  /// Every `(path, contents)` passed to [writeAtomic], in call order. A Dart
  /// record (not `MapEntry`, which uses identity equality) so tests can assert
  /// on it with plain `==`/`orderedEquals`.
  final List<(String path, String contents)> writeCalls = [];

  /// When true, [writeAtomic] throws instead of recording — lets tests cover
  /// the save-failure path.
  final bool failWrites;

  /// When true, [listDir] throws — lets tests cover the scan-failure/error-state
  /// path (an unexpected storage failure during a refresh).
  final bool throwOnListDir;

  FakeRepoStorage(
    this.rootPath, {
    List<RepoEntry> entries = const [],
    Map<String, List<RepoEntry>> dirEntries = const {},
    Map<String, String> fileContents = const {},
    this.failWrites = false,
    this.throwOnListDir = false,
  })  : _entries = entries, // ignore: prefer_initializing_formals
        _dirEntries = dirEntries { // ignore: prefer_initializing_formals
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
}
