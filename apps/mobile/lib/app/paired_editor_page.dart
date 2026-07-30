import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart' show kDirtyIndicatorKey, confirmDiscardUnsaved;
import 'file_editor.dart';

/// One language tab of a paired item.
class _Variant {
  final String lang; // 'ru' | 'en' | 'orig'
  final String label; // 'RU' | 'EN' | 'Original'
  final String repoPath; // repo-relative path of this variant's file
  final GlobalKey<FileEditorState> key;

  _Variant(this.lang, this.label, this.repoPath)
      : key = GlobalKey<FileEditorState>();
}

/// Edits a bilingual sub-entry as one screen with `[RU][EN]` tabs (FR12).
///
/// The pair is a **view**: each tab hosts an independent [FileEditor] over its
/// own `.ru.md` / `.en.md` file, so a save targets **only that file** and the
/// two languages are never merged (AD-6). The original/RU tab is selected by
/// default; switching tabs preserves each tab's unsaved buffer (both editors are
/// kept alive), and backing out saves-or-asks across **all** tabs (AD-10).
/// Backgrounding is handled per tab by each [FileEditor] itself.
class PairedEditorPage extends StatefulWidget {
  final RepoStorage storage;
  final LoreItem item;

  /// The resolved `loreDir` (model ids/files are loreDir-relative; the editor is
  /// repo-relative).
  final String loreDir;

  const PairedEditorPage({
    super.key,
    required this.storage,
    required this.item,
    required this.loreDir,
  });

  @override
  State<PairedEditorPage> createState() => _PairedEditorPageState();
}

class _PairedEditorPageState extends State<PairedEditorPage>
    with SingleTickerProviderStateMixin {
  static const _labels = {'ru': 'RU', 'en': 'EN', 'orig': 'Original'};
  // Tab order: original/RU first, EN last.
  static const _order = {'ru': 0, 'orig': 1, 'en': 2};

  late final List<_Variant> _variants;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final langs = widget.item.langs;
    final keys = langs.keys.toList()
      ..sort((a, b) => (_order[a] ?? 99).compareTo(_order[b] ?? 99));
    _variants = [
      for (final k in keys)
        _Variant(k, _labels[k] ?? k.toUpperCase(), _repoPath(langs[k]!.file)),
    ];
    // Default tab = the primary variant (orig ?? ru ?? en), matching the
    // loader's own primary selection. For the canonical ru+en pair there is no
    // `orig`, so this is the RU tab (FR12's "RU default").
    final primaryKey = langs.containsKey('orig')
        ? 'orig'
        : langs.containsKey('ru')
            ? 'ru'
            : _variants.first.lang;
    final initial = _variants.indexWhere((v) => v.lang == primaryKey);
    _tabController = TabController(
      length: _variants.length,
      initialIndex: initial < 0 ? 0 : initial,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // Rebuild so the AppBar (dirty/preview/save) reflects the active tab and the
    // IndexedStack shows it.
    if (mounted) setState(() {});
  }

  String _repoPath(String id) =>
      widget.loreDir.isEmpty ? id : '${widget.loreDir}/$id';

  FileEditorState? get _active => _variants[_tabController.index].key.currentState;

  /// Back with unsaved edits in any tab must not silently discard them: save the
  /// ones that can be saved; if any dirty tab can't be saved (lossy), ask once.
  Future<void> _handlePop() async {
    var blocked = false; // a dirty tab whose save failed / is in flight
    var anyLossyDirty = false;
    for (final v in _variants) {
      final ed = v.key.currentState;
      if (ed == null) continue;
      if (ed.canSave) {
        final saved = await ed.save();
        if (!mounted) return;
        if (!saved) blocked = true;
      } else if (ed.isDirty) {
        anyLossyDirty = true;
      }
    }
    // A tab whose save failed must not be navigated away from — keep the screen
    // (its snackbar explains why) rather than discard the edit.
    if (blocked) return;
    if (anyLossyDirty) {
      final discard = await confirmDiscardUnsaved(context, lossy: true);
      if (!discard) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  bool get _anyDirty => _variants.any((v) => v.key.currentState?.isDirty ?? false);

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return PopScope(
      canPop: !_anyDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(widget.item.title, overflow: TextOverflow.ellipsis),
              ),
              // Reflects ANY tab, not just the active one — a bilingual save can
              // leave the other language dirty while you view a clean tab.
              if (_anyDirty) ...[
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
            tabs: [
              for (final v in _variants)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(v.label),
                      // Per-tab hint so a dirty background tab is discoverable.
                      if (v.key.currentState?.isDirty ?? false) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.circle, size: 8),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            if (active?.isReady ?? false)
              IconButton(
                tooltip: active!.previewing ? 'Edit' : 'Preview',
                onPressed: () => active.togglePreview(),
                icon: Icon(
                  active.previewing
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            IconButton(
              tooltip: 'Save',
              onPressed: (active?.canSave ?? false) ? () => active!.save() : null,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        // Each tab is kept alive (never reloaded/disposed) so switching
        // preserves its unsaved buffer and each FileEditor's own lifecycle
        // observer still saves it on background (AD-10). Offscreen tabs are
        // offstage, so only the active editor is on screen.
        body: TabBarView(
          controller: _tabController,
          children: [
            for (final v in _variants)
              _KeepAlive(
                child: FileEditor(
                  key: v.key,
                  storage: widget.storage,
                  path: v.repoPath,
                  onStateChanged: () {
                    if (mounted) setState(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Keeps a tab's subtree alive while it is scrolled offscreen in the
/// [TabBarView], so its editor state (and lifecycle observer) survives a switch.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
