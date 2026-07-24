/// Dart port of the reference lore loader (`lib/lore.js`), reading through the
/// [RepoStorage] port (AD-3 / AD-9 — no `dart:io` here).
///
/// Layout rules inside `loreDir` (ARCHITECTURE §3.2):
/// - a `.md` file in a category folder is a **simple entity**;
/// - a folder containing `index.md` or `<folder-name>.md` is an **entity
///   folder**: that file is the card, everything else inside is its content tree;
/// - inside an entity, subfolders form a tree of sections; a subfolder's own
///   `<name>.md`/`index.md` is that section's overview;
/// - `<base>.ru.md` / `<base>.en.md` are language variants of one item, merged
///   original-language-first;
/// - `media/` folders are skipped.
///
/// Conformance to `test/fixtures/lore-model/` is the contract (AD-2). Changing
/// behavior here without changing the fixtures is a bug.
library;

import '../storage/storage.dart';
import 'lore_model.dart';

final RegExp _langRe = RegExp(r'\.(ru|en)\.md$', caseSensitive: false);
final RegExp _headingRe = RegExp(r'^#\s+(.+)$', multiLine: true);
final RegExp _aliasRe =
    RegExp(r'^aliases:\s*(.+)$', multiLine: true, caseSensitive: false);
// The marker is a literal ⇄ (U+21C4) — see ARCHITECTURE §3.3.
final RegExp _passageRe = RegExp(r'scene ⇄ passage:\s*"([^"]+)"');
final RegExp _sepRe = RegExp(r'[-_]');

/// Title (first `# heading`, else [fallback]) plus the alias list.
///
/// Aliases are `[title, ...aliases: line]`, empties dropped, deduped with
/// first-seen order preserved. Both the title and each alias are trimmed to
/// drop surrounding whitespace (e.g. `#  Selena `). Note: Dart's `.` does NOT
/// match `\r` (it follows ECMAScript, like the JS reference), so a CRLF heading
/// `# Selena\r\n` already captures `Selena` without the CR — verified by test.
({String title, List<String> aliases}) readTitleAliases(
  String text,
  String fallback,
) {
  final heading = _headingRe.firstMatch(text);
  final title = heading != null ? heading.group(1)!.trim() : fallback;

  final parts = <String>[title];
  final aliasLine = _aliasRe.firstMatch(text);
  if (aliasLine != null) {
    parts.addAll(aliasLine.group(1)!.split(',').map((s) => s.trim()));
  }

  final seen = <String>{};
  final aliases = <String>[];
  for (final a in parts) {
    if (a.isEmpty) continue;
    if (seen.add(a)) aliases.add(a);
  }
  return (title: title, aliases: aliases);
}

/// `relationship-quest-1` → `relationship quest 1`. Only the fallback for a
/// section title; an overview card's own heading wins. Does NOT change case —
/// section titles are shown verbatim (contract decision, applies to Cyrillic
/// and English alike).
String prettify(String seg) => seg.replaceAll(_sepRe, ' ');

/// The `scene ⇄ passage: "..."` target declared in [text], if any.
String? passageOf(String text) => _passageRe.firstMatch(text)?.group(1);

/// Well-known syncer/VCS metadata names (FR16, per AD-5). `.stversions` is the
/// load-bearing one: it holds dated `.md` copies of real files that would
/// otherwise be parsed as bogus entities. Case-insensitive — a Windows-authored
/// repo can sync down `.StVersions`.
///
/// Dart-only: the JS reference has no syncer awareness (addendum §E), and no
/// golden fixture contains these, so this cannot affect fixture conformance.
const Set<String> kSyncerMetadataNames = {
  '.stfolder',
  '.stversions',
  '.stignore',
};

/// True for a known syncer-internal name (case-insensitive).
bool isSyncerMetadata(String name) =>
    kSyncerMetadataNames.contains(name.toLowerCase());

