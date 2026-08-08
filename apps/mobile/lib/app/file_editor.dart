import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../lore/lore.dart' as lore;
import '../storage/storage.dart';
import 'convention_highlighting_controller.dart';
import 'editor_toolbar.dart';
import 'markdown_preview.dart';
import 'wikilink_autocomplete.dart';

/// The per-file editing surface — everything about editing **one** file, minus
/// any `Scaffold`/`AppBar` chrome. Hosted by [EditorPage] (a single file) and by
/// the RU/EN paired editor (one per tab, Story 2.8), so the hardened
/// save/dirty/pop/lossy/conflict/highlighting/preview logic lives in **one**
/// place and is never forked (AD-7 spirit).
///
/// Owns the in-memory buffer of its file (AD-10). A save writes that file, and
/// only that file, via [RepoStorage.writeAtomic] (AD-4/AD-6 — a paired editor
/// never merges the two languages). Reads/writes are total (AD-8): a malformed
/// file still opens, a lossy-UTF-8 file opens read-best-effort with saving
/// disabled, and a read/save failure surfaces an error state, never a crash.
///
/// The host drives chrome (title, dirty indicator, preview toggle, Save action,
/// pop/background save) through the exposed getters + [save]/[togglePreview],
/// and rebuilds when [FileEditor.onStateChanged] fires.
class FileEditor extends StatefulWidget {
  final RepoStorage storage;

  /// Repo-relative path of the file being edited.
  final String path;

  /// The resolved `loreDir` (model ids are loreDir-relative; [RepoStorage] is
  /// repo-relative). Used by the Story 3.2 `[[` autocomplete and
  /// wikilink-tap-navigation features to load the entity list once per
  /// instance (Story 3.1's Lint action needed this too, but reloads fresh
  /// each time at the host-page level instead — this field is `FileEditor`'s
  /// own, separate need).
  final String loreDir;

  /// Fired whenever host-visible state changes (dirty / load-state / preview),
  /// so the host can rebuild its chrome.
  final VoidCallback? onStateChanged;

  /// When true, a **missing** file opens as an empty ready buffer (a create
  /// surface) instead of the error state; the first save creates it. Used for
  /// the empty EN tab of a not-yet-translated pair (Story 2.9). Default false —
  /// a missing file is a load error (the single-file editor's behavior).
  final bool createIfMissing;

  /// Called with the resolved entity when a `[[wikilink]]` is tapped in the
  /// preview (Story 3.2, FR19). `null` (the default) leaves wikilinks styled
  /// but not tappable. The host owns navigation (it knows how to reach
  /// [EntityDetailPage]/[EditorPage] and holds the `Navigator`); this widget
  /// only resolves the tapped title to a [lore.LoreEntry] via [_entries].
  final void Function(lore.LoreEntry entry)? onNavigateToEntity;

  const FileEditor({
    super.key,
    required this.storage,
    required this.path,
    required this.loreDir,
    this.onStateChanged,
    this.createIfMissing = false,
    this.onNavigateToEntity,
  });

  @override
  FileEditorState createState() => FileEditorState();
}

enum _LoadState { loading, ready, error }

/// Public so a host can hold a `GlobalKey<FileEditorState>` and query
/// dirty/save/lossy state (for its AppBar and its pop/background handling).
class FileEditorState extends State<FileEditor> with WidgetsBindingObserver {
  // A convention-highlighting controller (FR9): renders the raw buffer styled
  // via buildTextSpan while the text stays raw markdown.
  final ConventionHighlightingController _controller =
      ConventionHighlightingController();
  _LoadState _loadState = _LoadState.loading;
  String? _errorMessage;
  String _original = '';
  bool _dirty = false;

  /// True when showing the read-only rendered preview (FR10) instead of the raw
  /// editor. Pure UI state — the buffer is never touched by previewing.
  bool _previewing = true;

  /// True when the open file is a Syncthing conflict copy. The AppBar path is
  /// ellipsized from the end — exactly where the `.sync-conflict-…` marker sits
  /// — so on a long path nothing else would signal "this is a conflict copy,
  /// not the original." A banner re-asserts that context (FR17 / Story 2.4);
  /// resolution is still done with the syncer on the desktop (AD-5). Reuses the
  /// loader's exported detector — no second implementation (AD-7 spirit).
  late final bool _isConflictCopy = lore.isConflictCopy(_basename(widget.path));

