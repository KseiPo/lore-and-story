/// Pure text-analysis + entity-matching for the `[[` autocomplete and
/// wikilink-navigation features (Story 3.2, FR19). Mirrors
/// `editor_toolbar.dart`'s pure-`TextEditingValue`-function style — these
/// operate on plain text/selections, testable with no widget tree.
///
/// Total (AD-8): every function here is total — no exceptions on empty text,
/// out-of-range offsets, or an empty entity list.
library;

import 'package:flutter/widgets.dart' show TextEditingValue, TextSelection;

import '../lore/lore.dart';

/// The open `[[query` span the caret is currently inside, if any.
class WikilinkQuery {
  /// Offset of the opening `[[`.
  final int start;

  /// Offset of the caret (the query's end).
  final int end;

  /// The text between the opening `[[` and the caret.
  final String query;

  const WikilinkQuery({required this.start, required this.end, required this.query});

  @override
  bool operator ==(Object other) =>
      other is WikilinkQuery &&
      other.start == start &&
      other.end == end &&
      other.query == query;

  @override
  int get hashCode => Object.hash(start, end, query);

  @override
  String toString() => 'WikilinkQuery($start, $end, "$query")';
}

/// Finds the unterminated `[[query` span the caret is inside, by scanning
/// backward from the caret. Stops (returns null) on a newline (left the
/// current line) or a `]` (either an already-closed wikilink, or the closing
/// half of something else) before reaching an opening `[[`. Also null when
/// the selection isn't a valid collapsed caret (a real text selection isn't
/// "inside" anything for this purpose).
///
/// (Review fix) A backward-only scan can't tell "genuinely open" apart from
/// "caret happens to sit inside an already-closed `[[Title]]`" — e.g.
/// `[[Se|lena]]` — since the closing `]]` is ahead of the caret, not behind
/// it. Once a candidate opening `[[` is found, a forward scan (to the next
/// `\n`/`[`, whichever comes first) checks for a `]` already reachable; if
/// one is found, the span is already closed and this is NOT an open query
/// (returning it would let a suggestion-accept corrupt the buffer, e.g.
/// `[[Selena]]lena]]`).
WikilinkQuery? findOpenWikilinkQuery(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final caret = selection.baseOffset;
  final text = value.text;
  if (caret < 0 || caret > text.length) return null;

  var i = caret;
  while (i > 0) {
    final ch = text[i - 1];
    if (ch == '\n' || ch == ']') return null;
    if (ch == '[' && i >= 2 && text[i - 2] == '[') {
      var j = caret;
      while (j < text.length) {
        final fch = text[j];
        if (fch == '\n' || fch == '[') break;
        if (fch == ']') return null;
        j++;
      }
      return WikilinkQuery(start: i - 2, end: caret, query: text.substring(i, caret));
    }
    i--;
  }
  return null;
}

/// Entities matching [query] (case-insensitive **starts-with** against each
/// entity's title or any alias — [LoreEntry.aliases] already includes the
/// entity's own title, so no separate title check is needed), one suggestion
/// per entity, capped at [limit], in entry order (already deterministic per
/// the loader). An empty [query] returns the first [limit] entities —
/// browsing, not just filtering.
///
/// (Review fix) Returns the matched [LoreEntry] itself, not just its title —
/// two entities can legitimately share a title (this codebase's own
/// `CategoryEntitiesPage` shows each entry's `id` as a disambiguating
/// subtitle for exactly this reason), so a caller needs `entry.id` to build a
/// suggestion row that doesn't collide, and `entry.title` to complete the
/// link. A title containing `[[`, `]]`, `->`, `<-`, or `|` is excluded — it
/// can never round-trip as a plain wikilink (the matcher would reclassify
/// the resulting bracket pair as a `sceneLink` or leave it malformed).
List<LoreEntry> matchWikilinkSuggestions(
  List<LoreEntry> entries,
  String query, {
  int limit = 8,
}) {
  final q = query.trim().toLowerCase();
  final results = <LoreEntry>[];
  for (final entry in entries) {
    if (results.length >= limit) break;
    if (!_isValidWikilinkTitle(entry.title)) continue;
    final matches =
        q.isEmpty || entry.aliases.any((n) => n.toLowerCase().startsWith(q));
    if (matches) results.add(entry);
  }
  return results;
}

/// Whether [title] can round-trip as a plain `[[title]]` wikilink — false for
/// a title containing bracket or scene-link-separator characters, which would
/// either break the `[[...]]` shape or get reclassified as a `sceneLink`.
bool _isValidWikilinkTitle(String title) =>
    !title.contains('[[') &&
    !title.contains(']]') &&
    !title.contains('->') &&
    !title.contains('<-') &&
    !title.contains('|');

/// Replaces [span] (the open `[[query` region) with `[[title]]`, caret
/// collapsed right after the inserted closing `]]`. [span]'s offsets are
/// clamped to the current text length defensively (AD-8) — a stale span from
/// a since-changed buffer must never throw a `RangeError`.
TextEditingValue completeWikilink(
  TextEditingValue value,
  WikilinkQuery span,
  String title,
) {
  final len = value.text.length;
  final start = span.start.clamp(0, len);
  final end = span.end.clamp(start, len);
  final replacement = '[[$title]]';
  final text = value.text.replaceRange(start, end, replacement);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: start + replacement.length),
  );
}

/// The entity [name] case-insensitively **exactly** matches (title or any
/// alias) — unlike [matchWikilinkSuggestions]'s starts-with, a tapped
/// wikilink names one specific entity, not a prefix. First match wins (entry
/// order, deterministic). Null when nothing matches — a dangling wikilink is
/// Story 3.1's linter's concern, not an error here (AD-8).
LoreEntry? findEntryByName(List<LoreEntry> entries, String name) {
  final target = name.trim().toLowerCase();
  if (target.isEmpty) return null;
  for (final entry in entries) {
    if (entry.aliases.any((n) => n.toLowerCase() == target)) return entry;
  }
  return null;
}
