import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart';

/// Lists the entities in one [LoreCategory] and opens the tapped entity's card
/// in the [EditorPage] (Story 2.2 — FR5 + "navigate to any card").
///
/// A simple entity (`frank.md`) and an entity folder (`selena/`) are rendered as
/// the **same** kind of row (FR5): same leading icon, same tap. In 2.2 both open
/// the entity's card (`LoreEntry.id`). Story 2.3 will route an entity tap to a
/// detail tree instead; the folder-vs-simple distinction (`entry.tree`) is that
/// story's concern, deliberately not surfaced here.
///
/// The list opens on the snapshot passed at tap-time, then **re-walks the lore
/// model on return from the editor** (AD-10 — the loader owns the model, the UI
/// never patches it) so an edit made here is reflected without backing out to
/// Home (AC3 / FR3). The Home page rescans too when this page is popped.
class CategoryEntitiesPage extends StatefulWidget {
  final RepoStorage storage;
  final LoreCategory category;

  /// The resolved `loreDir`. Model ids are **loreDir-relative** (the fixture
  /// contract), but [RepoStorage] / [EditorPage] are **repo-relative** — the
  /// two must be joined back together before touching storage.
  final String loreDir;

  const CategoryEntitiesPage({
    super.key,
    required this.storage,
    required this.category,
    required this.loreDir,
  });

  @override
  State<CategoryEntitiesPage> createState() => _CategoryEntitiesPageState();
}

class _CategoryEntitiesPageState extends State<CategoryEntitiesPage> {
  /// The entities shown. Seeded from the tap-time snapshot; rebuilt by [_rescan]
  /// on return from the editor.
  late List<LoreEntry> _entries = widget.category.entries;

  /// loreDir-relative model id → repo-relative storage path. Empty [loreDir]
  /// (the repo root *is* the lore folder) leaves the id unchanged.
  String _repoPath(String id) =>
      widget.loreDir.isEmpty ? id : '${widget.loreDir}/$id';

  Future<void> _openEntity(LoreEntry entry) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            EditorPage(storage: widget.storage, path: _repoPath(entry.id)),
      ),
    );
    // The edit may have changed this entity's title (or the files under it) —
    // re-walk so the list reflects it without popping back to Home (AC3/FR3),
    // mirroring the Home page's rescan-on-editor-return.
    if (mounted) await _rescan();
  }

  /// Rebuilds this category's entity list from a fresh walk (AD-10 — model
  /// rebuilt, never patched). An unexpected walk failure leaves the current
  /// list intact rather than stranding the screen (AD-8 at the call site).
  Future<void> _rescan() async {
    try {
      final model = await loadLore(widget.storage, widget.loreDir);
      if (!mounted) return;
      final match =
          categoriesOf(model.entries).where((c) => c.key == widget.category.key);
      setState(() {
        _entries = match.isEmpty ? const [] : match.first.entries;
      });
    } catch (_) {
      // Keep the current list on an unexpected walk failure (AD-8).
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.label)),
      body: _entries.isEmpty
          ? const Center(child: Text('No entities in this category.'))
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final e = _entries[i];
                return ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(e.title),
                  // The id disambiguates same-titled cards and shows where the
                  // entity lives (which `.md` a tap will open).
                  subtitle: Text(e.id),
                  onTap: () => _openEntity(e),
                );
              },
            ),
    );
  }
}
