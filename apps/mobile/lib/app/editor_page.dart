import 'package:flutter/material.dart';

import '../ai/ai.dart';
import '../lore/lore.dart';
import '../storage/storage.dart';
import 'entity_navigation.dart';
import 'file_editor.dart';
import 'grammar_panel.dart';
import 'lint_panel.dart';

/// Key for the dirty indicator, so tests bind to identity rather than to a
/// particular icon's visual styling.
const Key kDirtyIndicatorKey = Key('editor-dirty-indicator');

/// Single-file editor screen (FR7): a thin `Scaffold` host over a [FileEditor].
/// The AppBar (path, dirty indicator, preview toggle, Save) and the
/// back/unsaved-edits guard delegate to the one `FileEditor` — all the editing
/// machinery lives there, shared with the RU/EN paired editor (Story 2.8) so it
/// is never forked.
class EditorPage extends StatefulWidget {
  final RepoStorage storage;

  /// Repo-relative path of the file being edited.
  final String path;

  /// The resolved `loreDir` (model ids are loreDir-relative; [RepoStorage] is
  /// repo-relative). Used only by the Story 3.1 Lint action to reload the
  /// entity list for dangling-wikilink checks — nothing else in this page
  /// needs it, unlike every other page that already carries this field.
  final String loreDir;

  /// Story 4.3 — not used by this page directly, only forwarded to
  /// `navigateToEntity` so a wikilink tap from here can still reach a
  /// Translate action deeper in the navigation chain.
  final AiClient aiClient;

  const EditorPage({
    super.key,
    required this.storage,
    required this.path,
    required this.loreDir,
    required this.aiClient,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final GlobalKey<FileEditorState> _editorKey = GlobalKey<FileEditorState>();

  FileEditorState? get _editor => _editorKey.currentState;

  /// Re-entrancy guard — a double-tap on Lint must not start two concurrent
  /// `loadLore` walks or stack two panels.
  bool _linting = false;

  /// Re-entrancy guard, same shape as [_linting] — a double-tap on Review
  /// must not fire two concurrent AI requests or stack two panels.
  bool _reviewing = false;

  /// Wikilink tap-navigation (Story 3.2, FR19) — pushes the tapped entity via
  /// the shared `navigateToEntity` (the one place the folder-vs-card branch
  /// rule lives, AD-7). (Review fix) Reloads this editor's own entity list on
  /// return, since the pushed screen may have renamed the entity we just
  /// navigated to (or another one) — without this, `_entries` here would
  /// silently go stale for the rest of this editor's lifetime.
  Future<void> _navigateToEntity(LoreEntry entry) async {
    await navigateToEntity(context,
        storage: widget.storage,
        entry: entry,
        loreDir: widget.loreDir,
        aiClient: widget.aiClient);
    if (mounted) _editor?.reloadEntries();
  }

  /// Back with unsaved edits must not silently discard them. Saves first when
  /// the buffer is safe to write; otherwise (e.g. a lossy load, which can never
  /// be saved) asks before discarding.
  Future<void> _handlePop() async {
    final editor = _editor;
    if (editor == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (editor.canSave) {
      final saved = await editor.save();
      if (!mounted) return;
      // A failed (or still in-flight) save must not navigate away — that would
      // discard the edit. Keep the screen; the snackbar explains the failure.
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

  /// Story 3.1 — lints the live buffer and shows the findings panel. See
  /// `runLintAndShowPanel`'s own doc comment for the shared implementation.
  Future<void> _runLint() async {
    if (_linting) return;
    setState(() => _linting = true);
    await runLintAndShowPanel(
      context,
      storage: widget.storage,
      loreDir: widget.loreDir,
      getEditor: () => _editor,
      // Clears the spinner once findings are ready, not once the panel is
      // dismissed — showModalBottomSheet's Future only completes on
      // dismissal, so guarding on that would show the spinner the whole
      // time the panel is open.
      onLoaded: () {
        if (mounted) setState(() => _linting = false);
      },
    );
  }

  /// Story 4.6 — runs an AI grammar/style review on the live buffer and
  /// shows the findings panel. See `runGrammarReviewAndShowPanel`'s own doc
  /// comment for the shared implementation. Guarded against a blank buffer
  /// (Review fix, mirroring Translate's AC8 precedent — an author should
  /// never be able to pay for a review of nothing), matching the Review
  /// button's own `onPressed` guard defensively.
  ///
  /// Review fix: wrapped in try/finally — without it, an exception between
  /// `setState(_reviewing = true)` and `onLoaded` would permanently strand
  /// the Review button, the same failure mode `_translate()`
  /// (`paired_editor_page.dart`) already guards against. `onLoaded` still
  /// does the normal, earlier clear (before the modal bottom sheet opens);
  /// `finally` is only the backstop for a failure before `onLoaded` fires.
  Future<void> _runReview() async {
    if (_reviewing) return;
    if ((_editor?.text.trim().isEmpty) ?? true) return;
    setState(() => _reviewing = true);
    try {
      await runGrammarReviewAndShowPanel(
        context,
        storage: widget.storage,
        aiClient: widget.aiClient,
        getEditor: () => _editor,
        onLoaded: () {
          if (mounted) setState(() => _reviewing = false);
        },
      );
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    final dirty = editor?.isDirty ?? false;
    return PopScope(
      // Review fix: mirrors `PairedEditorPage`'s own `!_translating` guard —
      // nothing is "dirty" while a review is in flight, so without
      // `!_reviewing` the back gesture would silently discard a completed
      // (and billed) result the moment it lands against an unmounted page.
      canPop: !dirty && !_reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
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
                child: Text(widget.path, overflow: TextOverflow.ellipsis),
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
          actions: [
            // Read-only preview toggle (FR10) — only in the ready state.
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
            // Story 4.6 — AI grammar/style review (FR23). Not pair-aware and
            // not direction-specific (unlike Translate) — available on every
            // ready buffer.
            if (editor?.isReady ?? false)
              IconButton(
                key: const Key('review-action'),
                tooltip: 'Review',
                onPressed: (_reviewing || (editor!.text.trim().isEmpty))
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
          path: widget.path,
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

/// Shared "Discard changes?" dialog for backing out of an editor with unsaved
/// edits that cannot be (or should not be silently) saved. Returns true when the
/// user chooses to discard. Reused by the single-file and RU/EN paired editors.
Future<bool> confirmDiscardUnsaved(
  BuildContext context, {
  required bool lossy,
}) async {
  final discard = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Discard changes?'),
      content: Text(
        lossy
            ? 'This file is not valid UTF-8, so it cannot be saved safely. '
                'Your changes will be lost.'
            : 'Your changes have not been saved.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return discard ?? false;
}
