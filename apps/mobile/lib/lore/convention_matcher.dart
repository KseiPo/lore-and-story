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

/// The kinds of span the matcher recognizes. The trailing group are **error
/// kinds** (suspect/invalid markup, FR9a) — see [errorKinds]. Consumers must
/// tolerate kinds beyond the valid set: the highlighter styles error kinds
/// distinctly and the Story 3.1 linter surfaces them as findings.
enum ConventionKind {
  // Valid conventions (Story 2.5).
  heading,
  bold,
  italic,
  listMarker,
  wikilink,
  dialogueSpeaker,
  placeholder,
  emDash,
  // Scene-navigation link (Story 2.15) — a `[[...]]` bracket pair containing a
  // separator (`->`, `<-`, `|`). Distinguished from `wikilink` (no separator)
  // purely by shape — see the unified-link decision in that story's spec.
  sceneLink,
  // Error kinds (Story 2.6, FR9a) — suspect/invalid markup to flag, not hide.
  leakedTwee,
  leakedHtml,
  malformedMarkup,
  // Error kinds (Story 3.1, FR18) — extends the above with two checks Story
  // 2.6 deliberately deferred: a dialogue-shaped line whose colon is missing
  // its required trailing space, and an em-dash conditional marker
  // (`— если …` / `— конец условия —`) with no matching counterpart.
  malformedDialogue,
  unpairedConditional,
}

/// The [ConventionKind]s that denote suspect/invalid markup (FR9a/FR18). One
/// source of truth so the highlighter's error styling and the Story 3.1
/// linter agree on what an "error" is — neither hardcodes its own set (AD-7).
const Set<ConventionKind> errorKinds = {
  ConventionKind.leakedTwee,
  ConventionKind.leakedHtml,
  ConventionKind.malformedMarkup,
  ConventionKind.malformedDialogue,
  ConventionKind.unpairedConditional,
};

/// Whether [kind] denotes suspect/invalid markup (a member of [errorKinds]).
bool isError(ConventionKind kind) => errorKinds.contains(kind);

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
// Malformed dialogue (Story 3.1, FR18): the exact same dialogue-speaker shape
// as [_dialogue], but the colon is immediately followed by a non-whitespace
// character instead of a space or end-of-line — the precise way a dialogue
// line breaks when the author forgets the space after the colon (e.g.
// `Frank:hello`). The two patterns are mutually exclusive on the same colon
// ((?=\s|$) vs (?=\S) can never both match), so a line is never double-flagged
// as both valid and malformed. Deliberately this narrow — broadening it to
// "any line that looks like it might be dialogue" would amplify the
// [_dialogue] heuristic's existing false-positive surface on ordinary prose
// with an early colon (see Story 2.5's deferred-work note on that). The
// prefix requires at least 2 characters (`{1,39}?`, not `{0,39}?`) so a
// one-symbol "prefix" like an emoticon (`>:( face`) can't match — a single
// punctuation character is never a plausible speaker name.
//
// (Review fix) The prefix and the character right after the colon both
// exclude digits and `/`: without this, `12:30`, `Ratio 3:1`, and
// `http://...` (including the exact markdown link the Story 2.15 External
// Link toolbar button inserts) all matched — a name-like prefix never
// contains a digit, and a scheme/path separator right after the colon is a
// URL, not a missing space. Verified against those exact cases in
// convention_matcher_test.dart.
final RegExp _malformedDialogue = RegExp(
    r'^[ \t]*[^\s:.!?\[\d][^\n:.!?\d]{1,39}?(?:\s*\([^)\n]*\))?[ \t]*:(?=[^\s/])');

