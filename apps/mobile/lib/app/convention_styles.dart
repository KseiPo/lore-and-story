import 'package:flutter/material.dart';

import '../lore/lore.dart';

/// Shared convention → [TextStyle] mapping and span-building, so the editor
/// highlighter (`ConventionHighlightingController`) and the read-only preview
/// (`MarkdownPreview`) render this project's conventions **identically** — one
/// recognizer (`convention_matcher`, AD-7) and one style map, no drift.
///
/// These are Flutter (`TextStyle`/`ColorScheme`) so they live in `app/`, not the
/// pure `lore/` matcher (AD-9).

/// Maps a [ConventionKind] to its display style, merged onto [base].
///
/// Suspect/invalid markup (the FR9a error kinds) all share one distinct error
/// style: the error color + a wavy underline (a spellcheck-style squiggle). The
/// markup is styled, never hidden.
TextStyle styleForConvention(ConventionKind kind, ColorScheme scheme, TextStyle base) {
  switch (kind) {
    case ConventionKind.heading:
      return base.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.primary,
        fontSize: (base.fontSize ?? 14) * 1.15,
      );
    case ConventionKind.bold:
      return base.copyWith(fontWeight: FontWeight.bold);
    case ConventionKind.italic:
      return base.copyWith(fontStyle: FontStyle.italic);
    case ConventionKind.listMarker:
      return base.copyWith(color: scheme.primary, fontWeight: FontWeight.bold);
    case ConventionKind.wikilink:
      return base.copyWith(color: scheme.tertiary, fontWeight: FontWeight.w600);
    case ConventionKind.dialogueSpeaker:
      return base.copyWith(color: scheme.secondary, fontWeight: FontWeight.w600);
    case ConventionKind.placeholder:
      return base.copyWith(color: scheme.tertiary, fontStyle: FontStyle.italic);
    case ConventionKind.emDash:
      return base.copyWith(color: scheme.primary);
    case ConventionKind.leakedTwee:
    case ConventionKind.leakedHtml:
    case ConventionKind.scenePassageLink:
    case ConventionKind.malformedMarkup:
      return base.copyWith(
        color: scheme.error,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.wavy,
        decorationColor: scheme.error,
      );
  }
}

/// Convention kinds a rendered preview styles over its text runs — the ones
/// markdown does NOT render structurally (markdown owns heading/bold/italic/
/// listMarker). These are all **inline** patterns, safe to match on any text
/// fragment the markdown AST hands us.
///
/// Two valid kinds are deliberately excluded here:
/// - `dialogueSpeaker` is line-anchored (`^Name…:`), so it's applied only to a
///   block's first inline run (see [previewLineStartConventionKinds]) — matching
///   it on a mid-line fragment (after inline emphasis) would falsely style plain
///   prose like `… intro:` as a speaker.
/// - `malformedMarkup` (an unterminated `[[`) is an authoring-time signal that
///   is unreliable per-fragment — a valid `[[Se*le*na]]` split by emphasis would
///   falsely flag as an error. It is not surfaced in the read-only preview.
const Set<ConventionKind> previewConventionKinds = {
  ConventionKind.wikilink,
  ConventionKind.placeholder,
  ConventionKind.emDash,
  ConventionKind.leakedTwee,
  ConventionKind.leakedHtml,
  ConventionKind.scenePassageLink,
};

/// [previewConventionKinds] plus the line-anchored `dialogueSpeaker` — applied
/// only to a block's **first** inline text run, where `^` genuinely means the
/// start of the line (so `Frank (angry): hi` still styles the speaker).
const Set<ConventionKind> previewLineStartConventionKinds = {
  ...previewConventionKinds,
  ConventionKind.dialogueSpeaker,
};

/// Splits [text] into plain + styled runs from pre-matched [tokens], applying a
/// style only for kinds in [apply]. Shared by the editor and the preview so the
/// **span-text-equals-input** invariant lives in one place.
///
/// Total (AD-8): out-of-range/overlapping tokens are skipped defensively, and
/// any failure falls back to a single plain span — a character is never dropped,
/// added, reordered, or hidden. Returns at least one span for non-empty [text].
List<InlineSpan> buildConventionSpans(
  String text,
  List<ConventionToken> tokens, {
  required TextStyle? base,
  required Set<ConventionKind> apply,
  required TextStyle Function(ConventionKind kind) styleFor,
}) {
  try {
    final spans = <InlineSpan>[];
    var i = 0;
    for (final t in tokens) {
      if (!apply.contains(t.kind)) continue;
      // Defensive: ignore any out-of-range or overlapping token.
      if (t.start < i || t.end > text.length || t.start >= t.end) continue;
      if (t.start > i) {
        spans.add(TextSpan(text: text.substring(i, t.start), style: base));
      }
      spans.add(TextSpan(text: text.substring(t.start, t.end), style: styleFor(t.kind)));
      i = t.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i), style: base));
    if (spans.isEmpty) return [TextSpan(text: text, style: base)];
    return spans;
  } catch (_) {
    return [TextSpan(text: text, style: base)];
  }
}
