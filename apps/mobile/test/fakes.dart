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
class FakeRepoStorage implements RepoStorage {
  @override
  final String rootPath;
  final List<RepoEntry> _entries;

  FakeRepoStorage(this.rootPath, {List<RepoEntry> entries = const []})
      : _entries = entries; // ignore: prefer_initializing_formals

  @override
  Future<List<RepoEntry>> listDir(String path) async =>
      path.isEmpty ? List.of(_entries) : const [];

  @override
  Future<String> read(String path) async => '';

  @override
  Future<void> writeAtomic(String path, String contents) async {}

  @override
  // The root ('') exists; no specific child files are modeled.
  Future<bool> exists(String path) async => path.isEmpty;
}
