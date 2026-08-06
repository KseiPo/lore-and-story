import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart';
import 'markdown_preview.dart';
import 'paired_editor_page.dart';
import 'undetermined_language_page.dart';

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

  /// A lone `.ru.md` with no `.en.md` — a "needs translation" candidate (FR13):
  /// it opens the paired editor with an empty EN tab that creates the file.
  static bool _needsTranslation(LoreItem item) =>
      item.langs.containsKey('ru') && !item.langs.containsKey('en');

  /// A bare `.md` sub-entry with no declared language yet — the loader tags
  /// it `langs == {'orig': ...}` and nothing else (Story 2.18/FR12/FR13). Its
  /// stem can never match its own parent folder's name (the loader diverts
  /// that case to become a `LoreOverview` instead — see `lore_loader.dart`'s
  /// `_buildNode`), so an entity-folder/section-overview card can never reach
  /// this branch — AC6 is satisfied by construction, no extra guard needed.
  static bool _isUndeterminedLanguage(LoreItem item) =>
      item.langs.length == 1 && item.langs.containsKey('orig');

  /// Opens a sub-entry: an undetermined-language item (Story 2.18) opens
  /// [UndeterminedLanguagePage]; a bilingual pair (2+ variants, Story 2.8) or
  /// a translation candidate (RU with no EN, Story 2.9) opens the tabbed
  /// [PairedEditorPage]; any other single-file item opens the plain
  /// [EditorPage]. All three re-walk on return (AD-10/FR3).
  Future<void> _openItem(LoreItem item) async {
    if (_isUndeterminedLanguage(item)) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => UndeterminedLanguagePage(
            storage: widget.storage,
            item: item,
            loreDir: widget.loreDir,
          ),
        ),
      );
      if (mounted) await _rescan();
      return;
    }
    if (item.langs.length >= 2 || _needsTranslation(item)) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PairedEditorPage(
            storage: widget.storage,
            item: item,
            loreDir: widget.loreDir,
          ),
        ),
      );
      if (mounted) await _rescan();
      return;
    }
    // The loader only ever keys variants ru/en/orig; the final fallback is
    // defensive so an unexpected key can't make a tappable row a silent no-op.
    final primary = item.langs['orig'] ??
        item.langs['ru'] ??
        item.langs['en'] ??
        (item.langs.isEmpty ? null : item.langs.values.first);
    if (primary == null) return;
    await _open(primary.file);
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

  Future<void> _createSubEntry() async {
    // Top-level sections only (Story 2.19's group suggestions never nest —
    // the group field has only ever held a single path segment).
    final existingGroups =
        _entry?.tree?.children.map((n) => n.name).toList() ?? const <String>[];
    final result = await _showCreateSubEntryDialog(context, existingGroups);
    if (result == null || !mounted) return;

    final groupInput = result.group.trim();
    // A group exactly matching an existing raw folder name (i.e. a
    // suggestion chip was tapped, or its exact text was typed) writes to
    // that folder as-is — never re-slugified. Suggestion labels are raw,
    // on-disk directory names (`LoreNode.name`), which are not guaranteed to
    // already be a `_slugify`-stable string ("Events" vs "events", or a
    // non-Latin name like "События" that `_slugify` would strip to ''); a
    // chip must not be able to write somewhere other than the folder it
    // names.
    final matchedGroup =
        existingGroups.firstWhere((g) => g == groupInput, orElse: () => '');
    final groupSlug =
        matchedGroup.isNotEmpty ? matchedGroup : _slugify(result.group);
    final entrySlug = _slugify(result.title);
    // An empty group is no longer an error (Story 2.19, AC1) — it means
    // "create at the entity root" instead of inside a subfolder. Typed text
    // that isn't empty but produces no usable slug (e.g. punctuation-only,
    // or a name that doesn't match any existing group) is still an error —
    // AC1 only covers a field genuinely left blank, not mistyped input
    // silently falling back to root. An empty title is always an error.
    if (entrySlug.isEmpty || (groupInput.isNotEmpty && groupSlug.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Names produce invalid filenames.')),
        );
      }
      return;
    }
    if (groupSlug == 'media') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('"media" is reserved and cannot be used as a group name.')),
        );
      }
      return;
    }

    final entryId = widget.entry.id;
    final lastSlash = entryId.lastIndexOf('/');
    final entityFolder = lastSlash < 0 ? '' : entryId.substring(0, lastSlash);
    final targetFolder =
        groupSlug.isEmpty ? entityFolder : '$entityFolder/$groupSlug';
    final filePath = '$targetFolder/$entrySlug.ru.md';

    try {
      // The entity folder already exists; only a real group needs creating.
      if (groupSlug.isNotEmpty) {
        await widget.storage.ensureDir(_repoPath(targetFolder));
      }

      if (await widget.storage.exists(_repoPath(filePath)) ||
          await widget.storage.exists(_repoPath('$targetFolder/$entrySlug.md')) ||
          await widget.storage.exists(_repoPath('$targetFolder/$entrySlug.en.md'))) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A sub-entry with this name already exists.')),
        );
        return;
      }

      await widget.storage.writeAtomic(
          _repoPath(filePath), '# ${result.title}\n');
    } on RepoStorageException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create the sub-entry.')),
        );
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create the sub-entry.')),
        );
      }
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            EditorPage(storage: widget.storage, path: _repoPath(filePath)),
      ),
    );
    if (mounted) await _rescan();
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Scaffold(
      appBar: AppBar(title: Text(entry?.title ?? widget.entry.title)),
      floatingActionButton: entry?.tree != null
          ? FloatingActionButton(
              heroTag: null,
              onPressed: _createSubEntry,
              tooltip: 'Add sub-entry',
              child: const Icon(Icons.add),
            )
          : null,
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
      // The entity's own card — always first, rendered read-only so the card
      // reads like a page rather than a link (Story 2.13). Tapping opens the
      // editor; editing itself remains the editor's job. AbsorbPointer keeps
      // the tap on the InkWell: without it, the AD-8 fallback's SelectableText
      // wins the gesture arena on a malformed card and silently swallows the
      // tap, making that card unreachable (Story 2.13 review finding).
      InkWell(
        key: const Key('entity-card'),
        onTap: () => _open(entry.id),
        child: AbsorbPointer(
          child: MarkdownPreview(
            text: entry.text,
            storage: widget.storage,
            filePath: _repoPath(entry.id),
          ),
        ),
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
    // A bilingual pair opens the RU/EN tabbed editor; a single file opens the
    // plain editor (Story 2.8). A null primary (no readable variant) is
    // untappable.
    final hasVariant = item.langs.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(left: _indentFor(depth)),
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(item.title),
        // "Needs translation" badge for a lone .ru.md (FR13).
        trailing: _needsTranslation(item)
            ? const Tooltip(
                message: 'Needs translation',
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.translate, size: 14),
                  label: Text('Needs translation'),
                ),
              )
            : null,
        onTap: hasVariant ? () => _openItem(item) : null,
      ),
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