/// Directories the walk never descends into: `media/` (binary assets, shared
/// contract) and **every dot-prefixed folder** — the same rule the browse UI
/// uses (`app/browse_filter.dart`). A 3-name allowlist was too weak: it let the
/// walk descend into `.git`, `.github` (full of `.md`), `.obsidian`, and any
/// future `.st*`, loading their markdown as bogus entities — reachable when the
/// repo root *is* the lore folder. This also covers the app's own `.lore-tmp-*`
/// atomic-write temps (whose skip the storage adapter already promises here).
bool _isSkippedWalkDir(String name) =>
    name == 'media' || name.startsWith('.');

// Syncthing conflict copies: `<base>.sync-conflict-<yyyymmdd>-<hhmmss>-<modid>.md`.
// Anchored to the real shape (dated) so an *authored* file that merely contains
// the substring — e.g. `troubleshooting.sync-conflict-recovery.md` — is NOT
// mistaken for a conflict and silently removed from the model. Case-insensitive
// for case-preserving/insensitive filesystems (Android FUSE, Windows).
final RegExp _conflictCopyRe = RegExp(
  r'\.sync-conflict-\d{8}-\d{6}-[A-Za-z0-9]+\.md$',
  caseSensitive: false,
);

/// True for a Syncthing conflict copy.
///
/// Surfaced, never parsed and never hidden (FR17 / AD-5): the walk routes these
/// to [LoreModel.conflicts] so the author can see and resolve them.
bool isConflictCopy(String name) => _conflictCopyRe.hasMatch(name);

/// Parses [loreDir] (repo-relative) into the entity model, plus any syncer
/// conflict copies found alongside it.
///
/// Returns [LoreModel.empty] when [loreDir] does not exist. Never throws for a
/// missing or unreadable directory — `listDir` already degrades to empty (AD-8).
///
/// The walk is stateless and rebuilt on every call (AD-10 — no cached model, no
/// live watcher); a rescan on resume/refresh simply calls this again.
Future<LoreModel> loadLore(RepoStorage storage, String loreDir) async {
  final loader = _LoreLoader(storage, _normalizeDir(loreDir));
  return loader.run();
}

String _normalizeDir(String p) {
  final parts = p.split('/').where((s) => s.isNotEmpty && s != '.');
  return parts.join('/');
}

String _basename(String path) {
  final i = path.lastIndexOf('/');
  return i == -1 ? path : path.substring(i + 1);
}

String _dirname(String path) {
  final i = path.lastIndexOf('/');
  return i == -1 ? '' : path.substring(0, i);
}

String _stripMd(String name) =>
    name.endsWith('.md') ? name.substring(0, name.length - 3) : name;

/// One language variant collected while grouping a folder's files.
class _Variant {
  final String id;
  final String relDir;
  final String title;
  final String text;
  final String? passage;

  const _Variant({
    required this.id,
    required this.relDir,
    required this.title,
    required this.text,
    required this.passage,
  });
}

class _LoreLoader {
  final RepoStorage storage;

  /// Repo-relative, normalized lore root. Empty means the repo root itself.
  final String loreDir;

  final List<LoreEntry> _entries = [];
  final List<ConflictCopy> _conflicts = [];

  _LoreLoader(this.storage, this.loreDir);

  Future<LoreModel> run() async {
    if (!await storage.exists(loreDir)) return LoreModel.empty;
    await _walkCategory(loreDir, '');
    // Deterministic order, like entries/children[] (Story 2.4's list depends on
    // it); the walk visits conflicts in directory order, which is not stable.
    _conflicts.sort((a, b) => a.id.compareTo(b.id));
    // Hand out read-only views so a UI consumer can't mutate the model (and so
    // the type matches LoreModel.empty's const []).
    return LoreModel(
      entries: List.unmodifiable(_entries),
      conflicts: List.unmodifiable(_conflicts),
    );
  }

