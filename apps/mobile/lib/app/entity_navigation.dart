import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart';
import 'entity_detail_page.dart';

/// Pushes the screen for [entry] (Story 2.3 / Story 3.2, FR19): an entity
/// folder (`entry.tree != null`) opens the detail-tree outline, a simple
/// entity opens its card directly in the editor (no tree to navigate).
///
/// The **one** place this branch rule lives (AD-7) — originally
/// `CategoryEntitiesPage._openEntity`, reused verbatim (not reimplemented) by
/// every wikilink-tap-navigation call site (`EditorPage`, `PairedEditorPage`,
/// `UndeterminedLanguagePage`) added in Story 3.2. (Review fix: this used to
/// be copy-pasted identically into all three.)
Future<void> navigateToEntity(
  BuildContext context, {
  required RepoStorage storage,
  required LoreEntry entry,
  required String loreDir,
}) {
  final repoPath = loreDir.isEmpty ? entry.id : '$loreDir/${entry.id}';
  final Widget destination = entry.tree != null
      ? EntityDetailPage(storage: storage, entry: entry, loreDir: loreDir)
      : EditorPage(storage: storage, path: repoPath, loreDir: loreDir);
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => destination),
  );
}
