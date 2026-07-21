import '../storage/storage.dart';

/// Which repo entries a browsing UI should hide.
///
/// This is **browsing-UI policy**, deliberately kept in `app/` rather than in
/// the pure `RepoStorage` port: `listDir` stays a faithful, unfiltered
/// directory listing, and each surface applies the policy it needs.
///
/// The rule is deliberately simple — hide every dot-prefixed (hidden) entry,
/// plus `media/`:
///
/// * **Dot-prefixed**: covers Syncthing's own folders (`.stfolder`,
///   `.stversions`, `.stignore`), this app's atomic-write temp files
///   (`.lore-tmp-*`), `.git`, and anything else conventionally hidden. A single
///   rule beats a maintained list of special cases. Consequence to be aware of:
///   a dot-prefixed folder also can't be chosen as a repo root, and legitimate
///   dot-files aren't editable in-app.
/// * **`media/`**: binary assets, skipped by the loader walk per
///   ARCHITECTURE.md §3.2 and the Story 2.1b walk contract. Opening a binary
///   here would lossily decode it and destroy it on save.
///
/// Deliberately NOT hidden: `*.sync-conflict-*` copies. FR17 requires those to
/// be *surfaced with a badge*, never hidden; the badge UI is Epic 2 / Story 2.4.
bool isHiddenBrowseEntry(RepoEntry entry) =>
    entry.name.startsWith('.') || (entry.isDirectory && entry.name == 'media');
