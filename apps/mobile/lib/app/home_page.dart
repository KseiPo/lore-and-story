import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'app.dart';
import 'category_entities_page.dart';
import 'conflicts_page.dart';
import 'editor_page.dart';
import 'lore_file_picker_page.dart';
import 'root_picker_page.dart';

/// The states of the v0.1 landing surface. A real browsing UI is Epic 2 — this
/// stays deliberately thin.
enum _Stage { loading, needsPermission, needsRoot, ready, error }

/// Orchestrates grant → pick-root → ready and remembers the choice across
/// launches. Re-checks and re-scans the repo on app resume: a permission granted
/// in the system Settings screen takes effect without a restart, and the lore
/// model is rebuilt from disk (the AD-10 rescan — no live watcher, no cache).
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
  String _loreDir = ProjectConfig.defaults.loreDir;

  /// Result of the last lore walk. Rebuilt on every refresh — never cached
  /// across scans (AD-10: no live watcher, the model comes from a full walk).
  LoreModel _lore = LoreModel.empty;
  String? _errorMessage;

  /// Monotonic guard: a resume-triggered refresh can start while a prior one is
  /// still awaiting I/O. Each run captures the current epoch and bails after any
  /// await if a newer run has superseded it, so stale results never win.
  int _refreshEpoch = 0;

  /// Single-flight coalescing: overlapping triggers (rapid Refresh taps, a
  /// resume during a walk) never start concurrent full walks. A trigger while a
  /// walk is in flight sets [_refreshQueued]; the running walk re-runs once when
  /// it finishes, so the final state is always fresh.
  bool _refreshing = false;
  bool _refreshQueued = false;

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

  /// Coalescing, error-bounded entry point for a rescan. All triggers
  /// (initState, resume, Refresh, return-from-editor) go through here.
  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshQueued = false;
        await _scanOnce();
      } while (_refreshQueued && mounted);
    } catch (e) {
      // AD-8 is enforced inside the loader, but resolveProjectConfig, the
      // permission channel, or an unexpected throwable must not strand the UI
      // on a spinner. Surface an error state with a Retry rather than dropping
      // the future.
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _errorMessage = e.toString();
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _scanOnce() async {
    final epoch = ++_refreshEpoch;
    final granted = await widget.permission.isGranted();
    if (!mounted || epoch != _refreshEpoch) return;
    if (!granted) {
      setState(() {
        _stage = _Stage.needsPermission;
        _lore = LoreModel.empty;
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

    // Resolve project config every open (re-read, never cached) — FR2.
    final config = await resolveProjectConfig(storage);
    // The picked folder IS the lore folder — the author syncs the lore folder
    // itself, so its contents are the categories/entities directly (no `lore/`
    // level), which is why loreDir defaults to the repo root. A lore-story.json
    // may still redirect loreDir to a subfolder for the whole-repo-sync case.
    //
    // We deliberately do NOT substitute the repo root when a configured
    // subfolder is missing: silently walking the whole repo would surface — and
    // let the author byte-exact-save — non-lore files (README, CHANGELOG, …). A
    // missing configured loreDir instead yields an empty model that names the
    // folder, a safe and recoverable signal that a rescan clears once the
    // subfolder syncs in.
    final loreDir = config.loreDir;
    // Full lore walk, rebuilt every refresh (AD-10). This is the rescan: on
    // resume or manual refresh it re-reads the repo from disk, so the browsed
    // categories/entities and surfaced conflict copies always reflect current
    // state (FR3). Browsing is driven by this model, not a raw directory listing.
    final lore = await loadLore(storage, loreDir);
    if (!mounted || epoch != _refreshEpoch) return;
    setState(() {
      _stage = _Stage.ready;
      _rootPath = root;
      _loreDir = loreDir;
      _lore = lore;
    });
  }

  void _showNeedsRoot() {
    setState(() {
      _stage = _Stage.needsRoot;
      _rootPath = null;
      _lore = LoreModel.empty;
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

  /// Opens a category's entities list (Story 2.2). On return — including from
  /// any editor opened through it — rescans so the counts/conflicts reflect
  /// edits (FR3: "reflects the current repo"; AD-10 rebuild).
  Future<void> _openCategory(LoreCategory category) async {
    final root = _rootPath;
    if (root == null) return;
    final storage = widget.storageFactory(root);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CategoryEntitiesPage(
          storage: storage,
          category: category,
          loreDir: _loreDir,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  /// Opens the badged, tappable list of conflict copies (Story 2.4). On return
  /// — including from any editor opened through it — rescans so the count/banner
  /// reflect current disk state (AD-10/FR3). The app only surfaces conflicts; it
  /// never resolves them (AD-5).
  Future<void> _openConflicts() async {
    final root = _rootPath;
    if (root == null) return;
    final storage = widget.storageFactory(root);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ConflictsPage(
          storage: storage,
          conflicts: _lore.conflicts,
          loreDir: _loreDir,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  /// Pushes the in-repo file picker rooted at [startPath]; on a selected file,
  /// pushes the bare editor, then rescans so an edit is reflected.
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
    if (mounted) await _refresh();
  }

  Future<void> _createInNewCategory() async {
    final root = _rootPath;
    if (root == null) return;

    final result = await _showNewCategoryDialog(context);
    if (result == null || !mounted) return;

    final catSlug = _slugify(result.categoryName);
    final entitySlug = _slugify(result.entityTitle);
    if (catSlug.isEmpty || entitySlug.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Names produce invalid filenames.')),
        );
      }
      return;
    }
    if (catSlug == 'media') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('"media" is reserved and cannot be used as a category name.')),
        );
      }
      return;
    }

    final storage = widget.storageFactory(root);
    final categoryFolder = _loreDir.isEmpty ? catSlug : '$_loreDir/$catSlug';
    final filePath = '$categoryFolder/$entitySlug.ru.md';

    try {
      final categoryExists = await storage.exists(categoryFolder);
      await storage.ensureDir(categoryFolder);
      if (categoryExists && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category already exists — adding entity to it.')),
        );
      }
      if (await storage.exists(filePath) ||
          await storage.exists('$categoryFolder/$entitySlug.md') ||
          await storage.exists('$categoryFolder/$entitySlug.en.md')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An entity with this name already exists.')),
        );
        return;
      }
      await storage.writeAtomic(filePath, '# ${result.entityTitle}\n');
    } on RepoStorageException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create the entity.')),
        );
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create the entity.')),
        );
      }
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EditorPage(storage: storage, path: filePath),
      ),
    );
    if (mounted) await _refresh();
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
      floatingActionButton: _stage == _Stage.ready
          ? FloatingActionButton(
              heroTag: null,
              onPressed: _createInNewCategory,
              tooltip: 'Create in new category',
              child: const Icon(Icons.add),
            )
          : null,
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
          lore: _lore,
          categories: categoriesOf(_lore.entries),
          onChangeFolder: _chooseRoot,
          onOpenFile: _openFile,
          onOpenCategory: _openCategory,
          onOpenConflicts: _openConflicts,
          onRefresh: _refresh,
        );

      case _Stage.error:
        return _MessageAction(
          icon: Icons.error_outline,
          title: 'Something went wrong',
          body: _errorMessage ?? 'The repo could not be read.',
          actionLabel: 'Retry',
          onAction: _refresh,
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
  final LoreModel lore;
  final List<LoreCategory> categories;
  final VoidCallback onChangeFolder;
  final VoidCallback onOpenFile;
  final void Function(LoreCategory category) onOpenCategory;
  final VoidCallback onOpenConflicts;
  final VoidCallback onRefresh;

  const _ReadyView({
    required this.rootPath,
    required this.loreDir,
    required this.lore,
    required this.categories,
    required this.onChangeFolder,
    required this.onOpenFile,
    required this.onOpenCategory,
    required this.onOpenConflicts,
    required this.onRefresh,
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
        Text(
          loreDir.isEmpty ? '(the selected folder)' : loreDir,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '${lore.entries.length} lore '
          '${lore.entries.length == 1 ? "entity" : "entities"}',
          style: theme.textTheme.bodyMedium,
        ),
        if (lore.conflicts.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Conflict copies are surfaced, never hidden (FR17). Tapping opens the
          // badged, tappable list (Story 2.4).
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onOpenConflicts,
            child: Container(
              key: const Key('conflict-banner'),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 18, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${lore.conflicts.length} sync-conflict '
                      '${lore.conflicts.length == 1 ? "copy" : "copies"} — tap to view',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: theme.colorScheme.onErrorContainer),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Categories', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Expanded(
          child: categories.isEmpty
              // A friendly empty state, never a hollow list (AD-8/NFR7): an
              // empty model is a state, not an error.
              ? Center(
                  child: Text(
                    loreDir.isEmpty
                        ? 'No lore entities found in this folder.'
                        : 'No lore entities found in "$loreDir".',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (context, i) {
                    final c = categories[i];
                    final n = c.entries.length;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(c.label),
                      subtitle: Text('$n ${n == 1 ? "entity" : "entities"}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => onOpenCategory(c),
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
        // Manual half of FR3 — the resume path already re-scans via the
        // lifecycle observer; this makes a rescan available on demand.
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
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

String _slugify(String title) {
  return title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9\-]'), '')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

class _NewCategoryResult {
  final String categoryName;
  final String entityTitle;
  const _NewCategoryResult(this.categoryName, this.entityTitle);
}

Future<_NewCategoryResult?> _showNewCategoryDialog(BuildContext context) {
  final catController = TextEditingController();
  final titleController = TextEditingController();
  return showDialog<_NewCategoryResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New category & entity'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('category-name-field'),
            controller: catController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Category name',
              hintText: 'e.g. locations',
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('new-cat-entity-title-field'),
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Entity title',
              hintText: 'e.g. Raven\'s Nest',
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('create-new-category-confirm'),
          onPressed: () => Navigator.of(ctx).pop(
            _NewCategoryResult(catController.text, titleController.text),
          ),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
