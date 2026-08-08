import 'package:flutter/material.dart';

import '../ai/ai.dart';
import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart' show kDirtyIndicatorKey, confirmDiscardUnsaved;
import 'entity_navigation.dart';
import 'file_editor.dart';
import 'lint_panel.dart';

/// One language tab of a paired item.
class _Variant {
  final String lang; // 'ru' | 'en' | 'orig'
  final String label; // 'RU' | 'EN' | 'Original'
  final String repoPath; // repo-relative path of this variant's file

  /// True for the synthetic EN tab of a not-yet-translated pair (Story 2.9): the
  /// file doesn't exist yet, so it opens empty and the first save creates it.
  final bool createIfMissing;
  final GlobalKey<FileEditorState> key;

  _Variant(this.lang, this.label, this.repoPath, {this.createIfMissing = false})
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

  /// Story 4.3 — the AI client behind the Translate action on the synthetic
  /// RU→EN tab (Story 2.9's create-translation tab), and forwarded to
  /// `navigateToEntity` for wikilink taps.
  final AiClient aiClient;

  const PairedEditorPage({
    super.key,
    required this.storage,
    required this.item,
    required this.loreDir,
    required this.aiClient,
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
    // Story 2.9: a lone `.ru.md` with no `.en.md` gets an empty EN tab that
    // CREATES `<base>.en.md` on first save (a create, never a merge — AD-6). The
    // EN path sits beside the RU file, its `.ru.md` suffix swapped for `.en.md`.
    if (langs.containsKey('ru') && !langs.containsKey('en')) {
      final ruFile = langs['ru']!.file;
      final enFile = ruFile.replaceFirst(
        RegExp(r'\.ru\.md$', caseSensitive: false),
        '.en.md',
      );
      // Guard: only add the EN create tab when the `.ru.md` suffix actually
      // matched (so the EN path truly differs from the RU path). Without this, a
      // no-match `replaceFirst` would point the "EN" tab at the RU file and a
      // save would clobber it. Unreachable via the loader (it keys `ru` only for
      // `.ru.md`), but a one-line net against future drift.
      if (enFile != ruFile) {
        _variants.add(_Variant(
          'en',
          _labels['en']!,
          _repoPath(enFile),
          createIfMissing: true,
        ));
      }
    }
    // Mirror of the above: a lone `.en.md` with no `.ru.md` (Story 2.18's
    // undetermined-language flow can produce this, confirming EN on a bare
    // file) gets an empty RU create tab the same way.
    if (langs.containsKey('en') && !langs.containsKey('ru')) {
      final enFile = langs['en']!.file;
      final ruFile = enFile.replaceFirst(
        RegExp(r'\.en\.md$', caseSensitive: false),
        '.ru.md',
      );
      if (ruFile != enFile) {
        // Insert (not append) so the visual tab order stays RU-then-EN — the
        // convention every other pairing in this app follows — even though EN
        // is the real/confirmed variant here and RU is the synthetic one.
        _variants.insert(
          0,
          _Variant(
            'ru',
            _labels['ru']!,
            _repoPath(ruFile),
            createIfMissing: true,
          ),
        );
      }
    }
    // Default tab = the primary variant (orig ?? ru ?? en), matching the
    // loader's own primary selection. For the canonical ru+en pair there is no
    // `orig`, so this is the RU tab (FR12's "RU default"). For a lone
    // confirmed `en` (Story 2.18's undetermined-language flow), the real
    // content lives on the EN tab, so that's the default instead.
    final primaryKey = langs.containsKey('orig')
        ? 'orig'
        : langs.containsKey('ru')
            ? 'ru'
            : langs.containsKey('en')
                ? 'en'
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

  _Variant get _activeVariant => _variants[_tabController.index];

  /// Wikilink tap-navigation (Story 3.2, FR19) — pushes via the shared
  /// `navigateToEntity` (AD-7) and reloads the active tab's entity list on
  /// return (Review fix — see `EditorPage._navigateToEntity`'s doc comment).
  Future<void> _navigateToEntity(LoreEntry entry) async {
    await navigateToEntity(context,
        storage: widget.storage,
        entry: entry,
        loreDir: widget.loreDir,
        aiClient: widget.aiClient);
    if (mounted) _active?.reloadEntries();
  }

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

  /// Re-entrancy guard, same as `EditorPage._linting`.
  bool _linting = false;

  /// Story 3.1 — lints the **active tab's** live buffer (mirrors Save/Preview,
  /// which also target the active tab). `getEditor: () => _active` — not a
  /// captured snapshot — so `runLintAndShowPanel` re-reads the active tab
  /// fresh if it changes while the entity list is loading, instead of
  /// linting or jumping a tab the author isn't looking at anymore.
  Future<void> _runLint() async {
    if (_linting) return;
    setState(() => _linting = true);
    await runLintAndShowPanel(
      context,
      storage: widget.storage,
      loreDir: widget.loreDir,
      getEditor: () => _active,
      onLoaded: () {
        if (mounted) setState(() => _linting = false);
      },
    );
  }

  /// Re-entrancy guard, same shape as [_linting].
  bool _translating = false;

  /// Story 4.3 — RU→EN only: true exactly on the synthetic tab Story 2.9 adds
  /// for a lone `.ru.md` with no `.en.md` (FR21). Deliberately excludes the
  /// mirrored synthetic RU tab (`lang == 'ru'`, an EN-original file with no
  /// RU pair, Story 2.18's flow) — that direction is out of scope.
  bool get _canShowTranslate =>
      _activeVariant.lang == 'en' && _activeVariant.createIfMissing;

  /// The RU tab's live buffer — the "file" this action translates. Empty when
  /// the RU tab hasn't loaded yet or genuinely has no content (AC8 guards
  /// Translate on this).
  String get _ruText =>
      _variants.firstWhere((v) => v.lang == 'ru').key.currentState?.text ?? '';

  /// Runs the Story 4.3 translate flow for the active (RU→EN synthetic) tab:
  /// assembles the context pack, shows the FR22 preview, and on confirm
  /// populates the EN tab's buffer with the streamed result. A cancelled
  /// preview or any failure leaves the EN tab untouched — `runTranslate`
  /// already reported the failure (AD-8), so there is nothing more to do here
  /// beyond clearing the spinner.
  Future<void> _translate() async {
    // Defensive, matching the button's own visibility guard (AC5) — a future
    // call site must not be able to fire this off the wrong tab.
    if (_translating || !_canShowTranslate || _ruText.trim().isEmpty) return;
    setState(() => _translating = true);
    try {
      final result = await runTranslate(
        context,
        storage: widget.storage,
        loreDir: widget.loreDir,
        aiClient: widget.aiClient,
        ruText: _ruText,
      );
      if (result == null || !mounted) return;
      final enVariant = _variants.firstWhere((v) => v.lang == 'en');
      enVariant.key.currentState?.setText(result);
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

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
                      // The synthetic EN tab of a not-yet-translated pair — a
                      // "needs translation / will create" hint (Story 2.9).
                      if (v.createIfMissing) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.translate, size: 14),
                      ],
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
            // Story 3.1 — convention lint findings (FR18), active tab only.
            if (active?.isReady ?? false)
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
            // Story 4.3 — AI translate (FR21), the RU→EN synthetic tab only
            // (AC5): disabled while running or when there's nothing to
            // translate yet (AC8).
            if (_canShowTranslate)
              IconButton(
                key: const Key('translate-action'),
                tooltip: 'Translate with AI',
                onPressed: (_translating || _ruText.trim().isEmpty)
                    ? null
                    : _translate,
                icon: _translating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
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
                  loreDir: widget.loreDir,
                  createIfMissing: v.createIfMissing,
                  onStateChanged: () {
                    if (mounted) setState(() {});
                  },
                  onNavigateToEntity: _navigateToEntity,
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