// Inline patterns (scanned across the line via allMatches).
final RegExp _wikilink = RegExp(r'\[\[[^\[\]\n]+\]\]');
// A negative lookahead excludes `[label](url)` — standard markdown link
// syntax (Story 2.15's External link button), never a project-specific
// placeholder. Markdown owns rendering it; the matcher should stay quiet
// rather than mislabel it as a variable placeholder.
final RegExp _placeholder = RegExp(r'\[[^\[\]\n]+\](?!\()');
final RegExp _bold = RegExp(r'\*\*[^*\n]+\*\*');
final RegExp _italicUnderscore = RegExp(r'_[^_\n]+_');
final RegExp _italicStar = RegExp(r'\*[^*\n]+\*');
final RegExp _emDash = RegExp('—'); // — (U+2014)
// Scene-navigation link (Story 2.15): a `[[...]]` bracket pair containing a
// separator. `->`/`|` mean "forward to a named passage" (label before, target
// after); `<-` means "return, no target" (backlink type before, label after —
// see ARCHITECTURE.md §3.3). A bracket pair with NO separator is a `wikilink`
// instead — the two are disambiguated purely by shape, never by looking up
// whether the content resolves to a real passage/entity.
final RegExp _sceneLink = RegExp(r'\[\[[^\[\]\n]*(?:->|<-|\|)[^\[\]\n]*\]\]');

// Error patterns (FR9a). All linear (negated classes, no nested quantifiers) so
// they can never backtrack into a hang — "never crash" includes "never hang".
// A clean `<<…>>` SugarCube macro — twee never belongs in lore/scene markdown.
// The body excludes BOTH `<` and `>`: excluding `<` keeps each anchored attempt
// bounded by the next opener (no O(n²) rescans across a long `<<` run), and
// excluding `>` lets a whole clean macro highlight as one span. Macros with an
// interior `<`/`>` (e.g. `<<if $hp >= 100>>`, `<<link "a" -> "b">>`) don't match
// here — they're caught by the delimiter fallback below.
final RegExp _leakedTwee = RegExp(r'<<[^<>\n]*>>');
// The bare twee delimiters. MOBILE §6.1 names `<<`/`>>` themselves as the leak
// signal, so flag them even when the full macro body carries a `<`/`>` the clean
// pattern can't span. Same kind (leakedTwee); the clean whole-macro token, when
// present, wins by precedence+length so `<<x>>` stays a single span. Ungated and
// linear (two-literal alternation).
final RegExp _tweeDelimiter = RegExp(r'<<|>>');
// An HTML tag. The required letter after `<`/`</` keeps prose like `5 < 10`,
// `<3`, and `>:(` from matching (no false positives).
final RegExp _leakedHtml = RegExp(r'</?[A-Za-z][^>\n]*>');
// An unterminated `[[` — a wikilink opener with no `]]` reachable before the
// next bracket/end of line. A balanced `[[]]` is terminated, so not flagged
// (this is exactly what the toolbar's `[[` button inserts). Broader malformed
// detection (unpaired conditionals, dangling wikilinks) is the Story 3.1 linter.
final RegExp _unterminatedWikilink = RegExp(r'\[\[(?![^\[\]\n]*\]\])');

// Authoring-conditional em-dash markers (Story 3.1, FR18) — a prose block
// delimited by `— если <condition> —` (open) ... `— конец условия —` (close),
// with an optional `— иначе —` in between that is NOT itself checked for
// pairing — only если/конец условия balance matters (ARCHITECTURE.md's own
// example).
//
// (Review fix) The first draft's reasoning was backwards: requiring the
// closing dash on the open marker does NOT protect ordinary literary em-dash
// asides that use "если" (e.g. "она замолчала — если бы он знал..." —
// verified by probe to match `_condOpen` and, having no later "конец
// условия", to be flagged as unpaired) — that shape is exactly what the
// convention's own open-marker form looks like from the outside. The actual
// fix: this whole check now requires **at least one "конец условия" anywhere
// in the text** before it reports anything at all (see the early-return in
// [_matchConditionalMarkers]). A file that never uses this rare, specific
// convention produces zero conditional findings, full stop — the same
// precision-over-recall tradeoff `malformedMarkup` already made deliberately
// (Story 2.6: scoped to only the unterminated-`[[` case).
//
// The condition body also excludes `[`/`]` (in addition to em-dash/newline):
// without this, a wikilink written inside a condition clause (e.g. "— если
// [[Selena]] знает — ...") was swallowed whole into the marker's span and
// vanished from the token list entirely — invisible to both the highlighter
// and the Story 3.1 dangling-wikilink check (AC4). Excluding brackets means
// `_condOpen` simply can't match across a wikilink, so the marker isn't
// recognized there at all and the wikilink is tokenized normally instead —
// preferable to inventing a token-splitting/clipping scheme.
//
// The 300-char bound on the condition body keeps this linear (no unbounded
// backtracking) — same discipline as every other error pattern in this file.
// A condition longer than that, or one whose closing dash is on a different
// line, is a known, accepted residual gap (documented, not silently claimed
// solved): the open marker fails to match, so a later real "конец условия"
// reports as a stray closer instead of the true opener as unclosed. Fixing
// this fully would mean unbounded/cross-line matching, working against the
// ReDoS-safety bound every pattern in this file is built around.
//
// No `\b` after "если": Dart's `\b` is defined in terms of ASCII `\w`, so it
// silently fails to anchor right after Cyrillic text (Cyrillic letters aren't
// `\w` by default) — found by a failing test while adding this pattern, not
// assumed. The `—\s*` prefix is specific enough on its own.
final RegExp _condOpen =
    RegExp(r'—\s*если[^—\n\[\]]{1,300}—', caseSensitive: false);
