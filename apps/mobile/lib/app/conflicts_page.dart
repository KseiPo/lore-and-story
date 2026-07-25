import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'editor_page.dart';

/// The badged, tappable list of Syncthing conflict copies the walk surfaced
/// (Story 2.4, FR17) — reached by tapping the home conflict banner.
///
/// **Surface only (AD-5):** the app never merges, deletes, or resolves a
/// conflict; resolution is done with the external syncer on the desktop. Tapping
/// a row opens the copy in the [EditorPage] so the author can read/compare it —
/// inspection, not resolution.
///
/// Renders [LoreModel.conflicts] exactly as the loader produced them (Story
/// 2.1b) — it does no detection/filtering of its own.
class ConflictsPage extends StatelessWidget {
  final RepoStorage storage;
  final List<ConflictCopy> conflicts;

  /// Resolved `loreDir`. Conflict ids are loreDir-relative; [RepoStorage] /
  /// [EditorPage] are repo-relative — joined via [_repoPath]. Empty `loreDir`
  /// (the picked folder is the lore folder) passes the id through unchanged.
  final String loreDir;

  const ConflictsPage({
    super.key,
    required this.storage,
    required this.conflicts,
    required this.loreDir,
  });

  String _repoPath(String id) => loreDir.isEmpty ? id : '$loreDir/$id';

  Future<void> _open(BuildContext context, ConflictCopy c) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EditorPage(storage: storage, path: _repoPath(c.id)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync conflict copies')),
      body: conflicts.isEmpty
          ? const Center(child: Text('No sync conflict copies.'))
          : Column(
              children: [
                // Make clear the app only surfaces these; resolution is external.
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.errorContainer,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'These are Syncthing conflict copies. Resolve them with your '
                    'syncer on the desktop — the app only surfaces them.',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: conflicts.length,
                    itemBuilder: (context, i) {
                      final c = conflicts[i];
                      // `.` is the lore root — show a readable label.
                      final location = c.relDir == '.' ? 'root' : c.relDir;
                      return ListTile(
                        leading: Icon(Icons.warning_amber_outlined,
                            color: theme.colorScheme.error),
                        // Conflict names/paths are long and unbroken — ellipsize
                        // rather than overflow the row.
                        title: Text(c.name, overflow: TextOverflow.ellipsis),
                        subtitle: Text(location, overflow: TextOverflow.ellipsis),
                        trailing: const _ConflictBadge(),
                        onTap: () => _open(context, c),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// A small red "CONFLICT" badge (FR17's "conflict badge").
class _ConflictBadge extends StatelessWidget {
  const _ConflictBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'CONFLICT',
        style: TextStyle(
          color: theme.colorScheme.onError,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
