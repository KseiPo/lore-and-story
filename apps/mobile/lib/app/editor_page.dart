import 'package:flutter/material.dart';

import '../storage/storage.dart';
import 'file_editor.dart';

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

  const EditorPage({super.key, required this.storage, required this.path});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final GlobalKey<FileEditorState> _editorKey = GlobalKey<FileEditorState>();

  FileEditorState? get _editor => _editorKey.currentState;

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

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    final dirty = editor?.isDirty ?? false;
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
          onStateChanged: () {
            if (mounted) setState(() {});
          },
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