final RegExp _condClose =
    RegExp(r'—\s*конец\s+условия\s*—', caseSensitive: false);

/// Cross-line pass (unlike every other check in this file, which is
/// per-line): scans the whole [text] for em-dash conditional markers and
/// returns a token for each **unpaired** one — a stray close with no
/// preceding open, or an open with no later close. Pairing is a simple
/// stack (LIFO): the source convention doesn't document nesting, but a stack
/// degrades to a reasonable default if markers are ever interleaved.
///
/// Returns nothing at all unless the text contains at least one closer —
/// see [_condOpen]'s doc comment for why.
List<ConventionToken> _matchConditionalMarkers(String text) {
  if (!_condClose.hasMatch(text)) return const [];

  final rawMarkers = <(int start, int end, bool isOpen)>[
    for (final m in _condOpen.allMatches(text)) (m.start, m.end, true),
    for (final m in _condClose.allMatches(text)) (m.start, m.end, false),
  ]..sort((a, b) => a.$1 - b.$1);

  // An open and a close match can share their delimiting em-dash (the
  // close's trailing `—` is the same character as the next open's leading
  // `—`), which would otherwise produce two overlapping tokens — violating
  // this file's documented non-overlapping guarantee. Drop any marker that
  // overlaps the one immediately before it; keeping the earlier one is an
  // arbitrary but reasonable call for what is, either way, a pathological
  // adjacency no real authoring would intend.
  final markers = <(int start, int end, bool isOpen)>[];
  for (final m in rawMarkers) {
    if (markers.isNotEmpty && m.$1 < markers.last.$2) continue;
    markers.add(m);
  }

  final openStack = <(int start, int end)>[];
  final unpaired = <ConventionToken>[];
  for (final marker in markers) {
    if (marker.$3) {
      openStack.add((marker.$1, marker.$2));
    } else if (openStack.isNotEmpty) {
      openStack.removeLast();
    } else {
      unpaired.add(ConventionToken(
          marker.$1, marker.$2, ConventionKind.unpairedConditional));
    }
  }
  for (final open in openStack) {
    unpaired.add(
        ConventionToken(open.$1, open.$2, ConventionKind.unpairedConditional));
  }
  return unpaired;
}

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
    // Cross-line pass — see [_matchConditionalMarkers]. A conditional
    // marker's span can legitimately contain inline markup the per-line pass
    // already tokenized (e.g. `**bold**` inside the condition text), so
    // marker tokens take precedence: drop any per-line token they overlap
    // before merging, preserving the documented "non-overlapping" guarantee
    // without a full document-wide _resolveOverlaps pass (conditional
    // markers are rare per file, so this stays cheap in practice).
    final conditionals = _matchConditionalMarkers(text);
    if (conditionals.isNotEmpty) {
      tokens.removeWhere((t) =>
          conditionals.any((c) => t.start < c.end && c.start < t.end));
      tokens.addAll(conditionals);
      tokens.sort((a, b) => a.start - b.start);
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
  final badDlg = _malformedDialogue.matchAsPrefix(line);
  if (badDlg != null) {
    cands.add(ConventionToken(0, badDlg.end, ConventionKind.malformedDialogue));
  }

  // Error candidates (FR9a) — added alongside the valid ones; precedence in
  // _resolveOverlaps lets an error win over the valid kind it shadows (a
  // `<<…>>`/`<tag>` interior is never partially styled).
  //
  // Each is gated on its closing delimiter being present first. This is a cheap
  // correctness-preserving guard (the pattern can't match without it) that also
  // keeps a delimiter-less line linear: `<<[^>]*>>` / `<tag…>` would otherwise
  // backtrack O(n²) scanning a long run with no closer.
  if (line.contains('>>')) {
    _collect(_leakedTwee, line, ConventionKind.leakedTwee, cands);
  }
  _collect(_tweeDelimiter, line, ConventionKind.leakedTwee, cands);
  if (line.contains('>')) {
    _collect(_leakedHtml, line, ConventionKind.leakedHtml, cands);
  }
  _collect(_unterminatedWikilink, line, ConventionKind.malformedMarkup, cands);

  // A separator-bearing bracket pair also matches _wikilink's broader content
  // class; sceneLink wins that overlap via _priority() (below), not via being
  // collected first — collection order here is just grouping for readability,
  // it has no effect on precedence. Same gate style as the error patterns
  // above (cheap precondition, keeps a delimiter-less line linear).
  if (line.contains(']]')) {
    _collect(_sceneLink, line, ConventionKind.sceneLink, cands);
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
    // Error kinds outrank the valid kinds they shadow, so suspect markup is
    // flagged rather than mistaken for a convention.
    case ConventionKind.leakedTwee:
      return 1; // a `<<…>>` run beats any inline valid kind inside it
    case ConventionKind.leakedHtml:
      return 2; // a `<tag>` beats inline valid kinds inside it
    // sceneLink is not an error, but must still outrank the generic wikilink
    // pattern it would otherwise also match — a separator-bearing bracket
    // pair is a more specific match than a plain wikilink.
    case ConventionKind.sceneLink:
      return 3; // `[[a->b]]` is a scene link, not a wikilink/placeholder
    case ConventionKind.malformedMarkup:
      return 4;
    case ConventionKind.dialogueSpeaker:
      return 5;
    // Mutually exclusive with dialogueSpeaker on the same colon (see
    // [_malformedDialogue]'s comment), so this precedence never actually
    // competes with it in practice — placed here for readability only.
    case ConventionKind.malformedDialogue:
      return 5;
    // Resolved separately by [_matchConditionalMarkers], never a per-line
    // candidate — priority is irrelevant but every enum value needs a case.
    case ConventionKind.unpairedConditional:
      return 11;
    case ConventionKind.wikilink:
      return 6; // beats placeholder so `[[x]]` is a wikilink, not `[x]`
    case ConventionKind.bold:
      return 7; // beats italic so `**x**` is bold, not `*x*`
    case ConventionKind.italic:
      return 8;
    case ConventionKind.placeholder:
      return 9;
    case ConventionKind.emDash:
      return 10;
  }
}

