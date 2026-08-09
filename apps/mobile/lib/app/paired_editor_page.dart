import 'package:flutter/material.dart';

import '../ai/ai.dart';
import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart' show kDirtyIndicatorKey, confirmDiscardUnsaved;
import 'entity_navigation.dart';
import 'file_editor.dart';
import 'grammar_panel.dart';
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

  /// The AI client behind the bidirectional Translate action (Story 4.3
  /// created it for the RU→EN create-only case; Story 4.5 made it
  /// bidirectional), and forwarded to `navigateToEntity` for wikilink taps.
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

  /// Re-entrancy guard, same shape as [_linting] — a double-tap on Review
  /// must not fire two concurrent AI requests or stack two panels.
  bool _reviewing = false;

  /// Story 4.6 — reviews the **active tab's** live buffer for grammar/style
  /// (mirrors Lint/Save/Preview, which also target the active tab).
  /// `getEditor: () => _active` — not a captured snapshot — so
  /// `runGrammarReviewAndShowPanel` re-reads the active tab fresh if it
  /// changes while the request is in flight, instead of showing/jumping a
  /// tab the author isn't looking at anymore. Unlike Translate, not gated on
  /// a `ru`/`en` counterpart existing — available on every ready tab.
  ///
  /// Review fixes: guarded against `_translating` too — Translate and
  /// Review are not mutually exclusive by re-entrancy flag alone, so without
  /// this an author could fire both concurrently on the same tab and have
  /// Review's line numbers reference text Translate has since replaced.
  /// Also guarded against a blank buffer (mirrors Translate's AC8
  /// precedent), and wrapped in try/finally for the same reason
  /// `EditorPage._runReview` is — see its own doc comment.
  Future<void> _runReview() async {
    if (_reviewing || _translating) return;
    if ((_active?.text.trim().isEmpty) ?? true) return;
    setState(() => _reviewing = true);
    try {
      await runGrammarReviewAndShowPanel(
        context,
        storage: widget.storage,
        aiClient: widget.aiClient,
        getEditor: () => _active,
        onLoaded: () {
          if (mounted) setState(() => _reviewing = false);
        },
      );
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  /// Story 4.5 — the `ru`/`en` counterpart of [lang] within [_variants], or
  /// `null` for `orig` (direction is only defined between `ru` and `en`) or
  /// when no such counterpart tab exists on this item.
  _Variant? _counterpartOf(String lang) {
    final other = lang == 'ru' ? 'en' : (lang == 'en' ? 'ru' : null);
    if (other == null) return null;
    for (final v in _variants) {
      if (v.lang == other) return v;
    }
    return null;
  }

  /// Story 4.5/FR30 — the unifying bidirectional rule: Translate is
  /// available on the active tab whenever a `ru`/`en` counterpart tab exists
  /// at all — structural, not content-based (Review decision, 2026-08-08:
  /// restored to Story 4.3's original "visible even with nothing to
  /// translate yet, just disabled" affordance (AC8), rather than hiding the
  /// button outright; see the AppBar action's `onPressed` for the
  /// content-based enable/disable check via [_sourceText]). This single rule
  /// covers every case this app supports: Story 4.3's original RU→EN-create
  /// tab, Story 2.18's mirrored EN→RU-create tab (Story 4.3's old AC5
  /// restriction against it is superseded here), and a real already-paired
  /// item (Translate available on both tabs).
  bool get _canShowTranslate => _counterpartOf(_activeVariant.lang) != null;

  /// The best available *synchronous* text for [v]: the live buffer if that
  /// tab is built AND ready, falling back to the original content the
  /// loader read when this page opened. Used only for the cheap, synchronous
  /// enable/disable check ([_sourceText]) — the actual translate-time source
  /// text is re-read fresh from disk by [_translate] (Review fix — see its
  /// own comment) rather than trusting this possibly-stale fallback.
  ///
  /// (Verified empirically, not assumed — discovered during Story 4.5.) A
  /// `TabBarView` page is only built once the author actually scrolls/taps
  /// to it — `key.currentState` is `null` for a tab that has never been the
  /// active page, even though `_KeepAlive` preserves it forever once it has
  /// been. Gated on `isReady` (Review fix), not just non-null: a tab that
  /// has been built but is still loading, or failed to load, has a non-null
  /// state whose `.text` is `''` — treating that as "genuinely blank" would
  /// incorrectly disable Translate even though the fallback text is
  /// available. A synthetic (`createIfMissing`) tab has no entry in
  /// [PairedEditorPage.item]'s original `langs`, so it correctly falls
  /// through to `''` until the author actually types into it.
  String _textOf(_Variant? v) {
    if (v == null) return '';
    final state = v.key.currentState;
    if (state != null && state.isReady) return state.text;
    return widget.item.langs[v.lang]?.text ?? '';
  }

  /// The best-available (synchronous) text of the active tab's counterpart
  /// (see [_textOf]) — enables/disables the Translate button only; not the
  /// text actually sent (see [_translate]'s fresh read).
  String get _sourceText => _textOf(_counterpartOf(_activeVariant.lang));

  /// The freshest available text for [v]: the live buffer if it's built and
  /// ready, otherwise a fresh disk read (Review fix) rather than trusting
  /// [_textOf]'s possibly-stale `widget.item.langs` fallback — this project's
  /// own architecture rule is that files are the source of truth, recomputed
  /// on every request, never cached (project-context.md). A read failure (a
  /// missing file — the synthetic-tab case — or any other I/O error) falls
  /// back to that same snapshot, matching `_textOf`'s own AD-8 total-fallback
  /// shape; the catch-all (not a specific exception type) mirrors this
  /// codebase's established `AiPromptConfig.parse` reasoning.
  Future<String> _freshTextOf(_Variant v) async {
    final state = v.key.currentState;
    if (state != null && state.isReady) return state.text;
    try {
      return await widget.storage.read(v.repoPath);
    } catch (_) {
      return widget.item.langs[v.lang]?.text ?? '';
    }
  }

  /// Runs the Story 4.3/4.5 translate flow for the active tab: source = the
  /// counterpart tab's text, target = the active tab, direction follows from
  /// which language the active tab is. Assembles the context pack, shows the
  /// FR22 preview, and on confirm populates the target tab's buffer with the
  /// streamed result. A cancelled preview or any failure leaves the target
  /// tab untouched — `runTranslate` already reported the failure (AD-8), so
  /// there is nothing more to do here beyond clearing the spinner.
  Future<void> _translate() async {
    final target = _activeVariant;
    final source = _counterpartOf(target.lang);
    // Review fix: also guarded against `_reviewing` — see `_runReview`'s own
    // doc comment for why Translate and Review must not run concurrently.
    if (_translating || _reviewing || source == null) return;

    final sourceText = await _freshTextOf(source);
    // Defensive, matching the button's own visibility guard — a future call
    // site must not be able to fire this with nothing to translate.
    if (!mounted || sourceText.trim().isEmpty) return;

    final direction = target.lang == 'en'
        ? TranslationDirection.ruToEn
        : TranslationDirection.enToRu;
    setState(() => _translating = true);
    try {
      final result = await runTranslate(
        context,
        storage: widget.storage,
        loreDir: widget.loreDir,
        aiClient: widget.aiClient,
        sourceText: sourceText,
        direction: direction,
      );
      if (result == null || !mounted) return;
      final targetState = target.key.currentState;
      // Review fix (Story 4.3): a completed (and billed) translation must
      // never vanish silently — tell the author instead of just clearing the
      // spinner.
      if (targetState == null || !targetState.isReady) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Translation ready, but the ${target.label} tab was not open to receive it — try again.')),
        );
        return;
      }
      // Story 4.5/AC2: confirm before overwriting the target tab whenever it
      // has unsaved edits OR any non-blank content — saved, unsaved, or both
      // — not just a dirty draft (Story 4.3's original guard was
      // `enState.isDirty` alone, which missed overwriting a real,
      // already-saved translation). Review fix: `isDirty` is checked too,
      // not just non-blank text — an unsaved deletion (dirty, blank text)
      // must still be confirmed, since non-blank-text alone is not a
      // superset of dirty.
      if (targetState.isDirty || targetState.text.trim().isNotEmpty) {
        final overwrite = await confirmDiscardUnsaved(context, lossy: false);
        if (!overwrite || !mounted) return;
      }
      targetState.setText(result);
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return PopScope(
      // Review fix: nothing is "dirty" yet while a translation is still
      // streaming, so without `!_translating` the back gesture would silently
      // discard a completed, paid-for result the moment it lands against an
      // unmounted page (`_translate`'s own `if (!mounted) return;` guard).
      // `!_reviewing` is the same guard for a completed (and billed) review
      // (Review fix, Story 4.6 code review).
      canPop: !_anyDirty && !_translating && !_reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_translating) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A translation is still in progress.')),
          );
          return;
        }
        if (_reviewing) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A review is still in progress.')),
          );
          return;
        }
        _handlePop();
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
            // Story 4.6 — AI grammar/style review (FR23) for the active tab.
            // Not pair-aware and not direction-specific (unlike Translate) —
            // available whenever the active tab is ready.
            if (active?.isReady ?? false)
              IconButton(
                key: const Key('review-action'),
                tooltip: 'Review',
                onPressed: (_reviewing ||
                        _translating ||
                        active!.text.trim().isEmpty)
                    ? null
                    : _runReview,
                icon: _reviewing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.spellcheck),
              ),
            // Story 4.3/4.5 — AI translate (FR21/FR30), bidirectional: shown
            // on either tab that has a `ru`/`en` counterpart at all (AC8's
            // original "visible but disabled when there's nothing to
            // translate yet" affordance); disabled while running or while
            // the counterpart is actually blank.
            if (_canShowTranslate)
              IconButton(
                key: const Key('translate-action'),
                tooltip:
                    'Translate from ${_counterpartOf(_activeVariant.lang)?.label ?? ''}',
                onPressed: (_translating || _reviewing || _sourceText.trim().isEmpty)
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