String _slugify(String title) {
  return title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9\-]'), '')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class _SubEntryResult {
  final String group;
  final String title;
  const _SubEntryResult(this.group, this.title);
}

Future<_SubEntryResult?> _showCreateSubEntryDialog(
    BuildContext context, List<String> existingGroups) {
  final groupController = TextEditingController();
  final titleController = TextEditingController();
  return showDialog<_SubEntryResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New sub-entry'),
      // The chip row makes content height variable (and the group field is
      // autofocus'd, so the soft keyboard is up as soon as this opens) —
      // without this, an entity with several sections can overflow the
      // fixed-height AlertDialog content and clip the Title field/actions.
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (existingGroups.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final g in existingGroups)
                  ActionChip(
                    key: Key('sub-entry-group-chip-$g'),
                    label: Text(g),
                    onPressed: () => groupController.value = TextEditingValue(
                      text: g,
                      selection: TextSelection.collapsed(offset: g.length),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const Key('sub-entry-group-field'),
            controller: groupController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Group',
              hintText: 'e.g. events',
              helperText: 'Leave empty to create at the entity root',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('sub-entry-title-field'),
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: "e.g. Raven's Nest",
            ),
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => Navigator.of(ctx).pop(
              _SubEntryResult(groupController.text, titleController.text),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('create-sub-entry-confirm'),
          onPressed: () => Navigator.of(ctx).pop(
            _SubEntryResult(groupController.text, titleController.text),
          ),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
