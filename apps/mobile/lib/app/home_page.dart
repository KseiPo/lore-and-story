import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'app.dart';
import 'browse_filter.dart';
import 'editor_page.dart';
import 'lore_file_picker_page.dart';
import 'root_picker_page.dart';

/// The three states of the v0.1 landing surface. A real browsing UI is Epic 2 —
/// this stays deliberately thin.
enum _Stage { loading, needsPermission, needsRoot, ready }

/// Orchestrates grant → pick-root → ready and remembers the choice across
/// launches. Re-checks on app resume so a permission granted in the system
/// Settings screen takes effect without an app restart (app-lifecycle only —
/// this is not the Epic 2 model rescan of AD-10).
class HomePage extends StatefulWidget {
  final RepoRootStore rootStore;
  final StoragePermission permission;
  final RepoStorageFactory storageFactory;

  const HomePage({
    super.key,
    required this.rootStore,
    required this.permission,
    required this.storageFactory,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  _Stage _stage = _Stage.loading;
  String? _rootPath;
  List<RepoEntry> _topLevel = const [];
  String _loreDir = ProjectConfig.defaults.loreDir;

  /// Monotonic guard: a resume-triggered refresh can start while a prior one is
  /// still awaiting I/O. Each run captures the current epoch and bails after any
  /// await if a newer run has superseded it, so stale results never win.
  int _refreshEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the system "All files access" screen resumes the app.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final epoch = ++_refreshEpoch;
    final granted = await widget.permission.isGranted();
    if (!mounted || epoch != _refreshEpoch) return;
    if (!granted) {
      setState(() {
        _stage = _Stage.needsPermission;
        _topLevel = const [];
      });
      return;
    }

    final root = await widget.rootStore.read();
    if (!mounted || epoch != _refreshEpoch) return;
    if (root == null) {
      _showNeedsRoot();
      return;
    }

    final storage = widget.storageFactory(root);

    // A remembered root can vanish (the syncer renames/moves it, or access is
    // revoked). Distinguish "gone" from "empty" so the user is sent back to
    // re-pick instead of seeing a hollow "no entries" repo.
    final rootExists = await storage.exists('');
    if (!mounted || epoch != _refreshEpoch) return;
    if (!rootExists) {
      _showNeedsRoot();
      return;
    }

    // Demonstrate the seam end-to-end: read the chosen root through RepoStorage.
    // Syncthing's own folders (.stfolder, .stversions, ...) are never real
    // content — hide them here too, same as the file picker.
    final entries = (await storage.listDir(''))
        .where((e) => !isHiddenBrowseEntry(e))
        .toList();
    // Resolve project config every open (re-read, never cached) — FR2.
    final config = await resolveProjectConfig(storage);
    if (!mounted || epoch != _refreshEpoch) return;
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _stage = _Stage.ready;
      _rootPath = root;
      _topLevel = entries;
      _loreDir = config.loreDir;
    });
  }

  void _showNeedsRoot() {
    setState(() {
      _stage = _Stage.needsRoot;
      _rootPath = null;
      _topLevel = const [];
    });
  }

  Future<void> _requestPermission() async {
    final granted = await widget.permission.request();
    if (!granted) {
      // Some OEM builds won't surface the "All files access" screen from
      // request(); fall back to opening the app's settings page directly.
      await widget.permission.openSettings();
    }
    await _refresh();
  }

  /// Opens the in-repo file picker and, on a selected file, pushes the bare
  /// editor (AC5 — closes Epic 1's full loop).
  ///
  /// Starts at the resolved `loreDir` when it exists as a subfolder of the
  /// chosen root. If the user pointed the repo root directly at their lore
  /// folder (a perfectly reasonable choice), `loreDir` won't exist as a
  /// subfolder of itself — fall back to browsing from the true repo root
  /// rather than showing an empty picker.
  Future<void> _openFile() async {
    final root = _rootPath;
    if (root == null) return;
    final storage = widget.storageFactory(root);
    final startPath = await storage.exists(_loreDir) ? _loreDir : '';
    if (!mounted) return;
    await _openFileFrom(storage, startPath);
  }

  /// Opens [entry]: descends into a directory via the in-repo picker (which
  /// itself supports further recursive descent and file selection), or opens
  /// a file directly in the editor.
  Future<void> _openEntry(RepoEntry entry) async {
    final root = _rootPath;
    if (root == null) return;
    final storage = widget.storageFactory(root);
    if (entry.isDirectory) {
      await _openFileFrom(storage, entry.path);
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EditorPage(storage: storage, path: entry.path),
        ),
      );
    }
  }

  /// Pushes the in-repo file picker rooted at [startPath]; on a selected file,
  /// pushes the bare editor.
  Future<void> _openFileFrom(RepoStorage storage, String startPath) async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LoreFilePickerPage(storage: storage, startPath: startPath),
      ),
    );
    if (path == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EditorPage(storage: storage, path: path),
      ),
    );
  }

  Future<void> _chooseRoot() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RootPickerPage(storageFactory: widget.storageFactory),
      ),
    );
    if (picked != null) {
      await widget.rootStore.write(picked);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lore & Story')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _buildStage()),
      ),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case _Stage.loading:
        return const CircularProgressIndicator();

      case _Stage.needsPermission:
        return _MessageAction(
          icon: Icons.folder_shared_outlined,
          title: 'Grant access to your repo',
          body:
              'Lore & Story needs "All files access" to read and write your '
              'synced story folder. You will be sent to a system settings '
              'screen to turn it on.',
          actionLabel: 'Grant access',
          onAction: _requestPermission,
        );

      case _Stage.needsRoot:
        return _MessageAction(
          icon: Icons.drive_folder_upload_outlined,
          title: 'Choose your repo folder',
          body:
              'Pick the root of your synced story repo (a Syncthing folder or a '
              'folder inside one). It will be remembered next time.',
          actionLabel: 'Choose repo folder',
          onAction: _chooseRoot,
        );

      case _Stage.ready:
        return _ReadyView(
          rootPath: _rootPath ?? '',
          loreDir: _loreDir,
          topLevel: _topLevel,
          onChangeFolder: _chooseRoot,
          onOpenFile: _openFile,
          onOpenEntry: _openEntry,
        );
    }
  }
}

class _MessageAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _MessageAction({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(body, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _ReadyView extends StatelessWidget {
  final String rootPath;
  final String loreDir;
  final List<RepoEntry> topLevel;
  final VoidCallback onChangeFolder;
  final VoidCallback onOpenFile;
  final void Function(RepoEntry entry) onOpenEntry;

  const _ReadyView({
    required this.rootPath,
    required this.loreDir,
    required this.topLevel,
    required this.onChangeFolder,
    required this.onOpenFile,
    required this.onOpenEntry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Repo root', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(rootPath, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Text('Lore folder', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(loreDir, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Text(
          topLevel.isEmpty
              ? 'No entries found at the root.'
              : 'Top-level entries (${topLevel.length}):',
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: topLevel.length,
            itemBuilder: (context, i) {
              final e = topLevel[i];
              return ListTile(
                dense: true,
                leading: Icon(
                  e.isDirectory ? Icons.folder_outlined : Icons.description_outlined,
                ),
                title: Text(e.name),
                trailing: e.isDirectory ? const Icon(Icons.chevron_right) : null,
                onTap: () => onOpenEntry(e),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: onOpenFile,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Open a file'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onChangeFolder,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Change folder'),
        ),
      ],
    );
  }
}
