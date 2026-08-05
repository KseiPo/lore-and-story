import 'package:flutter/material.dart';

import '../lore/lore.dart';

/// The helper toolbar (FR8) and its pure text-operation functions.
///
/// The three mechanisms — insert-at-cursor, wrap-selection, prefix-line — are
/// pure functions over [TextEditingValue] (text + selection), so they unit-test
/// without a widget. The [EditorToolbar] widget applies them to the editor's
/// controller. Story 2.14 adds their inverses (`unwrap`/`unprefixLine`) and
/// active-state derivation, consuming [matchConventions] tokens (AD-7) — no
/// re-implemented recognition.

/// Current selection, normalized: falls back to a caret at end when the value
/// has no valid selection (a freshly-loaded controller), and **clamps** offsets
/// to the text length so a stale/out-of-range selection can never throw a
/// `RangeError` in the ops below (they are user-reachable and must be total).
TextSelection _sel(TextEditingValue v) {
  final len = v.text.length;
  final s = v.selection;
  if (!s.isValid) return TextSelection.collapsed(offset: len);
  return TextSelection(
    baseOffset: s.start.clamp(0, len),
    extentOffset: s.end.clamp(0, len),
  );
}

/// Replaces the selection with [s]; caret lands after the inserted text.
TextEditingValue insertAtCursor(TextEditingValue v, String s) {
  final sel = _sel(v);
  final text = v.text.replaceRange(sel.start, sel.end, s);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: sel.start + s.length),
  );
}

/// Wraps the selected range with [before]/[after]. An **empty** selection
/// inserts `before+after` and puts the caret **between** them (so bold/italic/
/// `[[` work with no selection); a non-empty selection stays selected.
TextEditingValue wrapSelection(
  TextEditingValue v,
  String before,
  String after,
) {
  final sel = _sel(v);
  final selected = v.text.substring(sel.start, sel.end);
  final text = v.text.replaceRange(
    sel.start,
    sel.end,
    '$before$selected$after',
  );
  if (sel.isCollapsed) {
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel.start + before.length),
    );
  }
  return TextEditingValue(
    text: text,
    selection: TextSelection(
      baseOffset: sel.start + before.length,
      extentOffset: sel.end + before.length,
    ),
  );
}

/// Prepends [prefix] to the start of every line the selection touches. See
/// [unprefixLine] for the inverse (Story 2.14).
TextEditingValue prefixLines(TextEditingValue v, String prefix) {
  final sel = _sel(v);
  final text = v.text;
  // Start of the line containing the selection start. At offset 0 the line
  // starts at 0 (do NOT search — a buffer beginning with `\n` would otherwise
  // match its own leading newline and skip the empty first line).
  final firstLineStart = sel.start == 0
      ? 0
      : text.lastIndexOf('\n', sel.start - 1) + 1;

  final head = text.substring(0, firstLineStart);
  final region = text.substring(firstLineStart);
  final selEndInRegion = sel.end - firstLineStart;

  final lines = region.split('\n');
  final out = StringBuffer();
  var consumed = 0; // running start offset (within region) of the current line
  var added = 0;
  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    // A line is touched when its start is strictly inside the selection span,
    // OR the selection is a collapsed caret sitting at that line's start. This
    // distinguishes "selection ends exactly at line B's start" (B not touched)
    // from "caret at line B's start" (B touched).
    if (consumed < selEndInRegion ||
        (consumed == selEndInRegion && sel.isCollapsed)) {
      out.write(prefix);
      added++;
    }
    out.write(line);
    if (li < lines.length - 1) out.write('\n');
    consumed += line.length + 1;
  }

  return TextEditingValue(
    text: head + out.toString(),
    selection: TextSelection(
      baseOffset: sel.start + prefix.length, // first prefixed line shifts start
      extentOffset: sel.end + prefix.length * added,
    ),
  );
}

