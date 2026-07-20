import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
      final bytes = await File(osPath).readAsBytes();
      // Best-effort UTF-8: invalid bytes become U+FFFD rather than throwing, so
      // a malformed file still opens (NFR7 / AD-8). Consequently a malformed
      // file is NOT guaranteed byte-exact on write-back — acceptable, since the
      // project's real files are well-formed UTF-8 (see the port doc + story).
      final decoded = utf8.decode(bytes, allowMalformed: true);
      // `utf8.decode` strips exactly ONE leading BOM. Windows editors/PowerShell
      // on this project write BOMs, so re-attach one as U+FEFF to keep the
      // round-trip byte-exact (utf8.encode re-emits EF BB BF). Always prepend
      // when the raw bytes carried a BOM — do NOT guard on
      // `!decoded.startsWith(bom)`, which would drop a BOM for a file that
      // legitimately begins with two (the second survives decode as U+FEFF, so
      // prepending the stripped one restores the exact byte count).
      final hasBom = bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;
      return hasBom ? '\u{FEFF}$decoded' : decoded;
    } on FileSystemException catch (e) {
      // A missing file or I/O error still fails loudly — only *content* decoding
      // is made total, not not-found.
      throw RepoStorageException(e.message, path, osErrorCode: e.osError?.errorCode);
    }
  }

  @override
  Future<void> writeAtomic(String path, String contents) async {
    final normalized = _normalizeRepoPath(path);
    // An empty path denotes the repo root — not a file. Refuse it: otherwise
    // `_dirname(_root)` is the *parent* of the root and the temp/sweep would
    // touch files outside the sandbox.
    if (normalized.isEmpty) {
      throw RepoStorageException('cannot write to an empty path (the repo root)', path);
    }
    final target = _toOsPath(normalized);
    final dir = _dirname(target);

    // Temp name scoped to THIS target file: distinctive, hidden, collision-proof,
    // in the SAME directory so the rename is an atomic same-filesystem move the
    // syncer can't observe as a partial file. The per-target `.lore-tmp-<base>-`
    // prefix means a sweep only touches this file's own orphans, so a concurrent
    // write to a *different* file in the same directory is never disturbed.
    final tmpPrefix = '$_tmpPrefix${_basename(target)}-';

    // Best-effort: clear stale temps THIS target left from an interrupted prior
    // write, so they never accumulate or get propagated by the syncer (AD-5).
    // Sweeping never fails the write.
    await _sweepStaleTemps(dir, tmpPrefix);

    final tmpName =
        '$tmpPrefix${DateTime.now().microsecondsSinceEpoch}-${_rand.nextInt(1 << 31)}';
    final tmpFile = File('$dir${Platform.pathSeparator}$tmpName');
    try {
      // Byte-exact: canonical UTF-8 encoded and written verbatim — no newline
      // translation, no BOM insert/strip, no trimming. EOL and the trailing
      // newline live in `contents` and are preserved (AD-4 / NFR1). Flush so the
      // bytes are durable before the atomic rename.
      await tmpFile.writeAsBytes(utf8.encode(contents), flush: true);
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

  /// Deletes files in [osDir] whose name starts with [prefix] (this target's
  /// own temp prefix). Best effort — never throws; a sweep failure must not fail
  /// the caller's write, and scoping to one target's prefix avoids disturbing a
  /// concurrent write to a different file in the same directory.
  Future<void> _sweepStaleTemps(String osDir, String prefix) async {
    final dir = Directory(osDir);
    try {
      if (!await dir.exists()) return;
      await for (final e in dir.list(followLinks: false)) {
        if (e is File && _basename(e.path).startsWith(prefix)) {
          try {
            await e.delete();
          } on FileSystemException {
            // best-effort
          }
        }
      }
    } on FileSystemException {
      // best-effort — sweeping is never allowed to fail a write
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

  /// Parent directory of an absolute OS path (uses the platform separator).
  static String _dirname(String osPath) {
    final i = osPath.lastIndexOf(Platform.pathSeparator);
    return i == -1 ? osPath : osPath.substring(0, i);
  }

  static String _stripTrailingSep(String p) {
    var s = p;
    while (s.length > 1 && (s.endsWith('/') || s.endsWith('\\'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// Prefix for the atomic-write temp file: hidden, distinctive, and greppable
  /// so orphans can be swept and (Epic 2) skipped by the syncer-aware walk.
  static const String _tmpPrefix = '.lore-tmp-';
  static final Random _rand = Random();
}
