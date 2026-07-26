/// Pure convention matcher for the `lore/` slice — the AD-7 keystone.
///
/// Recognizes this project's markdown + prose conventions (ARCHITECTURE §3.3)
/// over a string and returns **typed, sorted, non-overlapping** tokens. One
/// matcher, many consumers: the editor highlighter (Story 2.5) and the
/// convention linter (Story 3.1) both consume these tokens, and Story 2.6
/// extends [ConventionKind] with error kinds — neither reimplements matching.
///
/// Pure Dart — no Flutter, no `dart:io` (AD-9). **Total** — never throws (AD-8);
/// unclassifiable input simply yields fewer tokens. **CRLF-safe** — offsets are
/// into the original string; a trailing `\r` never shifts or breaks a match.
library;

/// The kinds of span the matcher recognizes. Story 2.6 will add error kinds;
/// consumers must tolerate kinds beyond this set.
enum ConventionKind {
  heading,
  bold,
  italic,
  listMarker,
  wikilink,
  dialogueSpeaker,
  placeholder,
  emDash,
}

/// A recognized span, half-open `[start, end)` into the matched string.
class ConventionToken {
  final int start;
  final int end;
  final ConventionKind kind;

  const ConventionToken(this.start, this.end, this.kind);

  @override
  bool operator ==(Object other) =>
      other is ConventionToken &&
      other.start == start &&
      other.end == end &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(start, end, kind);

  @override
  String toString() => 'ConventionToken($start, $end, ${kind.name})';
}

// Line-start markers (anchored via matchAsPrefix).
final RegExp _heading = RegExp(r'^#{1,6}[ \t]');
final RegExp _listMarker = RegExp(r'^[ \t]*(?:[-*]|\d+\.)[ \t]');
// Dialogue speaker: a name-like prefix, optional `(emotion)`, then `:` before a
// space or end of line. Heuristic (tunable): a leading run of non-colon,
// non-sentence-punctuation chars covers Cyrillic names naturally (negated class
// — no Unicode property escapes needed). Emotion is optional (§3.3).
// The leading char also excludes `[` so a line beginning with a `[[wikilink]]`
// (a wikilinked speaker) is not swallowed as a dialogue prefix — the wikilink
// keeps its own highlight.
final RegExp _dialogue =
    RegExp(r'^[ \t]*[^\s:.!?\[][^\n:.!?]{0,39}?(?:\s*\([^)\n]*\))?[ \t]*:(?=\s|$)');

// Inline patterns (scanned across the line via allMatches).
final RegExp _wikilink = RegExp(r'\[\[[^\[\]\n]+\]\]');
final RegExp _placeholder = RegExp(r'\[[^\[\]\n]+\]');
final RegExp _bold = RegExp(r'\*\*[^*\n]+\*\*');
final RegExp _italicUnderscore = RegExp(r'_[^_\n]+_');
final RegExp _italicStar = RegExp(r'\*[^*\n]+\*');
final RegExp _emDash = RegExp('—'); // — (U+2014)

/// Parses [text] into a sorted, non-overlapping list of convention tokens.
///
/// Never throws: any internal failure returns the tokens collected so far.
List<ConventionToken> matchConventions(String text) {
  final tokens = <ConventionToken>[];
  try {
    var offset = 0;
    for (final line in text.split('\n')) {
      _matchLine(line, offset, tokens);
      offset += line.length + 1; // + the consumed '\n'
    }
  } catch (_) {
    // Total (AD-8): return whatever was collected.
  }
  return tokens;
}

void _matchLine(String line, int base, List<ConventionToken> out) {
  // A heading styles the whole line (headers "larger"); inline tokens inside a
  // heading are deliberately not separately highlighted in v0.1. Trim a trailing
  // CRLF `\r` so it isn't dragged into the heading's styled span.
  if (_heading.matchAsPrefix(line) != null) {
    final end = line.endsWith('\r') ? line.length - 1 : line.length;
    out.add(ConventionToken(base, base + end, ConventionKind.heading));
    return;
  }

  final cands = <ConventionToken>[];

  final lm = _listMarker.matchAsPrefix(line);
  if (lm != null) cands.add(ConventionToken(0, lm.end, ConventionKind.listMarker));

  final dlg = _dialogue.matchAsPrefix(line);
  if (dlg != null) {
    cands.add(ConventionToken(0, dlg.end, ConventionKind.dialogueSpeaker));
  }

  _collect(_wikilink, line, ConventionKind.wikilink, cands);
  _collect(_placeholder, line, ConventionKind.placeholder, cands);
  _collect(_bold, line, ConventionKind.bold, cands);
  _collect(_italicUnderscore, line, ConventionKind.italic, cands);
  _collect(_italicStar, line, ConventionKind.italic, cands);
  _collect(_emDash, line, ConventionKind.emDash, cands);

  for (final t in _resolveOverlaps(cands)) {
    out.add(ConventionToken(base + t.start, base + t.end, t.kind));
  }
}

void _collect(RegExp re, String line, ConventionKind kind, List<ConventionToken> out) {
  for (final m in re.allMatches(line)) {
    if (m.end > m.start) out.add(ConventionToken(m.start, m.end, kind));
  }
}

/// Lower number = higher precedence when two candidates overlap.
int _priority(ConventionKind k) {
  switch (k) {
    case ConventionKind.heading:
      return -1; // handled separately
    case ConventionKind.listMarker:
      return 0;
    case ConventionKind.dialogueSpeaker:
      return 1;
    case ConventionKind.wikilink:
      return 2; // beats placeholder so `[[x]]` is a wikilink, not `[x]`
    case ConventionKind.bold:
      return 3; // beats italic so `**x**` is bold, not `*x*`
    case ConventionKind.italic:
      return 4;
    case ConventionKind.placeholder:
      return 5;
    case ConventionKind.emDash:
      return 6;
  }
}

/// Keeps higher-precedence candidates and drops any that overlap one already
/// kept; returns the survivors sorted by position (non-overlapping).
List<ConventionToken> _resolveOverlaps(List<ConventionToken> cands) {
  cands.sort((a, b) {
    final pa = _priority(a.kind), pb = _priority(b.kind);
    if (pa != pb) return pa - pb;
    if (a.start != b.start) return a.start - b.start;
    return (b.end - b.start) - (a.end - a.start); // longer first
  });
  final kept = <ConventionToken>[];
  for (final t in cands) {
    final overlaps = kept.any((k) => t.start < k.end && k.start < t.end);
    if (!overlaps) kept.add(t);
  }
  kept.sort((a, b) => a.start - b.start);
  return kept;
}