  /// Records a conflict copy. Surfaced, never parsed (FR17/AD-5). `relDir` uses
  /// `.` at the lore root, matching `LoreEntry.relDir` so Story 2.4 can join the
  /// two by directory.
  void _recordConflict(String repoPath) {
    final dir = _rel(_dirname(repoPath));
    _conflicts.add(ConflictCopy(
      id: _rel(repoPath),
      name: _basename(repoPath),
      relDir: dir.isEmpty ? '.' : dir,
    ));
  }

  /// Repo-relative path → loreDir-relative id.
  String _rel(String repoPath) {
    if (loreDir.isEmpty) return repoPath;
    if (repoPath == loreDir) return '';
    if (repoPath.startsWith('$loreDir/')) {
      return repoPath.substring(loreDir.length + 1);
    }
    return repoPath;
  }

  Future<void> _walkCategory(String dirPath, String category) async {
    final listed = await storage.listDir(dirPath);
    // The reference relies on readdir order here; entries are re-sorted by id
    // during normalization, so sorting is safe and makes the walk deterministic.
    final sorted = [...listed]..sort((a, b) => a.name.compareTo(b.name));

    for (final item in sorted) {
      if (item.isDirectory) {
        // Never descend into media/ (binary assets) or any dot-prefixed dir
        // (syncer metadata, VCS, temps) — `.stversions` in particular holds
        // `.md` version copies that would otherwise load as bogus entities.
        if (_isSkippedWalkDir(item.name)) continue;

        // index.md wins over <folder-name>.md, matching the reference's
        // ['index.md', name + '.md'].find(exists) precedence — but the card
        // must be a FILE. The reference uses fs.existsSync here, which is true
        // for a directory too, so a folder containing a *subdirectory* named
        // `index.md`/`<name>.md` makes the reference read a directory and throw
        // (EISDIR). We resolve the card from the directory's own listing so a
        // dir masquerading as a card is ignored, not crashed on (AD-8).
        final childFiles = {
          for (final c in await storage.listDir(item.path))
            if (!c.isDirectory) c.name,
        };
        String? card;
        for (final candidate in ['index.md', '${item.name}.md']) {
          if (childFiles.contains(candidate)) {
            card = '${item.path}/$candidate';
            break;
          }
        }

        if (card != null) {
          await _addEntry(card, category.isEmpty ? 'general' : category, item.path);
        } else {
          // No card ⇒ this folder is a nested category, not an entity.
          await _walkCategory(
            item.path,
            category.isEmpty ? item.name : '$category/${item.name}',
          );
        }
      } else if (isConflictCopy(item.name)) {
        // Surfaced, never parsed as an entity (FR17).
        _recordConflict(item.path);
      } else if (item.name.endsWith('.md')) {
        await _addEntry(item.path, category.isEmpty ? 'general' : category, null);
      }
    }
  }

  /// Builds and appends an entry, skipping it if its card read fails (a syncer
  /// race, a vanished file, permission) rather than aborting the whole walk
  /// (AD-8 — malformed/unreadable input degrades, never crashes).
  Future<void> _addEntry(
    String cardPath,
    String category,
    String? folderPath,
  ) async {
    try {
      _entries.add(await _makeEntry(cardPath, category, folderPath));
    } on RepoStorageException {
      // Skip this entity; keep walking.
    }
  }

  Future<LoreEntry> _makeEntry(
    String cardPath,
    String category,
    String? folderPath,
  ) async {
    final text = await storage.read(cardPath);
    final cardBase = _stripMd(_basename(cardPath));
    final ta = readTitleAliases(text, cardBase);

    final children = <LoreChild>[];
    LoreNode? tree;
    if (folderPath != null) {
      tree = await _buildNode(folderPath, cardBase, '', children);
    }

    final relDir = _rel(_dirname(cardPath));
    return LoreEntry(
      id: _rel(cardPath),
      title: ta.title,
      aliases: ta.aliases,
      category: category,
      relDir: relDir.isEmpty ? '.' : relDir,
      text: text,
      tree: tree,
      children: children,
    );
  }

