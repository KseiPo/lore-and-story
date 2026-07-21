import 'package:flutter/material.dart';

import '../storage/storage.dart';

/// Key for the dirty indicator, so tests bind to identity rather than to a
/// particular icon's visual styling.
const Key kDirtyIndicatorKey = Key('editor-dirty-indicator');

/// Bare raw-markdown editor for a single file (FR7): no rendering, no markup
/// hidden — the buffer is exactly what's on disk. Saving goes through
/// [RepoStorage.writeAtomic] (Story 1.2's byte-exact atomic writer).
///
/// This is the first place the AD-10 boundary exists in code: this page owns
/// the in-memory buffer of the one open file. There is no shared model to
/// update (Epic 2 introduces the loader) — a save writes the file and that's
/// the whole story here.
class EditorPage extends StatefulWidget {
  final RepoStorage storage;

  /// Repo-relative path of the file being edited.
  final String path;

  const EditorPage({super.key, required this.storage, required this.path});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

enum _LoadState { loading, ready, error }

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  _LoadState _loadState = _LoadState.loading;
  String? _errorMessage;
  String _original = '';
  bool _dirty = false;

  /// True when the loaded content contains U+FFFD replacement characters,
  /// meaning the file on disk is not well-formed UTF-8 and `read` decoded it
  /// lossily. Writing such a buffer back would replace the original bytes with
  /// the replacement chars — permanent corruption — so saving is disabled.
  ///
  /// This guard previously lived in the (now retired) round-trip spike; it
  /// belongs on the write path, which is here.
  bool _lossyLoad = false;

  /// Prevents two `writeAtomic` calls overlapping for the same buffer.
  bool _saving = false;

  /// Set when a save is requested while one is already in flight. The in-flight
  /// save re-runs once on completion, so a deferred save is never dropped (a
  /// plain "return if busy" guard would silently lose the newer text).
  bool _savePending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
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
    } catch (e) {
      // Catch-all, not just RepoStorageException: an Error subtype or an
      // untranslated platform exception must still land in the error state
      // rather than escaping as an unhandled async error (AD-8).
      if (!mounted) return;
      setState(() {
        _loadState = _LoadState.error;
        _errorMessage = e.toString();
      });
    }
  }

  void _onChanged() {
    final dirty = _controller.text != _original;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  bool get _canSave =>
      _dirty && !_lossyLoad && _loadState == _LoadState.ready;

  /// Saves the current buffer if there is something safe to save. Explicit save
  /// (the AppBar action), save-on-background, and save-on-pop all funnel
  /// through here.
  Future<void> _save() async {
    if (!_canSave) return;
    if (_saving) {
      // Don't drop it — re-run after the in-flight write finishes.
      _savePending = true;
      return;
    }
    _saving = true;
    try {
      do {
        _savePending = false;
        final text = _controller.text;
        await widget.storage.writeAtomic(widget.path, text);
        if (!mounted) return;
        _original = text;
        // Recompute rather than assuming clean: the user may have typed while
        // the write was in flight, and those keystrokes are still unsaved.
        final dirty = _controller.text != _original;
        if (dirty != _dirty) setState(() => _dirty = dirty);
        if (dirty) _savePending = true;
      } while (_savePending && _canSave);
    } catch (e) {
      // Catch-all for the same reason as _load.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      _saving = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save-on-background (FR11): best-effort — there is no guarantee Android
    // lets this Future finish before reclaiming the process. This is
    // acceptable because writeAtomic is atomic: a killed write leaves the old
    // content intact, never a partial file. No retry queue / WorkManager here
    // — out of scope for a v0.1 bare editor.
    if (state == AppLifecycleState.paused) {
      _save();
    }
  }

  /// Back with unsaved edits must not silently discard them. Saves first when
  /// the buffer is safe to write; otherwise (e.g. a lossy load, which can never
  /// be saved) asks before discarding.
  Future<void> _handlePop() async {
    if (_canSave) {
      await _save();
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(
          _lossyLoad
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
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(widget.path, overflow: TextOverflow.ellipsis)),
              if (_dirty) ...[
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
            IconButton(
              tooltip: 'Save',
              onPressed: _canSave ? _save : null,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
            ),
          ],
        );
    }
  }
}