/// Removes [beforeLen] chars at [start] and [afterLen] chars immediately
/// before [end] — the inverse of [wrapSelection] (Story 2.14). Total: [start]/
/// [end] clamp to the text length, and if that leaves no room for the full
/// delimiters the removal shrinks to what's actually there rather than
/// throwing. Selection offsets shift as the mirror image of how
/// [wrapSelection] placed them, so a caret left between the delimiters (or a
/// selection wrapSelection just wrapped) lands back exactly where it started.
TextEditingValue unwrap(
  TextEditingValue v,
  int start,
  int end,
  int beforeLen,
  int afterLen,
) {
  final len = v.text.length;
  final s = start.clamp(0, len);
  final e = end.clamp(s, len);
  final innerStart = (s + beforeLen).clamp(s, e);
  final innerEnd = (e - afterLen).clamp(innerStart, e);
  final text = v.text.replaceRange(s, e, v.text.substring(innerStart, innerEnd));
  final removed = innerStart - s;

  int shift(int o) {
    if (o <= s) return o;
    if (o <= innerStart) return s;
    if (o <= innerEnd) return o - removed;
    if (o <= e) return innerEnd - removed;
    return o - removed - (e - innerEnd);
  }

  final sel = _sel(v);
  return TextEditingValue(
    text: text,
    selection: TextSelection(
      baseOffset: shift(sel.baseOffset),
      extentOffset: shift(sel.extentOffset),
    ),
  );
}

/// Removes exactly [prefixLen] characters starting at [lineStart] — the
/// inverse of [prefixLines] for a single line (Story 2.14). Total: [lineStart]/
/// [prefixLen] clamp to the text length. Selection offsets before the removed
/// span are unchanged, offsets inside it collapse to [lineStart], and offsets
/// after it shift left by the amount actually removed.
TextEditingValue unprefixLine(TextEditingValue v, int lineStart, int prefixLen) {
  final len = v.text.length;
  final s = lineStart.clamp(0, len);
  final removeEnd = (s + prefixLen).clamp(s, len);
  final text = v.text.replaceRange(s, removeEnd, '');
  final removed = removeEnd - s;

  int shift(int o) {
    if (o <= s) return o;
    if (o <= removeEnd) return s;
    return o - removed;
  }

  final sel = _sel(v);
  return TextEditingValue(
    text: text,
    selection: TextSelection(
      baseOffset: shift(sel.baseOffset),
      extentOffset: shift(sel.extentOffset),
    ),
  );
}

// --- Active-state derivation (Story 2.14, AC1/AC3) -------------------------
//
// Two shapes of ConventionKind, two matching strategies:
// - Inline kinds (bold/italic/wikilink): the token span IS the formatted
//   region, so "active" means the caret/selection sits inside that span.
// - Line-anchored kinds (heading/listMarker): the matcher's own token can be
//   short (listMarker covers only e.g. "- ", not the rest of the line — see
//   convention_matcher.dart's _matchLine), so "active" means the caret's
//   *line* starts with a recognized token of that kind, checked anywhere on
//   the line — matching how a user thinks about "this line is a bullet."
// Either way, the matcher alone finds/classifies the span; only which
// *button* it corresponds to (H1 vs H2, bullet vs numbered) is decided here
// by reading the token's own line text — not new recognition (AD-7).

/// Whether the current [sel] sits inside a token of [kind] whose span **is**
/// the formatted region (bold/italic/wikilink). A collapsed caret counts at
/// either edge of the span; a non-empty selection must be entirely contained.
///
/// `ConventionToken` is documented (convention_matcher.dart) as a half-open
/// `[start, end)` span — this check is deliberately inclusive of `end` too,
/// a one-button-wider definition of "active" than the matcher's own span
/// convention. The reason: [wrapSelection] places a fresh collapsed caret at
/// `token.start + before.length`, which is comfortably inside `[start, end)`
/// either way, but a caret a user moves to the boundary right after typing
/// the closing delimiter (e.g. right after `**bold**`) should still read as
/// "in this bold run" for toggle-off to be reachable there, matching how a
/// caret at a formatted span's edge behaves in most rich-text editors.
bool isFormattingActive(
  List<ConventionToken> tokens,
  TextSelection sel,
  ConventionKind kind,
) =>
    _activeToken(tokens, sel, kind) != null;

