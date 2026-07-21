import 'package:flutter/material.dart';

import '../storage/storage.dart';
import 'browse_filter.dart';

/// In-repo file browser rooted at a given repo-relative start path (the
/// resolved `loreDir`) — picks a **file**, not a folder.
///
/// Distinct from [RootPickerPage]: that widget browses real device storage
/// (rooted at [kPrimaryExternalStorageRoot]) to pick a repo *root*; this one
/// browses **inside an already-open repo** via the injected [RepoStorage] to
/// pick a *file* within it. This is intentionally a flat directory
/// drill-down — not Epic 2's entity-tree/category browser (no card model, no
/// RU/EN pairing, no conflict badges). That richer browsing UI is a separate,
/// later concern; merging the two here would entangle root-picking with lore
/// browsing before the real entity model exists.
class LoreFilePickerPage extends StatefulWidget {
  final RepoStorage storage;

  /// Repo-relative path to start browsing at (the resolved `loreDir`).
  final String startPath;

  const LoreFilePickerPage({
    super.key,
    required this.storage,
    required this.startPath,
  });

  @override
  State<LoreFilePickerPage> createState() => _LoreFilePickerPageState();
}

class _LoreFilePickerPageState extends State<LoreFilePickerPage> {
  late String _relPath;
  List<RepoEntry> _entries = const [];
  bool _loading = true;

  /// Guards against overlapping loads from rapid navigation taps (same pattern
  /// as [RootPickerPage] / [HomePage]'s refresh epoch).
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _relPath = widget.startPath;
    _load();
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    final requested = _relPath;
    setState(() => _loading = true);
    // A missing/unreadable directory degrades to an empty list (never
    // throws) — the empty state below covers it.
    final entries = await widget.storage.listDir(requested);
    if (!mounted || epoch != _loadEpoch) return;
    // Syncthing's own folders (.stfolder, .stversions, ...) and other hidden
    // entries are never real lore content — hide them at every level.
    final sorted = entries.where((e) => !isHiddenBrowseEntry(e)).toList()
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    setState(() {
      _entries = sorted;
      _loading = false;
    });
  }

  void _open(RepoEntry entry) {
    if (entry.isDirectory) {
      _relPath = entry.path;
      _load();
    } else {
      // File selected — return its repo-relative path to the caller.
      Navigator.of(context).pop<String>(entry.path);
    }
  }

  bool get _atStart => _relPath == widget.startPath;

  void _up() {
    if (_atStart) return;
    final i = _relPath.lastIndexOf('/');
    _relPath = i == -1 ? widget.startPath : _relPath.substring(0, i);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // Drill-down mutates _relPath in place rather than pushing routes, so
    // system Back must go *up* a level while there is somewhere to go — not
    // exit the picker and lose the user's position.
    return PopScope(
      canPop: _atStart,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open a file'),
        actions: [
          if (!_atStart)
            IconButton(
              tooltip: 'Up',
              onPressed: _up,
              icon: const Icon(Icons.arrow_upward),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(_relPath, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? const Center(child: Text('No files found.'))
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, i) {
                          final e = _entries[i];
                          return ListTile(
                            leading: Icon(
                              e.isDirectory
                                  ? Icons.folder_outlined
                                  : Icons.description_outlined,
                            ),
                            title: Text(e.name),
                            trailing: e.isDirectory
                                ? const Icon(Icons.chevron_right)
                                : null,
                            onTap: () => _open(e),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
