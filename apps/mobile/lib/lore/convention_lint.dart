/// The convention linter (Story 3.1, FR18) — turns [matchConventions]'s
/// tokens into a navigable list of author-facing findings. One matcher, one
/// more consumer (AD-7): this file never reimplements detection, it only
/// wraps the matcher's own error tokens with a line number and a message,
/// plus the one check that genuinely needs data the matcher can't have
/// (the loaded entity list) — dangling wikilinks.
///
/// Pure Dart — no Flutter, no `dart:io` (AD-9). Total (AD-8): never throws.
library;

import 'convention_matcher.dart';

/// One navigable finding — a line-addressable error the author can jump to
/// and fix.
class LintFinding {
  /// 1-indexed line number the finding starts on (editors are line-oriented;
  /// this is exactly what a host jumps the caret to).
  final int line;

  final ConventionKind kind;

  /// Short, author-facing description of what's wrong.
  final String message;

  const LintFinding({required this.line, required this.kind, required this.message});

  @override
  bool operator ==(Object other) =>
      other is LintFinding &&
      other.line == line &&
      other.kind == kind &&
      other.message == message;

  @override
  int get hashCode => Object.hash(line, kind, message);

  @override
  String toString() => 'LintFinding(line $line, ${kind.name}: $message)';
}

/// Lints [text] for mechanically detectable convention errors (FR18), reusing
/// [matchConventions] — the exact same matcher the editor's highlighter uses.
///
/// [knownEntityNames] is the trimmed, lowercased set of every loaded entity's
/// title + aliases, used only for the dangling-wikilink check. Pass an empty
/// set (the default) to skip that check entirely — e.g. when the model
/// couldn't be loaded (AD-8: a load failure degrades to syntax-only findings,
/// never a crash or a false "everything is dangling").
///
/// Never throws (AD-8): any internal failure yields whatever findings were
/// already collected, mirroring [matchConventions]'s own total contract.
List<LintFinding> lintText(String text, {Set<String> knownEntityNames = const {}}) {
  final findings = <LintFinding>[];
  try {
    final tokens = matchConventions(text);
    final lineStarts = _lineStartOffsets(text);

    for (final token in tokens) {
      if (isError(token.kind)) {
        findings.add(LintFinding(
          line: _lineOf(token.start, lineStarts),
          kind: token.kind,
          message: _messageFor(token.kind),
        ));
      } else if (token.kind == ConventionKind.wikilink &&
          knownEntityNames.isNotEmpty) {
        final inner = text.substring(token.start + 2, token.end - 2).trim().toLowerCase();
        if (!knownEntityNames.contains(inner)) {
          findings.add(LintFinding(
            line: _lineOf(token.start, lineStarts),
            kind: token.kind,
            message: "[[${text.substring(token.start + 2, token.end - 2)}]] "
                "doesn't match any known entity.",
          ));
        }
      }
    }
  } catch (_) {
    // Total (AD-8): return whatever was collected so far.
  }
  return findings;
}

String _messageFor(ConventionKind kind) {
  switch (kind) {
    case ConventionKind.leakedTwee:
      return "Twee/SugarCube syntax (`<<...>>`) doesn't belong in lore/scene prose.";
    case ConventionKind.leakedHtml:
      return "HTML tag doesn't belong in lore/scene prose.";
    case ConventionKind.malformedMarkup:
      return 'Unterminated `[[` — missing the closing `]]`.';
    case ConventionKind.malformedDialogue:
      return 'Dialogue line is missing a space after the colon.';
    case ConventionKind.unpairedConditional:
      return 'Em-dash conditional marker («если» / «конец условия») has no matching counterpart.';
    // Not error kinds — never reached via the isError(token.kind) branch,
    // only listed so the switch stays exhaustive (AD-8: total).
    case ConventionKind.heading:
    case ConventionKind.bold:
    case ConventionKind.italic:
    case ConventionKind.listMarker:
    case ConventionKind.wikilink:
    case ConventionKind.dialogueSpeaker:
    case ConventionKind.placeholder:
    case ConventionKind.emDash:
    case ConventionKind.sceneLink:
      return '';
  }
}

/// The character offset each line starts at (index 0 = line 1's start),
/// computed once so per-token line lookup is O(log n) via binary search
/// instead of re-splitting the text per token.
List<int> _lineStartOffsets(String text) {
  const newline = 0x0A; // '\n'
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == newline) starts.add(i + 1);
  }
  return starts;
}

/// 1-indexed line number containing [offset], via binary search over
/// [lineStarts].
int _lineOf(int offset, List<int> lineStarts) {
  var lo = 0, hi = lineStarts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (lineStarts[mid] <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo + 1;
}
