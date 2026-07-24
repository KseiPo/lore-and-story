import 'dart:convert';

import '../storage/storage.dart';

/// Repo-root filename holding per-project configuration (ARCHITECTURE.md §3.4).
const String kProjectConfigFile = 'lore-story.json';

/// A `loreDir` value longer than this is treated as invalid (falls back to
/// [ProjectConfig.defaults]) — guards against a pathological config value being
/// read and rendered with no bound.
const int _maxLoreDirLength = 512;

/// Resolved per-project configuration.
///
/// v0.1 reads only [loreDir] — the folder under the repo root that holds lore
/// entries. Other `lore-story.json` keys (`storyDir`, `scenesDir`, `codeDirs`,
/// `linkMacros`, `dynamicTags`) are twee/desktop concerns and are ignored here.
/// Pure value type — no I/O.
class ProjectConfig {
  /// Repo-relative folder containing lore entries. Default: `''` — the repo
  /// root itself.
  ///
  /// On mobile the author syncs (and picks) the lore folder directly, so the
  /// chosen root **is** the lore folder; there is no `lore/` subfolder level.
  /// A `lore-story.json` may still point `loreDir` at a subfolder for the
  /// whole-repo-sync case (the desktop layout), but the default is the root —
  /// deliberately different from the desktop reference's `lore` default, which
  /// assumes the whole repo is present.
  final String loreDir;

  const ProjectConfig({this.loreDir = ''});

  /// Config used when `lore-story.json` is missing, invalid, or under-specified.
  static const ProjectConfig defaults = ProjectConfig();

  /// Parses raw `lore-story.json` text, best-effort. **Never throws**: any
  /// failure or unexpected shape falls back to [defaults] (FR2 / AD-8).
  factory ProjectConfig.parse(String raw) {
    // The entire body is guarded by a catch-all (not just `on FormatException`):
    // `jsonDecode` is a recursive-descent parser that can raise a
    // `StackOverflowError` on pathological (e.g. deeply nested) input, and
    // `Error` subtypes are NOT caught by an `Exception`-typed clause. FR2/AD-8
    // require this to never throw regardless of what kind of throwable a
    // malformed file produces.
    try {
      // Strip a single leading BOM before decoding. Windows editors/PowerShell
      // write one, and `RepoStorage.read` re-attaches it (to keep writes
      // byte-exact), so a BOM'd config would otherwise fail `jsonDecode` and
      // silently fall back to defaults. This guard is load-bearing
      // (project-context.md), not cosmetic.
      final cleaned = raw.startsWith('\u{FEFF}') ? raw.substring(1) : raw;

      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) return defaults;

      final lore = decoded['loreDir'];
      if (lore is! String) return defaults;

      // Accept the JS POC's `"./lore"` form as well as §3.4's `"lore"`; strip
      // ALL leading `./` segments (not just one — `"././lore"` fully
      // normalizes to `"lore"`) and let `RepoStorage` path normalization
      // handle the rest.
      var normalized = lore.trim();
      while (normalized.startsWith('./')) {
        normalized = normalized.substring(2);
      }
      // A bare '.' means the repo root — the same as the default. Normalize it
      // so the resolved value (and the UI/paths built from it) never carry a
      // literal '.'.
      if (normalized == '.') normalized = '';
      if (normalized.isEmpty || normalized.length > _maxLoreDirLength) {
        return defaults;
      }

      return ProjectConfig(loreDir: normalized);
    } catch (_) {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectConfig && other.loreDir == loreDir;

  @override
  int get hashCode => loreDir.hashCode;

  @override
  String toString() => 'ProjectConfig(loreDir: $loreDir)';
}

/// Reads and resolves `lore-story.json` from the repo root via [storage].
///
/// A missing file, read error, or invalid content resolves to
/// [ProjectConfig.defaults] — this **never throws and never blocks** (FR2).
/// Re-read on every call (no caching), so an edited config takes effect on the
/// next repo open (AD-1 / re-read-per-open).
Future<ProjectConfig> resolveProjectConfig(RepoStorage storage) async {
  try {
    final raw = await storage.read(kProjectConfigFile);
    return ProjectConfig.parse(raw);
  } catch (_) {
    // Missing file, I/O error, or any other read failure → defaults. A
    // catch-all (not just `on RepoStorageException`) so a storage
    // implementation that surfaces a different failure type still can't break
    // FR2's "never blocks" guarantee.
    return ProjectConfig.defaults;
  }
}
