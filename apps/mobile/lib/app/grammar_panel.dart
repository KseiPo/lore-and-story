import 'package:flutter/material.dart';

import '../ai/ai.dart';
import '../storage/storage.dart';
import 'file_editor.dart';

/// The Story 4.6 grammar/style findings panel — a bottom sheet listing every
/// [GrammarFinding] a review produced, one row per finding. Tapping a row
/// dismisses the sheet and calls [onJumpToLine] with that finding's line
/// number. An empty [findings] list renders a clear "No issues found" state
/// instead of an empty sheet (AD-8 — a genuinely clean review is a real,
/// honest result, not a broken/blank panel). Structurally mirrors Story
/// 3.1's `showLintPanel` (`lint_panel.dart`), but over the AI-produced
/// `GrammarFinding` shape (issue/suggestion/severity), not `LintFinding`.
Future<void> showGrammarPanel(
  BuildContext context, {
  required List<GrammarFinding> findings,
  required void Function(int line) onJumpToLine,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: findings.isEmpty
          ? const Padding(
              key: Key('grammar-no-issues'),
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No issues found.', textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: findings.length,
              itemBuilder: (context, i) {
                final finding = findings[i];
                return ListTile(
                  key: Key('grammar-finding-$i'),
                  leading: Icon(_iconFor(finding.severity)),
                  title: Text(finding.issue),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Line ${finding.line} · ${_labelFor(finding.severity)}'),
                      Text(finding.suggestion),
                    ],
                  ),
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

IconData _iconFor(GrammarSeverity severity) {
  switch (severity) {
    case GrammarSeverity.minor:
      return Icons.info_outline;
    case GrammarSeverity.moderate:
      return Icons.warning_amber_outlined;
    case GrammarSeverity.major:
      return Icons.error_outline;
  }
}

String _labelFor(GrammarSeverity severity) {
  switch (severity) {
    case GrammarSeverity.minor:
      return 'Minor';
    case GrammarSeverity.moderate:
      return 'Moderate';
    case GrammarSeverity.major:
      return 'Major';
  }
}

/// Runs the Story 4.6 grammar review on [getEditor]'s current buffer and
/// shows the findings panel — shared by `EditorPage` and `PairedEditorPage`
/// (AD-7), mirroring `runLintAndShowPanel`'s exact shape (`lint_panel.dart`).
///
/// [getEditor] is a getter, not a snapshot — re-read both before the request
/// and again right before opening the panel, so a `PairedEditorPage` tab
/// switch mid-request bails rather than showing/jumping a buffer that's no
/// longer the one on screen (same reasoning Story 3.1's own lint already
/// established).
///
/// [onLoaded], if given, fires once the result is known — findings, or a
/// request already handled by [runGrammarReview]'s own error/cancel path —
/// and **before** the panel opens, not once the panel is dismissed: a host's
/// spinner must clear at the "result known" point, since
/// `showModalBottomSheet`'s returned Future doesn't complete until dismissal
/// (identical reasoning to `runLintAndShowPanel`'s own doc comment).
Future<void> runGrammarReviewAndShowPanel(
  BuildContext context, {
  required RepoStorage storage,
  required AiClient aiClient,
  required FileEditorState? Function() getEditor,
  VoidCallback? onLoaded,
}) async {
  final editor = getEditor();
  if (editor == null) {
    onLoaded?.call();
    return;
  }
  final text = editor.text;

  final findings = await runGrammarReview(
    context,
    storage: storage,
    aiClient: aiClient,
    text: text,
  );
  onLoaded?.call();
  // A cancelled preview or any request/parse failure already reported
  // itself (or reported nothing to report, for a plain cancel) — nothing
  // further to show.
  if (findings == null) return;

  if (!context.mounted) return;
  // The active tab may have changed while the request was in flight — a
  // completed (and billed) review must never vanish silently (Review fix,
  // mirroring `runTranslate`'s own "never lie by omission" SnackBar for the
  // equivalent situation, Story 4.3).
  if (!identical(getEditor(), editor)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Review ready, but that tab is no longer open — try again.')),
    );
    return;
  }

  await showGrammarPanel(
    context,
    findings: findings,
    onJumpToLine: (line) => getEditor()?.jumpToLine(line),
  );
}
