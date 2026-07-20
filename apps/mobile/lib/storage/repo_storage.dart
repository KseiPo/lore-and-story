/// The `storage/` slice's public port.
///
/// Pure Dart — **no** `dart:io`, no Flutter, no network imports live here
/// (AD-9). Everything that needs the filesystem depends on [RepoStorage], never
/// on `dart:io` or the storage permission directly (AD-3 / NFR3). That is what
/// keeps a future SAF backend or app-private+git working copy a *root-path swap,
/// not a rewrite*.
library;

/// One immediate child returned by [RepoStorage.listDir].
class RepoEntry {
  /// The last path segment, e.g. `selena.md` or `characters`.
  final String name;

  /// Repo-relative, **forward-slash-normalized** path, e.g.
  /// `characters/selena` — never a backslash, even on Android.
  final String path;

  /// True when this entry is a directory.
  final bool isDirectory;

  const RepoEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  @override
  bool operator ==(Object other) =>
      other is RepoEntry &&
      other.name == name &&
      other.path == path &&
      other.isDirectory == isDirectory;

  @override
  int get hashCode => Object.hash(name, path, isDirectory);

  @override
  String toString() =>
      'RepoEntry(name: $name, path: $path, isDirectory: $isDirectory)';
}

/// Raised for storage failures (missing path, permission denied, I/O error).
///
/// Defined in the pure port so callers can handle failures **without** importing
/// `dart:io` — adapters translate platform exceptions (e.g.
/// `FileSystemException`) into this type, keeping `dart:io` behind the seam.
class RepoStorageException implements Exception {
  /// Human-readable description of what failed.
  final String message;

  /// The repo-relative path involved, when known.
  final String path;

  /// The underlying OS error code (errno), when known. Lets callers
  /// distinguish causes — e.g. not-found (ENOENT) from permission-denied
  /// (EACCES) — without importing `dart:io`.
  final int? osErrorCode;

  const RepoStorageException(this.message, this.path, {this.osErrorCode});

  @override
  String toString() => 'RepoStorageException($path): $message'
      '${osErrorCode != null ? ' (errno $osErrorCode)' : ''}';
}

/// Abstraction over the repo's filesystem.
///
/// Paths are **repo-relative and forward-slash normalized**; the empty string
/// (or `.`) denotes the repo root. Implementations translate these to real OS
/// paths under the configured root.
abstract interface class RepoStorage {
  /// The absolute root this storage is anchored at (real OS path).
  String get rootPath;

  /// Lists the immediate children of the directory at [path]. Order is
  /// unspecified. A missing *or unreadable* directory yields an empty list
  /// (never throws), so browsing degrades gracefully (AD-8). Callers that must
  /// distinguish "gone" from "empty" (e.g. validating a remembered root) should
  /// call [exists] rather than inferring it from an empty list.
  Future<List<RepoEntry>> listDir(String path);

  /// Reads the file at [path] as UTF-8 text.
  ///
  /// Throws [RepoStorageException] if the file is missing or unreadable.
  Future<String> read(String path);

  /// Writes [contents] to [path] atomically: a temp file in the **same
  /// directory** followed by a rename, so the external syncer never observes a
  /// partial file.
  ///
  /// NOTE: the byte-exact / EOL-preserving guarantees (AD-4 / NFR1) are hardened
  /// in **Story 1.2**. This story only requires the atomic temp+rename seam to
  /// exist. Throws [RepoStorageException] on failure.
  Future<void> writeAtomic(String path, String contents);

  /// Whether a file or directory exists at [path].
  Future<bool> exists(String path);
}
