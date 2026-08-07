import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart' show kDirtyIndicatorKey, confirmDiscardUnsaved;
import 'entity_navigation.dart';
import 'file_editor.dart';
import 'lint_panel.dart';
import 'paired_editor_page.dart';

/// Lets the author declare which language a bare `.md` sub-entry (no `.ru.md`/
/// `.en.md` suffix, `item.langs == {'orig': ...}`) is written in, then unlocks
/// the standard translation flow (FR12/FR13, Story 2.18).
///
/// Two phases, both rendered by this one widget instance so the transition
/// between them is in-place (no pop/re-navigate):
/// 1. **Undetermined** — real `[RU][EN]` tabs, same as a known-language pair,
///    but **neither is marked active** (the language genuinely isn't known
///    yet). The body is always the one real [FileEditor] over the bare file
///    — the author can read **and edit** it before declaring anything;
///    nothing is hidden behind the decision. Tapping a tab asks to confirm
///    that language; it never switches the view (there's only one file to
///    show either way).
/// 2. **Confirmed** — once a language is picked, any dirty buffer is saved
///    first (AD-10 — never move a file out from under unsaved edits), the
///    bare file is renamed (`RepoStorage.movePath`, same directory — Story
///    2.17's port addition, reused verbatim), and this widget delegates
///    entirely to [PairedEditorPage], which already implements Story 2.9's
///    create-translation flow for a lone `.ru.md`/`.en.md` with no sibling.
class UndeterminedLanguagePage extends StatefulWidget {
  final RepoStorage storage;
  final LoreItem item;

  /// The resolved `loreDir` (model ids/files are loreDir-relative; storage
  /// paths are repo-relative — see [_repoPath]).
  final String loreDir;

  const UndeterminedLanguagePage({
    super.key,
    required this.storage,
    required this.item,
    required this.loreDir,
  });

  @override
  State<UndeterminedLanguagePage> createState() =>
      _UndeterminedLanguagePageState();
}