  /// True when the loaded content contains U+FFFD replacement characters,
  /// meaning the file on disk is not well-formed UTF-8 and `read` decoded it
  /// lossily. Writing such a buffer back would replace the original bytes with
  /// the replacement chars — permanent corruption — so saving is disabled.
  bool _lossyLoad = false;

  /// Prevents two `writeAtomic` calls overlapping for the same buffer.
  bool _saving = false;

  /// Owns focus for the raw-editor `TextField` — `jumpToLine` (Story 3.1)
  /// requests focus here after moving the caret, since Flutter only scrolls
  /// a selection into view for a field that actually has focus (a bare
  /// `selection` change on an unfocused field is invisible).
  final FocusNode _focusNode = FocusNode();

  /// Set when a save is requested while one is already in flight. The in-flight
  /// save re-runs once on completion, so a deferred save is never dropped (a
  /// plain "return if busy" guard would silently lose the newer text).
  bool _savePending = false;

  // ---- Host-facing state ---------------------------------------------------

  /// Whether the buffer differs from what's on disk.
  bool get isDirty => _dirty;

  /// Whether there is something safe to save (dirty, not lossy, ready).
  bool get canSave => _canSave;

  /// Whether the file decoded lossily and so cannot be saved without corruption.
  bool get isLossy => _lossyLoad;

  /// Whether the file loaded (vs. loading / errored).
  bool get isReady => _loadState == _LoadState.ready;

  /// Whether the open file is a Syncthing conflict copy.
  bool get isConflictCopy => _isConflictCopy;

  /// Whether the read-only preview is showing (vs. the raw editor).
  bool get previewing => _previewing;

  /// The current buffer text — the live, possibly-unsaved content, not
  /// last-saved disk content. Used by the Story 3.1 linter, which must lint
  /// what the author is actually looking at.
  String get text => _controller.text;

  /// Toggle between the read-only preview and the raw editor (ready state only).
  void togglePreview() {
    if (_loadState != _LoadState.ready) return;
    setState(() => _previewing = !_previewing);
    _notify();
  }

  /// Switches out of preview (if showing) and moves the caret to the start of
  /// [line] (1-indexed) — used by the Story 3.1 lint panel to jump to a
  /// finding. The raw text must be visible to actually edit at that line, so
  /// this always lands in edit mode. A no-op before the buffer is ready.
  ///
  /// (Review fix) Setting `_controller.selection` alone moves the caret in
  /// the buffer's *state* but is invisible on screen for an off-screen line:
  /// Flutter only scrolls a selection into view for a field that has focus,
  /// and the `TextField` doesn't exist in the tree until this frame's build
  /// (which flips `_previewing` off) completes. Request focus in a
  /// post-frame callback, once the field is actually there to focus.
  void jumpToLine(int line) {
    if (_loadState != _LoadState.ready) return;
    final lines = _controller.text.split('\n');
    var offset = 0;
    for (var i = 0; i < line - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    offset = offset.clamp(0, _controller.text.length);
    setState(() {
      _previewing = false;
      _controller.selection = TextSelection.collapsed(offset: offset);
    });
    _notify();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  /// Replaces the buffer with [text] — used by the Story 4.3 translate action
  /// to populate a freshly generated draft. Marks the buffer dirty against
  /// [_original] exactly like a manual edit would (via the existing
  /// [_onChanged] listener — no special-casing needed) and switches out of
  /// preview so the draft is immediately visible and editable. This never
  /// writes to disk itself — an explicit save (FR21) is still required.
  ///
  /// A no-op before the buffer is ready, matching [jumpToLine]'s own guard —
  /// there is nothing to populate yet.
  void setText(String text) {
    if (_loadState != _LoadState.ready) return;
    setState(() {
      _previewing = false;
      _controller.text = text;
    });
    _notify();
  }

  /// Save the buffer to this file, if safe (see [canSave]). Returns whether it
  /// is now **safe to leave** the editor — true when the buffer is persisted
  /// (or there was nothing dirty to save), false when a write failed or a save
  /// is still in flight. A host's back/pop handler must NOT navigate away on a
  /// false result, or the unsaved edit is lost.
  Future<bool> save() => _save();

  void _notify() => widget.onStateChanged?.call();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onChanged);
    _load();
    _loadEntries();
  }