/// Keeps higher-precedence candidates and drops any that overlap one already
/// kept; returns the survivors sorted by position (non-overlapping).
///
/// Overlap is tested against a `covered` bitmap rather than by scanning every
/// kept token, so a line with very many candidates (e.g. a long run of `[[`)
/// resolves in ~O(total token length) instead of O(n²).
List<ConventionToken> _resolveOverlaps(List<ConventionToken> cands) {
  if (cands.isEmpty) return cands;
  cands.sort((a, b) {
    final pa = _priority(a.kind), pb = _priority(b.kind);
    if (pa != pb) return pa - pb;
    if (a.start != b.start) return a.start - b.start;
    return (b.end - b.start) - (a.end - a.start); // longer first
  });
  var maxEnd = 0;
  for (final t in cands) {
    if (t.end > maxEnd) maxEnd = t.end;
  }
  final covered = List<bool>.filled(maxEnd, false);
  final kept = <ConventionToken>[];
  for (final t in cands) {
    var clash = false;
    for (var i = t.start; i < t.end; i++) {
      if (covered[i]) {
        clash = true;
        break;
      }
    }
    if (clash) continue;
    for (var i = t.start; i < t.end; i++) {
      covered[i] = true;
    }
    kept.add(t);
  }
  kept.sort((a, b) => a.start - b.start);
  return kept;
}