class _UndeterminedLanguagePageState extends State<UndeterminedLanguagePage>
    with SingleTickerProviderStateMixin {
  /// The item this screen is showing. Starts as [UndeterminedLanguagePage.item]
  /// (orig-only); reassigned in place once a language is confirmed, so
  /// [build] can switch to delegating to [PairedEditorPage] without leaving
  /// this screen.
  late LoreItem _item;

  /// Drives the `[RU][EN]` `TabBar` — never a `TabBarView` (there is only one
  /// file to show regardless of which tab is tapped), so its `index` is
  /// otherwise unused; taps are read from `TabBar.onTap` directly.
  late final TabController _tabController;

  final GlobalKey<FileEditorState> _editorKey = GlobalKey<FileEditorState>();

  FileEditorState? get _editor => _editorKey.currentState;

  /// Guards the whole confirm-dialog-through-rename sequence against a second
  /// tab tap while the first is still in flight — without this, two quick
  /// taps can run [_confirmLanguage] twice concurrently, and the second call
  /// dereferences `_item.langs['orig']!` after the first has already replaced
  /// it.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _repoPath(String id) =>
      widget.loreDir.isEmpty ? id : '${widget.loreDir}/$id';

  /// Wikilink tap-navigation (Story 3.2, FR19) — pushes via the shared
  /// `navigateToEntity` (AD-7) and reloads this editor's entity list on
  /// return (Review fix — see `EditorPage._navigateToEntity`'s doc comment).
  Future<void> _navigateToEntity(LoreEntry entry) async {
    await navigateToEntity(context,
        storage: widget.storage, entry: entry, loreDir: widget.loreDir);
    if (mounted) _editor?.reloadEntries();
  }

  bool get _isUndetermined =>
      _item.langs.length == 1 && _item.langs.containsKey('orig');

  /// Tapping a tab only ever *asks* — reading and editing the file never
  /// required tapping a tab in the first place (the body is already showing
  /// it). `index` 0 = RU, 1 = EN, matching the `tabs:` order in [build].
  Future<void> _onTabTap(int index) async {
    if (_busy) return;
    _busy = true;
    try {
      final lang = index == 0 ? 'ru' : 'en';
      final humanLabel = index == 0 ? 'Russian' : 'English';
      final confirmed =
          await _showLanguageConfirmDialog(context, lang, humanLabel);
      if (confirmed != true || !mounted) return;
      await _confirmLanguage(lang);
    } finally {
      _busy = false;
    }
  }

  Future<void> _confirmLanguage(String lang) async {
    // Save-or-block first: the file has been genuinely editable this whole
    // time, so a dirty buffer is a real possibility here — never rename it
    // out from under unsaved edits (AD-10).
    final editor = _editor;
    if (editor != null && editor.isDirty) {
      if (!editor.canSave) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'This file cannot be saved (invalid UTF-8) — resolve that before assigning a language.'),
            ),
          );
        }
        return;
      }
      final saved = await editor.save();
      if (!mounted) return;
      if (!saved) {
        // A write failure already shows its own snackbar (FileEditor's
        // `_save`); this covers the other way `save()` can return `false`
        // silently — a save already in flight — so Confirm never appears to
        // do nothing.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Your edit could not be saved yet — try again in a moment.')),
        );
        return;
      }
    }

    final orig = _item.langs['orig']!;
    // The loader only ever hands us a `.md`-suffixed file for an 'orig'
    // variant — strip it and append the confirmed language's suffix.
    final newFile = '${orig.file.substring(0, orig.file.length - 3)}.$lang.md';
    final oldPath = _repoPath(orig.file);
    final newPath = _repoPath(newFile);

    try {
      if (await widget.storage.exists(newPath)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A file with this name already exists.')),
        );
        return;
      }
      await widget.storage.movePath(oldPath, newPath);
      if (!mounted) return;
    } on RepoStorageException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to set the language.')),
        );
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to set the language.')),
        );
      }
      return;
    }

    // No re-read: PairedEditorPage's own FileEditor re-reads the renamed
    // file from storage itself once it mounts (fresh, including whatever was
    // just saved above) — this reconstruction only needs to carry the right
    // *shape* (Story 2.9's "lone .ru.md, needs EN", or its EN mirror) so
    // `build()` below hands PairedEditorPage something it already knows how
    // to render, with zero changes to that widget.
    setState(() {
      _item = LoreItem(
        id: _item.id,
        title: _item.title,
        group: _item.group,
        passage: _item.passage,
        langs: {
          lang: LoreLang(
            file: newFile,
            relDir: orig.relDir,
            title: orig.title,
            text: orig.text,
          ),
        },
      );
    });
  }

  /// Back with unsaved edits must not silently discard them — identical
  /// shape to [EditorPage]'s own `_handlePop` (this phase *is* a single-file
  /// editor, just with a decorated AppBar).
  Future<void> _handlePop() async {
    final editor = _editor;
    if (editor == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (editor.canSave) {
      final saved = await editor.save();
      if (!mounted) return;
      if (!saved) return;
      Navigator.of(context).pop();
      return;
    }
    if (!editor.isDirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final discard = await confirmDiscardUnsaved(context, lossy: editor.isLossy);
    if (discard && mounted) Navigator.of(context).pop();
  }

  /// Re-entrancy guard, same as `EditorPage._linting`.
  bool _linting = false;

  /// Story 3.1 — lints the one always-visible `FileEditor`'s live buffer. See
  /// `runLintAndShowPanel`'s own doc comment for the shared implementation.
  Future<void> _runLint() async {
    if (_linting) return;
    setState(() => _linting = true);
    await runLintAndShowPanel(
      context,
      storage: widget.storage,
      loreDir: widget.loreDir,
      getEditor: () => _editor,
      onLoaded: () {
        if (mounted) setState(() => _linting = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isUndetermined) {
      // Delegate entirely — PairedEditorPage provides its own complete
      // Scaffold/AppBar/PopScope, so this is the whole build result, not
      // nested inside another Scaffold.
      return PairedEditorPage(
        storage: widget.storage,
        item: _item,
        loreDir: widget.loreDir,
      );
    }

    final editor = _editor;
    final dirty = editor?.isDirty ?? false;
    final orig = _item.langs['orig']!;
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(_item.title, overflow: TextOverflow.ellipsis),
              ),
              if (dirty) ...[
                const SizedBox(width: 6),
                Semantics(
                  key: kDirtyIndicatorKey,
                  label: 'Unsaved changes',
                  child: const Icon(Icons.circle, size: 10),
                ),
              ],
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            onTap: _onTabTap,
            // No tab is "active" — the language genuinely isn't known yet, so
            // the usual selection emphasis a real pair's TabBar shows here
            // would be misleading. Suppress it rather than picking a default.
            indicatorColor: Colors.transparent,
            labelColor: scheme.onSurface,
            unselectedLabelColor: scheme.onSurface,
            tabs: const [
              Tab(key: Key('lang-tab-ru'), text: 'RU'),
              Tab(key: Key('lang-tab-en'), text: 'EN'),
            ],
          ),
          actions: [
            if (editor?.isReady ?? false)
              IconButton(
                tooltip: editor!.previewing ? 'Edit' : 'Preview',
                onPressed: () => editor.togglePreview(),
                icon: Icon(
                  editor.previewing
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            // Story 3.1 — convention lint findings (FR18).
            if (editor?.isReady ?? false)
              IconButton(
                key: const Key('lint-action'),
                tooltip: 'Lint',
                onPressed: _linting ? null : _runLint,
                icon: _linting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined),
              ),
            IconButton(
              tooltip: 'Save',
              onPressed: (editor?.canSave ?? false) ? () => editor!.save() : null,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: FileEditor(
          key: _editorKey,
          storage: widget.storage,
          path: _repoPath(orig.file),
          loreDir: widget.loreDir,
          onStateChanged: () {
            if (mounted) setState(() {});
          },
          onNavigateToEntity: _navigateToEntity,
        ),
      ),
    );
  }
}

Future<bool?> _showLanguageConfirmDialog(
    BuildContext context, String lang, String humanLabel) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Is this file written in $humanLabel?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: Key('confirm-language-$lang'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}
