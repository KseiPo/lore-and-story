import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart';

/// The entity **card on top**, then its folder-named sections (Events, Quests)
/// with their items, nested sections rendered nested — the navigable outline of
/// an entity folder (Story 2.3, FR6). Every leaf (the card, a sub-entry, a
/// scene, a section's overview) taps into the [EditorPage].
///
/// The model already excludes `media/` and the entity's own card from the tree,
/// and prettifies section titles (Story 2.1a). This page renders that tree
/// **faithfully** — it adds no filtering, prettifying, or parsing of its own, so
/// it can never diverge from the golden-fixture contract.
///
/// Snapshot semantics match [CategoryEntitiesPage]: the tree is seeded from the
/// passed [entry] and re-walked on return from the editor (AD-10 — the loader
/// owns the model, the UI never patches it) so a title edit is reflected without
/// backing out.
class EntityDetailPage extends StatefulWidget {
  final RepoStorage storage;
  final LoreEntry entry;

  /// The resolved `loreDir`. Model ids are **loreDir-relative**; [RepoStorage] /
  /// [EditorPage] are **repo-relative** — joined via [_repoPath] before use.
  final String loreDir;

  const EntityDetailPage({
    super.key,
    required this.storage,
    required this.entry,
    required this.loreDir,
  });

  @override
  State<EntityDetailPage> createState() => _EntityDetailPageState();
}

class _EntityDetailPageState extends State<EntityDetailPage> {
  /// Current entity snapshot; becomes null once a rescan finds it gone.
  LoreEntry? _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  /// loreDir-relative model id → repo-relative storage path. Empty [loreDir]
  /// (the picked folder is the lore folder) leaves the id unchanged.
  String _repoPath(String id) =>
      widget.loreDir.isEmpty ? id : '${widget.loreDir}/$id';

  Future<void> _open(String loreRelId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            EditorPage(storage: widget.storage, path: _repoPath(loreRelId)),
      ),
    );
    // A title edit (or a new/removed file) changes the tree — re-walk so the
    // outline reflects it without popping back to the entities list (AC3/FR3).
    if (mounted) await _rescan();
  }

  /// Re-walk and re-find this entity by its stable [LoreEntry.id] (AD-10 —
  /// rebuilt, never patched). Keeps the current view on an unexpected walk
  /// failure rather than stranding the screen (AD-8 at the call site).
  Future<void> _rescan() async {
    try {
      final model = await loadLore(widget.storage, widget.loreDir);
      if (!mounted) return;
      final matches = model.entries.where((e) => e.id == widget.entry.id);
      setState(() => _entry = matches.isEmpty ? null : matches.first);
    } catch (_) {
      // Keep the current view (AD-8).
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Scaffold(
      appBar: AppBar(title: Text(entry?.title ?? widget.entry.title)),
      body: entry == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This entity is no longer present.'),
              ),
            )
          : ListView(children: _rows(entry)),
    );
  }

  List<Widget> _rows(LoreEntry entry) {
    final rows = <Widget>[
      // The entity's own card — always first, visually distinct from sub-entries.
      ListTile(
        key: const Key('entity-card'),
        leading: const Icon(Icons.badge_outlined),
        title: Text(entry.title),
        subtitle: const Text('Card'),
        onTap: () => _open(entry.id),
      ),
    ];
    final tree = entry.tree;
    if (tree != null) {
      // A dual-card entity folder (both `index.md` and `<name>.md`) resolves one
      // file as the card and the other as the root node's overview. Surface it
      // as an Overview row so it is never stranded (it otherwise appears only in
      // the flat `children`, which this outline does not render).
      final overview = tree.overview;
      if (overview != null) {
        rows.add(_leaf(
          title: 'Overview',
          icon: Icons.article_outlined,
          loreRelId: overview.id,
          depth: 0,
        ));
      }
      // The entity-root node has an empty title — render its items directly
      // under the card and its children as the top-level sections.
      for (final item in tree.items) {
        rows.add(_itemRow(item, 0));
      }
      for (final section in tree.children) {
        _appendSection(rows, section, 0);
      }
    }
    return rows;
  }

  void _appendSection(List<Widget> rows, LoreNode node, int depth) {
    // `node.title` is always populated for non-root nodes (prettified folder
    // name or the section's overview heading) — rendered verbatim (AD-9).
    rows.add(_sectionHeader(node.title, depth));
    final overview = node.overview;
    if (overview != null) {
      rows.add(_leaf(
        title: 'Overview',
        icon: Icons.article_outlined,
        loreRelId: overview.id,
        depth: depth + 1,
      ));
    }
    for (final item in node.items) {
      rows.add(_itemRow(item, depth + 1));
    }
    for (final child in node.children) {
      _appendSection(rows, child, depth + 1);
    }
  }

  Widget _itemRow(LoreItem item, int depth) {
    // Open the primary language variant; RU/EN tabs are Story 2.8.
    final primary = item.langs['orig'] ?? item.langs['ru'] ?? item.langs['en'];
    return _leaf(
      title: item.title,
      icon: Icons.description_outlined,
      loreRelId: primary?.file,
      depth: depth,
    );
  }

  /// Left indent for a row at [depth], clamped so a very deeply nested tree
  /// (e.g. `quests/<arc>/<chapter>/…`) can never squeeze row content off-screen.
  static const int _kMaxIndentDepth = 6;
  double _indentFor(int depth) =>
      (depth < _kMaxIndentDepth ? depth : _kMaxIndentDepth) * 16.0;

  Widget _leaf({
    required String title,
    required IconData icon,
    required String? loreRelId,
    required int depth,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: _indentFor(depth)),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        onTap: loreRelId == null ? null : () => _open(loreRelId),
      ),
    );
  }

  Widget _sectionHeader(String title, int depth) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16 + _indentFor(depth), 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