  /// The loaded entity list — Story 3.2's `[[` autocomplete and
  /// wikilink-tap-navigation both need it. Loaded once per instance, not on
  /// every keystroke/tap (unlike Story 3.1's Lint action, which deliberately
  /// reloads fresh each time — a different tradeoff for a different,
  /// occasional action). A failure (AD-8) just leaves this empty: no
  /// suggestions, no tap-resolution — never a crash.
  List<lore.LoreEntry> _entries = const [];

  Future<void> _loadEntries() async {
    try {
      final model = await lore.loadLore(widget.storage, widget.loreDir);
      if (!mounted) return;
      setState(() => _entries = model.entries);
      // (Review fix) The user may have already typed `[[query` while this
      // walk was in flight — without this, AC5's own scenario (suggestions
      // arrive once the walk lands) never actually surfaces them until the
      // next keystroke or caret move.
      _updateWikilinkQuery();
    } catch (_) {
      // _entries stays empty (AD-8) — see the field's own doc comment.
    }
  }

  /// Re-runs the entity-list load (Story 3.2 review fix) — a host page calls
  /// this after returning from a pushed wikilink-navigation destination,
  /// since an edit made there (e.g. a title rename) would otherwise leave
  /// this instance's `_entries`/suggestions/tap-resolution silently stale for
  /// the rest of this editor's lifetime.
  void reloadEntries() => _loadEntries();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Create surface (Story 2.9): a file that doesn't exist yet opens EMPTY,
      // not as an error — the first save creates it. `exists` distinguishes an
      // expected-absent file from a genuine read failure (which still errors),
      // so create-mode can't mask a real I/O problem.
      if (widget.createIfMissing && !await widget.storage.exists(widget.path)) {
        if (!mounted) return;
        _original = '';
        setState(() {
          _loadState = _LoadState.ready;
          _lossyLoad = false;
          // Nothing to preview in an empty new file — open in edit mode so the
          // author can type the translation straight away.
          _previewing = false;
        });
        _notify();
        return;
      }
      final text = await widget.storage.read(widget.path);
      if (!mounted) return;
      _original = text;
      // Set text without letting the listener mark this initial load as dirty.
      _controller.removeListener(_onChanged);
      _controller.text = text;
      _controller.addListener(_onChanged);
      setState(() {
        _loadState = _LoadState.ready;
        _lossyLoad = text.contains('\u{FFFD}');
      });
      _notify();
    } catch (e) {
      // Catch-all, not just RepoStorageException: an Error subtype or an
      // untranslated platform exception must still land in the error state
      // rather than escaping as an unhandled async error (AD-8).
      if (!mounted) return;
      setState(() {
        _loadState = _LoadState.error;
        _errorMessage = e.toString();
      });
      _notify();
    }
  }

  void _onChanged() {
    final dirty = _controller.text != _original;
    if (dirty != _dirty) {
      setState(() => _dirty = dirty);
      _notify();
    }
    _updateWikilinkQuery();
  }

  /// The `[[query` span the caret is currently inside (Story 3.2), if any,
  /// and the suggestion titles it currently matches. Recomputed on every
  /// text/selection change — including a pure caret move with no text
  /// change, so moving out of a span hides the row just as reliably as
  /// closing it with `]` does.
  WikilinkQuery? _activeQuery;
  List<lore.LoreEntry> _suggestions = const [];

  /// (Review fix) Guarded like `_onChanged`'s own `_dirty` check one function
  /// up — without this, every keystroke *and* every pure caret move
  /// `setState`s the whole `FileEditor` subtree even when the query/
  /// suggestions didn't actually change (the overwhelmingly common case).
  void _updateWikilinkQuery() {
    final query = findOpenWikilinkQuery(_controller.value);
    final suggestions = query == null
        ? const <lore.LoreEntry>[]
        : matchWikilinkSuggestions(_entries, query.query);
    if (query == _activeQuery && listEquals(suggestions, _suggestions)) return;
    setState(() {
      _activeQuery = query;
      _suggestions = suggestions;
    });
  }

  /// Replaces the active `[[query` span with `[[title]]` — the controller
  /// change this triggers runs back through [_onChanged]/[_updateWikilinkQuery]
  /// on its own, which naturally clears `_activeQuery`/`_suggestions` (the
  /// caret now sits right after `]]`, which `findOpenWikilinkQuery` correctly
  /// reads as "not inside an open query" — no separate reset needed here).
  void _completeWikilink(lore.LoreEntry entry) {
    final query = _activeQuery;
    if (query == null) return;
    _controller.value = completeWikilink(_controller.value, query, entry.title);
  }

  /// Resolves a tapped wikilink's title against the loaded entity list and
  /// forwards it to the host (Story 3.2, FR19). An unresolved title (the
  /// entity list hasn't loaded yet, or the link is dangling — Story 3.1's
  /// own concern, not re-litigated here) is silently ignored: AD-8, never a
  /// crash, and there's nowhere sensible to navigate to anyway.
  void _handleWikilinkTap(String title) {
    final entry = findEntryByName(_entries, title);
    if (entry != null) widget.onNavigateToEntity?.call(entry);
  }

  bool get _canSave => _dirty && !_lossyLoad && _loadState == _LoadState.ready;

  /// Saves the current buffer if there is something safe to save. Explicit save
  /// (the host's Save action), save-on-background, and save-on-pop all funnel
  /// through here.
  Future<bool> _save() async {
    if (!_canSave) return !_dirty; // nothing safe to save → ok to leave iff clean
    if (_saving) {
      // A write is already running; queue our newest text for its re-run. We
      // can't confirm it landed yet, so report "not safe to leave" — the caller
      // (a pop handler) must keep the screen rather than discard the edit.
      _savePending = true;
      return false;
    }
    _saving = true;
    try {
      do {
        _savePending = false;
        final text = _controller.text;
        await widget.storage.writeAtomic(widget.path, text);
        if (!mounted) return false;
        _original = text;
        // Recompute rather than assuming clean: the user may have typed while
        // the write was in flight, and those keystrokes are still unsaved.
        final dirty = _controller.text != _original;
        if (dirty != _dirty) {
          setState(() => _dirty = dirty);
        }
        _notify();
        if (dirty) _savePending = true;
      } while (_savePending && _canSave);
      return !_dirty; // persisted → safe to leave
    } catch (e) {
      // Catch-all for the same reason as _load. The write failed and the buffer
      // is still dirty — surface it and report "not safe to leave" so a pop
      // handler keeps the edit instead of silently discarding it.
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      return false;
    } finally {
      _saving = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save-on-background (FR11): best-effort — there is no guarantee Android
    // lets this Future finish before reclaiming the process. This is
    // acceptable because writeAtomic is atomic: a killed write leaves the old
    // content intact, never a partial file.
    if (state == AppLifecycleState.paused) {
      _save();
    }
  }

  static String _basename(String p) {
    final i = p.lastIndexOf('/');
    return i == -1 ? p : p.substring(i + 1);
  }

  @override
  Widget build(BuildContext context) {
    switch (_loadState) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _LoadState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not open this file.\n\n${_errorMessage ?? ''}'),
          ),
        );
      case _LoadState.ready:
        return Column(
          children: [
            if (_isConflictCopy)
              Container(
                key: const Key('editor-conflict-banner'),
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(12),
                child: Text(
                  'This is a Syncthing conflict copy — not the original file. '
                  'Resolve it with your syncer on the desktop.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            if (_lossyLoad)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(12),
                child: Text(
                  'This file is not valid UTF-8. It is shown best-effort and '
                  'cannot be saved — saving would corrupt the original bytes.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            if (_previewing)
              // Read-only rendered view of the CURRENT buffer (FR10). Display
              // only — the buffer is untouched, so Save/dirty still apply.
              Expanded(
                child: MarkdownPreview(
                  text: _controller.text,
                  storage: widget.storage,
                  filePath: widget.path,
                  onWikilinkTap: _handleWikilinkTap,
                ),
              )
            else ...[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
              ),
              // `[[` autocomplete suggestion row (Story 3.2, FR19) — docked
              // between the text and the toolbar, not a caret-positioned
              // floating overlay (see the story's Context for why).
              if (_activeQuery != null && _suggestions.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final entry in _suggestions)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: ActionChip(
                            // (Review fix) Keyed by id, not title — two
                            // entities can share a title (this codebase
                            // supports that, see CategoryEntitiesPage), and a
                            // title-only key would make two chips
                            // indistinguishable.
                            key: Key('wikilink-suggestion-${entry.id}'),
                            label: Text(entry.title),
                            onPressed: () => _completeWikilink(entry),
                          ),
                        ),
                    ],
                  ),
                ),
              // Helper toolbar above the keyboard (FR8) — editing only.
              EditorToolbar(controller: _controller),
            ],
          ],
        );
    }
  }
}
