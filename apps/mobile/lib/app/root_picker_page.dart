import 'package:flutter/material.dart';

import '../storage/storage.dart';
import 'app.dart';
import 'browse_filter.dart';

/// In-app directory browser rooted at primary shared storage. It navigates real
/// filesystem directories through the [RepoStorage] seam and returns the
/// selected **real path** (e.g. `/storage/emulated/0/story-repo`).
///
/// Deliberately NOT a SAF picker: a SAF `content://` document-tree URI would
/// break the whole path contract the loader depends on (addendum §A). Because
/// all-files access is granted, the app enumerates the filesystem itself.
class RootPickerPage extends StatefulWidget {
  final RepoStorageFactory storageFactory;

  const RootPickerPage({super.key, required this.storageFactory});

  @override
  State<RootPickerPage> createState() => _RootPickerPageState();
}

class _RootPickerPageState extends State<RootPickerPage> {
  late final RepoStorage _storage;

  /// Path relative to [kPrimaryExternalStorageRoot]; empty = the base itself.
  String _relPath = '';
  List<RepoEntry> _dirs = const [];
  bool _loading = true;

  /// Guards against overlapping loads from rapid navigation taps (see
  /// [_HomePageState] for the same pattern): a slow listing for a previous
  /// directory must not overwrite the current one.
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _storage = widget.storageFactory(kPrimaryExternalStorageRoot);
    _load();
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    final requested = _relPath;
    setState(() => _loading = true);
    final entries = await _storage.listDir(requested);
    if (!mounted || epoch != _loadEpoch) return;
    final dirs = entries
        .where((e) => e.isDirectory && !isHiddenBrowseEntry(e))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _dirs = dirs;
      _loading = false;
    });
  }

  void _enter(RepoEntry dir) {
    _relPath = dir.path;
    _load();
  }

  void _up() {
    final i = _relPath.lastIndexOf('/');
    _relPath = i == -1 ? '' : _relPath.substring(0, i);
    _load();
  }

  String get _absolutePath => _relPath.isEmpty
      ? kPrimaryExternalStorageRoot
      : '$kPrimaryExternalStorageRoot/$_relPath';

  Future<void> _select() async {
    // Selecting the storage root itself makes all of shared storage the repo —
    // almost never intended. Require an explicit confirm before allowing it.
    if (_relPath.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Use all of shared storage?'),
          content: const Text(
            'This selects the storage root itself as your repo, not a synced '
            'folder inside it. That is usually not what you want. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Use anyway'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    Navigator.of(context).pop<String>(_absolutePath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose repo folder'),
        actions: [
          if (_relPath.isNotEmpty)
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
            child: Text(_absolutePath, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _dirs.isEmpty
                    ? const Center(child: Text('No sub-folders here.'))
                    : ListView.builder(
                        itemCount: _dirs.length,
                        itemBuilder: (context, i) {
                          final d = _dirs[i];
                          return ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(d.name),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _enter(d),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _select,
            icon: const Icon(Icons.check),
            label: const Text('Use this folder'),
          ),
        ),
      ),
    );
  }
}
