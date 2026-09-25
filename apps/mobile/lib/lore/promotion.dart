/// Where a simple entity lands when it is promoted to an entity folder
/// (FR26, Story 2.17; naming rule from Story 5.6).
///
/// **Folders never carry a language suffix** (KseiPo, 2026-09-24). A card named
/// `<slug>.md`, `<slug>.ru.md` or `<slug>.en.md` always promotes to
/// `<slug>/<slug>.md`. The card inside must lose the suffix too, not just the
/// folder: the loader only recognizes an entity folder whose card is named
/// exactly `index.md` or `<folder-name>.md` (`lore_loader.dart`'s
/// `_walkCategory`). A `frank/` holding only `frank.ru.md` would be read as a
/// sub-category, with the card and every sub-entry scattered into loose
/// entities. Entity-folder cards are language-neutral by design, since the
/// loader never pairs them.
///
/// The stripped name is exactly the loader's own `base` for that file: only
/// the final language suffix goes (`frank.ru.en.md` → `frank.ru`), matched
/// case-insensitively. A name without a language suffix keeps Story 2.17's
/// plain `.md` strip.
///
/// Pure Dart: no Flutter, no `dart:io` (AD-9). **Total** (AD-8): string
/// operations only, never throws.
library;

/// Mirrors `lore_loader.dart`'s private `_langRe` exactly. Keep the two in
/// sync. Duplicated rather than imported because the loader is pinned by the
/// shared golden fixtures (contract gate), the same
/// duplication-with-a-comment precedent as the loader's own
/// `_kAiPromptConfigFileName`.
final RegExp _langSuffixRe = RegExp(r'\.(ru|en)\.md$', caseSensitive: false);

/// The loreDir-relative folder id and card id a simple entity at [entryId]
/// (loreDir-relative, forward-slash normalized, e.g. `characters/frank.ru.md`)
/// promotes to, e.g. `characters/frank` and `characters/frank/frank.md`.
({String folderId, String cardId}) promotionTargetOf(String entryId) {
  final lastSlash = entryId.lastIndexOf('/');
  final dirId = lastSlash == -1 ? '' : entryId.substring(0, lastSlash);
  final fileName = lastSlash == -1 ? entryId : entryId.substring(lastSlash + 1);

  final String slug;
  if (_langSuffixRe.hasMatch(fileName)) {
    slug = fileName.replaceFirst(_langSuffixRe, '');
  } else if (fileName.endsWith('.md')) {
    slug = fileName.substring(0, fileName.length - 3);
  } else {
    slug = fileName;
  }

  final folderId = dirId.isEmpty ? slug : '$dirId/$slug';
  return (folderId: folderId, cardId: '$folderId/$slug.md');
}