  /// Builds one folder's node, recursively, appending every leaf language file
  /// to [flat] — except the entity card, which is not a sub-entry of itself.
  Future<LoreNode> _buildNode(
    String dirPath,
    String? cardBase,
    String groupPath,
    List<LoreChild> flat,
  ) async {
    final dirName = _basename(dirPath);
    var nodeTitle = groupPath.isEmpty ? '' : prettify(dirName);
    LoreOverview? overview;
    final items = <LoreItem>[];
    final childNodes = <LoreNode>[];

    final listed = await storage.listDir(dirPath);
    final files = <RepoEntry>[];
    final subdirs = <RepoEntry>[];
    for (final e in listed) {
      if (e.isDirectory) {
        if (!_isSkippedWalkDir(e.name)) subdirs.add(e);
      } else if (isConflictCopy(e.name)) {
        // Surfaced, never parsed — it must not reach byBase, so it can never
        // become an item, an overview card, or a `children[]` entry (FR17).
        _recordConflict(e.path);
      } else if (e.name.endsWith('.md')) {
        files.add(e);
      }
    }
    // `flat` order follows this loop and `normalize` does NOT sort children, so
    // the sort is what makes the flattened list deterministic (and matches the
    // goldens). listDir guarantees no ordering of its own.
    files.sort((a, b) => a.name.compareTo(b.name));
    subdirs.sort((a, b) => a.name.compareTo(b.name));

    final byBase = <String, Map<String, _Variant>>{};
    for (final f in files) {
      final m = _langRe.firstMatch(f.name);
      final lang = m != null ? m.group(1)!.toLowerCase() : 'orig';
      final base = _stripMd(f.name.replaceFirst(_langRe, ''));

      // A sub-entry file that can't be read (syncer race, permission) is
      // skipped, not fatal (AD-8) — the rest of the tree still loads.
      final String text;
      try {
        text = await storage.read(f.path);
      } on RepoStorageException {
        continue;
      }
      final title = readTitleAliases(text, base).title;

      (byBase[base] ??= <String, _Variant>{})[lang] = _Variant(
        id: _rel(f.path),
        relDir: _rel(dirPath),
        title: title,
        text: text,
        passage: passageOf(text),
      );

      if (base != cardBase) {
        flat.add(LoreChild(
          id: _rel(f.path),
          title: title,
          group: groupPath,
          text: text,
        ));
      }
    }

    final bases = byBase.keys.toList()..sort();
    for (final base in bases) {
      final langs = byBase[base]!;

      // This folder's own card becomes the overview — unless it is the entity
      // card, which the caller owns.
      if (base == dirName || base == 'index') {
        if (base == cardBase) continue;
        final v = langs['orig'] ?? langs['ru'] ?? langs['en'];
        if (v != null) {
          overview = LoreOverview(id: v.id, text: v.text, relDir: v.relDir);
          nodeTitle = v.title;
        }
        continue;
      }

      final ru = langs['ru'];
      final en = langs['en'];
      final orig = langs['orig'];
      final primary = orig ?? ru ?? en;
      if (primary == null) continue;

      // Original language first; the em dash is U+2014 with spaces.
      final title =
          (ru != null && en != null) ? '${ru.title} — ${en.title}' : primary.title;

      items.add(LoreItem(
        id: groupPath.isEmpty ? base : '$groupPath/$base',
        title: title,
        group: groupPath,
        passage: (ru ?? en ?? orig)!.passage,
        langs: {
          for (final e in langs.entries)
            e.key: LoreLang(
              file: e.value.id,
              relDir: e.value.relDir,
              title: e.value.title,
              text: e.value.text,
            ),
        },
      ));
    }

    for (final sub in subdirs) {
      childNodes.add(await _buildNode(
        sub.path,
        null,
        groupPath.isEmpty ? sub.name : '$groupPath/${sub.name}',
        flat,
      ));
    }

    return LoreNode(
      name: dirName,
      title: nodeTitle,
      overview: overview,
      items: items,
      children: childNodes,
    );
  }
}
