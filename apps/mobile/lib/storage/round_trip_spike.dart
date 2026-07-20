import 'repo_storage.dart';

/// Outcome of a headless read → write-back → read round-trip. Never carries an
/// unhandled throw — a failure is captured in [detail] with [identical] = false.
class SpikeResult {
  /// The repo-relative path that was round-tripped (or attempted).
  final String path;

  /// True only when the file is well-formed UTF-8 and the write-back reproduced
  /// it exactly (a byte-safe round-trip).
  final bool identical;

  /// Human-readable note: a caught error message, or why the round-trip is not
  /// byte-safe (e.g. malformed input). Null on a clean success.
  final String? detail;

  const SpikeResult({required this.path, required this.identical, this.detail});
}

/// Proves the storage + sync write loop headless: read a file, write it back
/// unchanged via [RepoStorage.writeAtomic], re-read, and report whether it
/// round-tripped byte-safely. Never throws (NFR7) — read/write failures are
/// returned as [SpikeResult.detail].
class RoundTripSpike {
  final RepoStorage storage;

  const RoundTripSpike(this.storage);

  Future<SpikeResult> run(String path) async {
    try {
      final before = await storage.read(path);
      // A replacement char (U+FFFD) means the source had invalid UTF-8 that
      // decoded lossily — writing `before` back would CORRUPT the file. Never
      // write in that case; report and bail. (Conservative: a well-formed file
      // that genuinely contains U+FFFD is also skipped, which is the safe side.)
      if (before.contains('\u{FFFD}')) {
        return SpikeResult(
          path: path,
          identical: false,
          detail: 'File contains invalid UTF-8 (replacement chars) — skipped '
              'write-back to avoid corrupting it.',
        );
      }
      await storage.writeAtomic(path, before);
      final after = await storage.read(path);
      return SpikeResult(
        path: path,
        identical: before == after,
        detail: before == after ? null : 'Re-read differs from what was written.',
      );
    } on RepoStorageException catch (e) {
      return SpikeResult(path: path, identical: false, detail: e.toString());
    }
  }
}

/// Breadth-first search for the first non-directory entry whose name satisfies
/// [match], starting at the repo root. Bounded by [maxNodes] so a huge repo
/// cannot make the debug trigger run away. Returns null if none is found.
Future<String?> findFirstMatching(
  RepoStorage storage,
  bool Function(String name) match, {
  int maxNodes = 5000,
}) async {
  final queue = <String>[''];
  var visited = 0;
  while (queue.isNotEmpty && visited < maxNodes) {
    final dir = queue.removeAt(0);
    for (final e in await storage.listDir(dir)) {
      visited++;
      if (!e.isDirectory) {
        if (match(e.name)) return e.path;
      } else if (!e.name.startsWith('.') && e.name != 'media') {
        // Never descend into syncer control/versioning dirs (.stfolder,
        // .stversions), other dot-dirs, temp residue, or media/ — the app must
        // not touch files inside them (matches the Story 2.1b walk contract).
        queue.add(e.path);
      }
    }
  }
  return null;
}
