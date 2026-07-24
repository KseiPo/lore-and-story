/// The lore read-model — the Dart side of the contract pinned by the shared
/// golden fixtures in `test/fixtures/lore-model/` (AD-2).
///
/// The field shapes here mirror the reference implementation (`lib/lore.js`)
/// exactly, because `normalize.js` projects them straight into `expected.json`.
/// Do not "improve" the shape: a rename here is a contract change that must go
/// fixtures-first and be followed by both implementations.
///
/// Pure Dart — no `dart:io`, no Flutter (AD-9). All paths are **relative to
/// `loreDir`** and forward-slash normalized, even on Android.
library;

/// The result of one walk: the entity model plus anything the walk surfaced
/// alongside it.
///
/// [conflicts] is **Dart-only** — the JS reference has no syncer awareness
/// (addendum §E), it is not part of `normalize`, and no golden fixture pins it.
/// Only [entries] is covered by the shared contract.
class LoreModel {
  /// The entity model — the shape pinned by the golden fixtures.
  final List<LoreEntry> entries;

  /// Syncthing conflict copies found during the walk. Surfaced so the author can
  /// resolve them (FR17); never parsed as content, never silently dropped.
  final List<ConflictCopy> conflicts;

  const LoreModel({required this.entries, required this.conflicts});

  static const LoreModel empty = LoreModel(entries: [], conflicts: []);
}

/// A `*.sync-conflict-*.md` file found during the walk.
class ConflictCopy {
  /// loreDir-relative path, forward-slash normalized.
  final String id;

  /// The filename, e.g. `selena.sync-conflict-20240612-093000-K3F9AAA.md`.
  final String name;

  /// loreDir-relative directory holding it.
  final String relDir;

  const ConflictCopy({
    required this.id,
    required this.name,
    required this.relDir,
  });

  @override
  bool operator ==(Object other) =>
      other is ConflictCopy &&
      other.id == id &&
      other.name == name &&
      other.relDir == relDir;

  @override
  int get hashCode => Object.hash(id, name, relDir);

  @override
  String toString() => 'ConflictCopy($id)';
}

/// One lore entity: a simple `.md` card, or an entity folder with a content
/// tree.
class LoreEntry {
  /// loreDir-relative path of the card file, e.g. `characters/selena/selena.md`.
  final String id;

  /// First `# heading` in the card, falling back to the filename slug.
  final String title;

  /// `[title, ...aliases:]`, deduped, first-seen order preserved. Doubles as the
  /// AI translation glossary in Epic 4.
  final List<String> aliases;

  /// Folder path under `loreDir` (`characters`, `characters/secondary`), or
  /// `general` for a card sitting directly in `loreDir`.
  final String category;

  /// loreDir-relative directory holding the card; `.` at the lore root.
  final String relDir;

  /// Raw card text, exactly as decoded.
  final String text;

  /// Content tree for an entity folder; null for a simple entity.
  final LoreNode? tree;

  /// Flat list of every sub-entry file beneath the entity — **excluding the
  /// entity's own card** (ARCHITECTURE §3.2).
  final List<LoreChild> children;

  const LoreEntry({
    required this.id,
    required this.title,
    required this.aliases,
    required this.category,
    required this.relDir,
    required this.text,
    required this.tree,
    required this.children,
  });
}

/// A folder in an entity's content tree (the entity root, or a section like
/// `events/` or `quests/<quest>/`).
class LoreNode {
  /// The folder's own name.
  final String name;

  /// Section title: the overview card's `# heading` when one exists, else the
  /// prettified folder name. Empty at the entity root.
  final String title;

  /// This folder's own card (`<folder-name>.md` or `index.md`), when present.
  final LoreOverview? overview;

  /// Entries directly in this folder, language variants merged.
  final List<LoreItem> items;

  /// Nested sections.
  final List<LoreNode> children;

  const LoreNode({
    required this.name,
    required this.title,
    required this.overview,
    required this.items,
    required this.children,
  });
}

/// A folder's own card.
class LoreOverview {
  final String id;
  final String text;
  final String relDir;

  const LoreOverview({
    required this.id,
    required this.text,
    required this.relDir,
  });
}

/// One entry in a folder, with its language variants merged.
class LoreItem {
  /// Group-qualified slug, e.g. `quests/relationship-quest-1/01-hobby`.
  final String id;

  /// `"<ru> — <en>"` when both languages exist (original first), else the
  /// primary variant's title.
  final String title;

  /// Subfolder path within the entity; empty string at the entity root.
  final String group;

  /// `scene ⇄ passage` target, when the text declares one.
  final String? passage;

  /// Variants keyed by `ru` / `en` / `orig`.
  final Map<String, LoreLang> langs;

  const LoreItem({
    required this.id,
    required this.title,
    required this.group,
    required this.passage,
    required this.langs,
  });
}

/// One language variant of an item.
class LoreLang {
  /// loreDir-relative path of this variant's file. (Named `file` to match the
  /// contract; the reference stores the relative id here, not an absolute path.)
  final String file;

  final String relDir;
  final String title;
  final String text;

  const LoreLang({
    required this.file,
    required this.relDir,
    required this.title,
    required this.text,
  });
}

/// A flattened sub-entry file beneath an entity.
class LoreChild {
  final String id;
  final String title;

  /// Subfolder path within the entity; empty string at the entity root.
  final String group;

  final String text;

  const LoreChild({
    required this.id,
    required this.title,
    required this.group,
    required this.text,
  });
}