/// The token of [kind] the current [sel] sits inside, if any — same
/// containment rule as [isFormattingActive], but returns the token itself so
/// a toggle-off operation knows exactly what span to unwrap.
ConventionToken? _activeToken(
  List<ConventionToken> tokens,
  TextSelection sel,
  ConventionKind kind,
) {
  final s = sel.start, e = sel.end;
  for (final t in tokens) {
    if (t.kind != kind) continue;
    if (sel.isCollapsed) {
      if (t.start <= s && s <= t.end) return t;
    } else {
      if (t.start <= s && e <= t.end) return t;
    }
  }
  return null;
}

/// Start offset of the line containing [offset] (mirrors [prefixLines]'
/// firstLineStart derivation).
int _lineStartAt(String text, int offset) {
  final o = offset.clamp(0, text.length);
  return o == 0 ? 0 : text.lastIndexOf('\n', o - 1) + 1;
}

/// Whether [sel] sits entirely within one line, and that line has a [kind]
/// token starting at its very beginning (heading/listMarker are both
/// line-anchored in the matcher).
bool _lineHasLeadingToken(
  String text,
  List<ConventionToken> tokens,
  TextSelection sel,
  ConventionKind kind,
) {
  final lineStart = _lineStartAt(text, sel.start);
  if (_lineStartAt(text, sel.end) != lineStart) return false; // spans lines
  return tokens.any((t) => t.kind == kind && t.start == lineStart);
}

// Exact `#` count + exactly one trailing space/tab — matches the matcher's
// own `_heading` pattern (`^#{1,6}[ \t]`) per level, so a tab is recognized
// just as validly as a space, and a level match can never also satisfy a
// different level's pattern (the character right after the exact `#` run is
// never another `#`, or the count wouldn't be exact).
final List<RegExp> _headingPrefixByLevel = [
  RegExp(r'^#[ \t]'),
  RegExp(r'^##[ \t]'),
  RegExp(r'^###[ \t]'),
];

/// H1/H2/H3 active state ([level] 1–3). `heading` is one [ConventionKind] for
/// H1–H6, so the token alone can't tell the three buttons apart.
bool isHeadingActive(
  String text,
  List<ConventionToken> tokens,
  TextSelection sel,
  int level,
) {
  if (!_lineHasLeadingToken(text, tokens, sel, ConventionKind.heading)) {
    return false;
  }
  return _headingPrefixByLevel[level - 1]
      .hasMatch(text.substring(_lineStartAt(text, sel.start)));
}

/// The prefix length to strip for heading [level] on toggle-off — always
/// `level + 1`: the matcher's pattern only ever matches exactly one trailing
/// whitespace char after the `#` run, never a run of them, so this never
/// needs to be read from the actual match the way bullet/numbered do.
int headingPrefixLength(int level) => level + 1;

final RegExp _bulletLinePrefix = RegExp(r'^[ \t]*[-*][ \t]');
final RegExp _numberedLinePrefix = RegExp(r'^[ \t]*\d+\.[ \t]');

/// Bullet-list active state — `listMarker` covers both bullets and numbered
/// items, so a regex on the line's own text picks out which this is. Matches
/// `-`/`*`, not the toolbar's own fixed insert literal.
bool isBulletActive(String text, List<ConventionToken> tokens, TextSelection sel) {
  if (!_lineHasLeadingToken(text, tokens, sel, ConventionKind.listMarker)) {
    return false;
  }
  return _bulletLinePrefix.hasMatch(text.substring(_lineStartAt(text, sel.start)));
}

/// Numbered-list active state — matches **any** `\d+\.` marker (e.g. `42. `),
/// not just the literal `'1. '` the toolbar's own insert always writes.
bool isNumberedActive(String text, List<ConventionToken> tokens, TextSelection sel) {
  if (!_lineHasLeadingToken(text, tokens, sel, ConventionKind.listMarker)) {
    return false;
  }
  return _numberedLinePrefix.hasMatch(text.substring(_lineStartAt(text, sel.start)));
}

/// The actual matched bullet-marker length at [sel]'s line — leading
/// whitespace varies (`'- '` is 2 chars, `'  - '` is 4), so toggle-off must
/// strip what's really there, not an assumed fixed length. `null` if the
/// line doesn't match (defensive; callers only use this when [isBulletActive]
/// is already true).
int? bulletPrefixLength(String text, TextSelection sel) =>
    _bulletLinePrefix.firstMatch(text.substring(_lineStartAt(text, sel.start)))?.end;

