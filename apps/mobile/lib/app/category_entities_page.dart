import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart';
import 'entity_navigation.dart';

/// Lists the entities in one [LoreCategory] and opens the tapped entity (Story
/// 2.2 — FR5 + "navigate to any card"; Story 2.3 — detail tree).
///
/// A simple entity (`frank.md`) and an entity folder (`selena/`) are rendered as
/// the **same** kind of row (FR5): same leading icon, same tap. The tap
/// *destination* branches (Story 2.3): an entity folder (`entry.tree != null`)
/// opens the [EntityDetailPage] outline; a simple entity opens its card directly
/// in the [EditorPage], since a flat card has no tree to navigate.
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
    await navigateToEntity(context,
        storage: widget.storage, entry: entry, loreDir: widget.loreDir);
    // The edit may have changed this entity's title (or the files under it) —
    // re-walk so the list reflects it without popping back to Home (AC3/FR3),
    // mirroring the Home page's rescan-on-editor-return.
    if (mounted) await _rescan();
  }

  Future<void> _createEntity() async {
    final title = await _showCreateEntityDialog(context);
    if (title == null || !mounted) return;

    final slug = _slugify(title);
    if (slug.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Title produces an invalid filename.')),
        );
      }
      return;
    }

    final categoryFolder = _repoPath(widget.category.key);
    final filePath = '$categoryFolder/$slug.ru.md';

    try {
      if (await widget.storage.exists(filePath) ||
          await widget.storage.exists('$categoryFolder/$slug.md') ||
          await widget.storage.exists('$categoryFolder/$slug.en.md')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An entity with this name already exists.')),
        );
        return;
      }
      await widget.storage.writeAtomic(filePath, '# $title\n');
    } on RepoStorageException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create the entity.')),
        );
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create the entity.')),
        );
      }
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EditorPage(
          storage: widget.storage,
          path: filePath,
          loreDir: widget.loreDir,
        ),
      ),
    );
    if (mounted) await _rescan();
  }

  /// Entity ids currently mid-promotion — guards against a double-tap
  /// launching two concurrent promotions of the same row (Review fix): the
  /// second `movePath` would throw because the source is already gone,
  /// surfacing a spurious failure for an operation that actually succeeded.
  final Set<String> _promotingIds = {};

  /// Promotes a simple entity (`entry.tree == null`) to an entity folder
  /// (`<slug>.md` → `<slug>/<slug>.md`, FR26). A single atomic rename — see
  /// [RepoStorage.movePath] — so the card's bytes are preserved exactly with
  /// no re-encode step.
  ///
  /// The pre-flight guard only refuses an existing **card** at the target
  /// (`newCardPath`) — not an existing **folder** there (Review fix). Only the
  /// card colliding is actually dangerous (`movePath` would silently
  /// overwrite it); refusing on the folder too would mean a single transient
  /// failure between `ensureDir` succeeding and `movePath` failing leaves an
  /// orphaned empty folder that then permanently blocks every retry.
  /// `ensureDir` is idempotent, so proceeding into an existing (possibly
  /// orphaned, possibly legitimately pre-existing) folder is safe.
  Future<void> _promoteEntity(LoreEntry entry) async {
    // Defensive: the trailing icon is only ever shown for a simple entity,
    // but don't rely solely on that — a future call site must not be able to
    // silently orphan an existing entity folder's sub-entries (Review fix).
    if (entry.tree != null || _promotingIds.contains(entry.id)) return;

    final confirmed = await _showPromoteConfirmDialog(context, entry.title);
    if (confirmed != true || !mounted) return;

    setState(() => _promotingIds.add(entry.id));
    try {
      final lastSlash = entry.id.lastIndexOf('/');
      final dirId = lastSlash == -1 ? '' : entry.id.substring(0, lastSlash);
      final fileName =
          lastSlash == -1 ? entry.id : entry.id.substring(lastSlash + 1);
      final slug =
          fileName.endsWith('.md') ? fileName.substring(0, fileName.length - 3) : fileName;
      final newFolderId = dirId.isEmpty ? slug : '$dirId/$slug';
      final newCardId = '$newFolderId/$slug.md';

      final cardPath = _repoPath(entry.id);
      final newFolderPath = _repoPath(newFolderId);
      final newCardPath = _repoPath(newCardId);

      try {
        if (await widget.storage.exists(newCardPath)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A folder with this name already exists.')),
          );
          return;
        }
        await widget.storage.ensureDir(newFolderPath);
        await widget.storage.movePath(cardPath, newCardPath);
      } on RepoStorageException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to promote this entity.')),
          );
        }
        return;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to promote this entity.')),
          );
        }
        return;
      }

      if (mounted) await _rescan();
    } finally {
      if (mounted) setState(() => _promotingIds.remove(entry.id));
    }
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
                  // Only a simple entity (no tree) can be promoted — a folder
                  // entity already is one (FR26).
                  trailing: e.tree == null
                      ? IconButton(
                          icon: const Icon(Icons.create_new_folder_outlined),
                          tooltip: 'Promote to folder',
                          // Disabled while this row's own promotion is in
                          // flight — guards a fast double-tap (Review fix).
                          onPressed: _promotingIds.contains(e.id)
                              ? null
                              : () => _promoteEntity(e),
                        )
                      : null,
                  onTap: () => _openEntity(e),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: _createEntity,
        tooltip: 'Create entity',
        child: const Icon(Icons.add),
      ),
    );
  }
}

String _slugify(String title) {
  return title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9\-]'), '')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

Future<String?> _showCreateEntityDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New entity'),
      content: TextField(
        key: const Key('entity-title-field'),
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Title',
          hintText: 'e.g. Raven\'s Nest',
        ),
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('create-entity-confirm'),
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

Future<bool?> _showPromoteConfirmDialog(BuildContext context, String title) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Promote to folder?'),
      content: Text(
        '"$title" will become a folder that can hold events and quests. '
        'The card itself is unchanged — just moved.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('promote-entity-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Promote'),
        ),
      ],
    ),
  );
}
