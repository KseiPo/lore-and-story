import 'dart:convert';
import 'dart:io';

import 'repo_storage.dart';

/// All-files (`dart:io`) implementation of [RepoStorage].
///
/// This is the **only** file in the app permitted to import `dart:io` (AD-3 /
/// AD-9). It translates repo-relative, forward-slash paths to real OS paths
/// under [rootPath] and back, so callers stay platform-agnostic and IDs remain
/// forward-slash normalized even on Android.
class AllFilesRepoStorage implements RepoStorage {
  /// Absolute, OS-native root path (e.g. `/storage/emulated/0/story-repo`).
  final String _root;

  AllFilesRepoStorage(String rootPath) : _root = _stripTrailingSep(rootPath);

  @override
  String get rootPath => _root;

  @override
  Future<List<RepoEntry>> listDir(String path) async {
    final repoDir = _normalizeRepoPath(path);
    final dir = Directory(_toOsPath(repoDir));
    try {
      if (!await dir.exists()) return const [];
      final entries = <RepoEntry>[];
      await for (final e in dir.list(followLinks: false)) {
        final name = _basename(e.path);
        final childRepoPath = repoDir.isEmpty ? name : '$repoDir/$name';
        entries.add(RepoEntry(
          name: name,
          path: childRepoPath,
          isDirectory: e is Directory,
        ));
      }
      return entries;
    } on FileSystemException {
      // Permission denied / transient I/O — degrade to empty, never throw.
      return const [];
    }
  }

  @override
  Future<String> read(String path) async {
    final osPath = _toOsPath(_normalizeRepoPath(path));
    try {
      // Explicit UTF-8: never rely on a platform-default encoding (AD-4).
      return await File(osPath).readAsString(encoding: utf8);
    } on FileSystemException catch (e) {
      throw RepoStorageException(e.message, path, osErrorCode: e.osError?.errorCode);
    }
  }

  @override
  Future<void> writeAtomic(String path, String contents) async {
    final target = _toOsPath(_normalizeRepoPath(path));
    // Temp file in the SAME directory so the rename is an atomic move on the
    // same filesystem (the syncer never sees a partial file).
    final tmp = '$target.tmp-${DateTime.now().microsecondsSinceEpoch}';
    final tmpFile = File(tmp);
    try {
      // Story 1.2: harden byte-exactness (preserve EOL + trailing newline,
      // byte-exact round-trip, fsync). This is the minimal atomic seed only.
      await tmpFile.writeAsString(contents, encoding: utf8, flush: true);
      await tmpFile.rename(target);
    } on FileSystemException catch (e) {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } on FileSystemException {
          // best-effort cleanup
        }
      }
      throw RepoStorageException(e.message, path, osErrorCode: e.osError?.errorCode);
    }
  }

  @override
  Future<bool> exists(String path) async {
    final osPath = _toOsPath(_normalizeRepoPath(path));
    return await File(osPath).exists() || await Directory(osPath).exists();
  }

  // --- path translation --------------------------------------------------

  /// Repo-relative (forward-slash) → absolute OS path under [_root].
  String _toOsPath(String repoRelative) {
    final normalized = _normalizeRepoPath(repoRelative);
    if (normalized.isEmpty) return _root;
    final osRel = normalized.replaceAll('/', Platform.pathSeparator);
    return '$_root${Platform.pathSeparator}$osRel';
  }

  /// Normalizes any input to a clean, forward-slash, repo-relative path that
  /// cannot escape the root: backslashes → slashes; drop empty, `.`, and `..`
  /// segments; no leading/trailing slash. This neutralizes absolute, backslash,
  /// and parent-traversal (`../`) inputs so a "repo-relative" path can never
  /// resolve outside [rootPath].
  static String _normalizeRepoPath(String p) {
    return p
        .replaceAll('\\', '/')
        .split('/')
        .where((seg) => seg.isNotEmpty && seg != '.' && seg != '..')
        .join('/');
  }

  static String _basename(String osPath) {
    final norm = osPath.replaceAll('\\', '/');
    final i = norm.lastIndexOf('/');
    return i == -1 ? norm : norm.substring(i + 1);
  }

  static String _stripTrailingSep(String p) {
    var s = p;
    while (s.length > 1 && (s.endsWith('/') || s.endsWith('\\'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}