/// The actual matched numbered-marker length at [sel]'s line — the digit run
/// width varies (`'1. '` is 3 chars, `'42. '` is 4), so toggle-off must strip
/// what's really there. `null` if the line doesn't match.
int? numberedPrefixLength(String text, TextSelection sel) =>
    _numberedLinePrefix.firstMatch(text.substring(_lineStartAt(text, sel.start)))?.end;

/// A horizontally-scrollable quick-insert row above the keyboard (FR8): a
/// structure group and a project-token group, over the three mechanisms.
///
/// Stateful (Story 2.14): 8 of the 12 buttons (H1–H3, Bullet, Numbered, Bold,
/// Italic, Wikilink) show an **active** state and toggle off when tapped
/// while active. That state depends on the caret/selection, which changes on
/// every keystroke and every caret move — not just when the host
/// [FileEditor]'s dirty flag flips (its only other rebuild trigger). This
/// widget owns its own [controller] listener so it repaints live regardless
/// of the host's rebuild cadence.
class EditorToolbar extends StatefulWidget {
  final TextEditingController controller;

  const EditorToolbar({super.key, required this.controller});

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(EditorToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Defensive: the current call site (FileEditor) never swaps its
    // controller (it's `final`), but if a future host ever did, this keeps
    // the listener attached to the live controller instead of silently going
    // stale — the exact failure mode this widget's statefulness exists to
    // avoid (see class doc comment).
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _apply(TextEditingValue Function(TextEditingValue) op) {
    widget.controller.value = op(widget.controller.value);
  }

  /// Inserts the dialogue-line template on exactly one line, regardless of
  /// how much text is selected. `prefixLines` repeats its prefix on every
  /// touched line — the right behavior for a short repeatable marker (H1,
  /// `- `, …), but `'Name (emotion): '` is a one-off template, not a marker;
  /// applied to a multi-line selection it would duplicate the literal text
  /// onto every line. Collapsing to the selection's start first keeps this a
  /// single-line insert no matter what was selected.
  void _insertDialogueLine() {
    _apply((v) {
      final collapsed = TextEditingValue(
        text: v.text,
        selection: TextSelection.collapsed(offset: _sel(v).start),
      );
      return prefixLines(collapsed, 'Name (emotion): ');
    });
  }

  void _toggleHeading(int level, bool active, String text, TextSelection sel) {
    if (active) {
      final lineStart = _lineStartAt(text, sel.start);
      _apply((v) => unprefixLine(v, lineStart, headingPrefixLength(level)));
    } else {
      _apply((v) => prefixLines(v, '${'#' * level} '));
    }
  }

  void _toggleBullet(bool active, String text, TextSelection sel) {
    if (active) {
      final lineStart = _lineStartAt(text, sel.start);
      final len = bulletPrefixLength(text, sel) ?? 0;
      _apply((v) => unprefixLine(v, lineStart, len));
    } else {
      _apply((v) => prefixLines(v, '- '));
    }
  }

  void _toggleNumbered(bool active, String text, TextSelection sel) {
    if (active) {
      final lineStart = _lineStartAt(text, sel.start);
      final len = numberedPrefixLength(text, sel) ?? 0;
      _apply((v) => unprefixLine(v, lineStart, len));
    } else {
      _apply((v) => prefixLines(v, '1. '));
    }
  }

  void _toggleWrap(
    ConventionKind kind,
    bool active,
    List<ConventionToken> tokens,
    TextSelection sel,
    String before,
    String after,
  ) {
    if (active) {
      final token = _activeToken(tokens, sel, kind)!; // active implies found
      _apply((v) => unwrap(v, token.start, token.end, before.length, after.length));
    } else {
      _apply((v) => wrapSelection(v, before, after));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = widget.controller.value;
    final text = value.text;
    final sel = _sel(value); // normalized + clamped, same guard every op below uses
    final tokens = matchConventions(text);

    final h1Active = isHeadingActive(text, tokens, sel, 1);
    final h2Active = isHeadingActive(text, tokens, sel, 2);
    final h3Active = isHeadingActive(text, tokens, sel, 3);
    final bulletActive = isBulletActive(text, tokens, sel);
    final numberedActive = isNumberedActive(text, tokens, sel);
    final boldActive = isFormattingActive(tokens, sel, ConventionKind.bold);
    final italicActive = isFormattingActive(tokens, sel, ConventionKind.italic);
    final wikilinkActive = isFormattingActive(tokens, sel, ConventionKind.wikilink);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      // The buttons must not steal focus from the editor's TextField — that
      // would dismiss the soft keyboard the toolbar sits above (FR8). A
      // non-focusable Focus subtree lets taps fire while the field keeps focus.
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: SizedBox(
          height: 48,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _TextBtn(
                  'H1',
                  'Heading 1',
                  active: h1Active,
                  onPressed: () => _toggleHeading(1, h1Active, text, sel),
                ),
                _TextBtn(
                  'H2',
                  'Heading 2',
                  active: h2Active,
                  onPressed: () => _toggleHeading(2, h2Active, text, sel),
                ),
                _TextBtn(
                  'H3',
                  'Heading 3',
                  active: h3Active,
                  onPressed: () => _toggleHeading(3, h3Active, text, sel),
                ),
                _IconBtn(
                  Icons.format_list_bulleted,
                  'Bullet list',
                  active: bulletActive,
                  onPressed: () => _toggleBullet(bulletActive, text, sel),
                ),
                _IconBtn(
                  Icons.format_list_numbered,
                  'Numbered list',
                  active: numberedActive,
                  onPressed: () => _toggleNumbered(numberedActive, text, sel),
                ),
                _IconBtn(
                  Icons.format_bold,
                  'Bold',
                  active: boldActive,
                  onPressed: () => _toggleWrap(
                      ConventionKind.bold, boldActive, tokens, sel, '**', '**'),
                ),
                _IconBtn(
                  Icons.format_italic,
                  'Italic',
                  active: italicActive,
                  onPressed: () => _toggleWrap(
                      ConventionKind.italic, italicActive, tokens, sel, '_', '_'),
                ),
                const VerticalDivider(width: 8, indent: 8, endIndent: 8),
                _TextBtn(
                  '[[',
                  'Wikilink',
                  active: wikilinkActive,
                  onPressed: () => _toggleWrap(ConventionKind.wikilink,
                      wikilinkActive, tokens, sel, '[[', ']]'),
                ),
                _IconBtn(
                  Icons.chat_bubble_outline,
                  'Dialogue line',
                  onPressed: _insertDialogueLine,
                ),
                _IconBtn(
                  Icons.call_made,
                  'Passage link',
                  onPressed: () => _apply(
                      (v) => insertAtCursor(v, '[[Choice->Passage Name]]')),
                ),
                _IconBtn(
                  Icons.keyboard_return,
                  'Return link',
                  onPressed: () =>
                      _apply((v) => insertAtCursor(v, '[[back<-Label]]')),
                ),
                _IconBtn(
                  Icons.link,
                  'External link',
                  onPressed: () =>
                      _apply((v) => insertAtCursor(v, '[label](url)')),
                ),
                const VerticalDivider(width: 8, indent: 8, endIndent: 8),
                _TextBtn(
                  '[',
                  'Open bracket',
                  onPressed: () => _apply((v) => insertAtCursor(v, '[')),
                ),
                _TextBtn(
                  ']',
                  'Close bracket',
                  onPressed: () => _apply((v) => insertAtCursor(v, ']')),
                ),
                _TextBtn(
                  '—',
                  'Em dash',
                  onPressed: () => _apply((v) => insertAtCursor(v, '—')),
                ),
                _TextBtn(
                  '(emotion):',
                  'Dialogue emotion',
                  onPressed: () => _apply((v) => insertAtCursor(v, '(emotion): ')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  const _IconBtn(this.icon, this.tooltip, {required this.onPressed, this.active = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: active ? theme.colorScheme.primaryContainer : null,
        foregroundColor: active ? theme.colorScheme.onPrimaryContainer : null,
      ),
    );
  }
}

class _TextBtn extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  const _TextBtn(this.label, this.tooltip, {required this.onPressed, this.active = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: active ? theme.colorScheme.primaryContainer : null,
          foregroundColor: active ? theme.colorScheme.onPrimaryContainer : null,
        ),
        child: Text(label, style: const TextStyle(fontFamily: 'monospace')),
      ),
    );
  }
}
