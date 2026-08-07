import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'file_editor.dart';

/// The Story 3.1 lint findings panel — a bottom sheet listing every finding
/// [lintText] produced, one row per finding. Tapping a row dismisses the
/// sheet and calls [onJumpToLine] with that finding's line number. An empty
/// [findings] list renders a clear state instead of an empty sheet (AD-8 —
/// never a broken/blank panel); [danglingCheckAvailable] distinguishes a
/// genuinely clean file from one where the entity list couldn't be loaded,
/// so "No issues found" is never shown for a check that silently didn't run.
Future<void> showLintPanel(
  BuildContext context, {
  required List<LintFinding> findings,
  required bool danglingCheckAvailable,
  required void Function(int line) onJumpToLine,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: findings.isEmpty
          ? Padding(
              key: const Key('lint-no-issues'),
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  danglingCheckAvailable
                      ? 'No issues found.'
                      : 'No syntax issues found. The entity list could not '
                          'be loaded, so the dangling-wikilink check did '
                          'not run.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: findings.length,
              itemBuilder: (context, i) {
                final finding = findings[i];
                return ListTile(
                  key: Key('lint-finding-$i'),
                  leading: const Icon(Icons.error_outline),
                  title: Text(finding.message),
                  subtitle: Text('Line ${finding.line}'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onJumpToLine(finding.line);
                  },
                );
              },
            ),
    ),
  );
}

/// Lints [getEditor]'s current buffer and shows the findings panel — the one
/// place this flow is implemented, shared by `EditorPage`, `PairedEditorPage`,
/// and `UndeterminedLanguagePage` (AD-7: was forked 3 ways in an earlier
/// draft; a review caught it and it was consolidated here).
///
/// [getEditor] is a getter, not a snapshot: `PairedEditorPage` passes
/// `() => _active` so the *current* tab is re-read both before linting and
/// again right before jumping — if the author switches tabs while the entity
/// list is loading, this bails rather than showing findings for, or jumping,
/// a buffer that's no longer the one on screen.
///
/// The entity list is reloaded fresh via `loadLore` every time (AD-10 — no
/// caching); a load failure (AD-8) degrades to syntax-only findings rather
/// than blocking the panel, and the panel is told so it can say so instead
/// of silently reporting "No issues found."
///
/// [onLoaded], if given, fires once findings are computed and **before** the
/// panel opens — a host uses this to clear its own loading indicator right
/// then, rather than for the panel's entire open-until-dismissed lifetime.
/// `showModalBottomSheet`'s returned Future doesn't complete until the sheet
/// is dismissed, so awaiting this whole function for that purpose would keep
/// a host's spinner showing the entire time the panel is open, not just
/// during the load — a real bug an earlier draft had, caught by a hung test.
Future<void> runLintAndShowPanel(
  BuildContext context, {
  required RepoStorage storage,
  required String loreDir,
  required FileEditorState? Function() getEditor,
  VoidCallback? onLoaded,
}) async {
  final editor = getEditor();
  if (editor == null) {
    onLoaded?.call();
    return;
  }
  final text = editor.text;

  var knownEntityNames = const <String>{};
  var danglingCheckAvailable = false;
  try {
    final model = await loadLore(storage, loreDir);
    knownEntityNames = _collectKnownNames(model);
    danglingCheckAvailable = true;
  } catch (_) {
    // Syntax-only findings still show — see showLintPanel's own message.
  }

  if (!context.mounted) {
    onLoaded?.call();
    return;
  }
  // The active tab may have changed while the entity list was loading.
  if (!identical(getEditor(), editor)) {
    onLoaded?.call();
    return;
  }

  final findings = lintText(text, knownEntityNames: knownEntityNames);
  onLoaded?.call();
  if (!context.mounted) return;

  await showLintPanel(
    context,
    findings: findings,
    danglingCheckAvailable: danglingCheckAvailable,
    onJumpToLine: (line) => getEditor()?.jumpToLine(line),
  );
}

/// Every name a `[[wikilink]]` may legitimately target (ARCHITECTURE.md
/// §3.3: "lore entity references (cards/overviews)"), trimmed and
/// lowercased: each top-level entity's title + aliases, every section
/// overview's title, and every sub-entry's title. `LoreEntry.aliases`
/// already includes the entity's own title (`readTitleAliases` seeds it in),
/// so entity titles need no separate pass.
Set<String> _collectKnownNames(LoreModel model) {
  final names = <String>{};
  for (final entry in model.entries) {
    for (final alias in entry.aliases) {
      names.add(alias.trim().toLowerCase());
    }
    for (final child in entry.children) {
      names.add(child.title.trim().toLowerCase());
    }
    _collectSectionTitles(entry.tree, names);
  }
  return names;
}

void _collectSectionTitles(LoreNode? node, Set<String> out) {
  if (node == null) return;
  if (node.overview != null && node.title.isNotEmpty) {
    out.add(node.title.trim().toLowerCase());
  }
  for (final child in node.children) {
    _collectSectionTitles(child, out);
  }
}
