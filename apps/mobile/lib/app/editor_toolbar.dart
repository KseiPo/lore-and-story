import 'package:flutter/material.dart';

/// The helper toolbar (FR8) and its pure text-operation functions.
///
/// The three mechanisms — insert-at-cursor, wrap-selection, prefix-line — are
/// pure functions over [TextEditingValue] (text + selection), so they unit-test
/// without a widget. The [EditorToolbar] widget applies them to the editor's
/// controller.

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

/// Prepends [prefix] to the start of every line the selection touches (v0.1:
/// always prepend — no un-prefix toggle).
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

/// A horizontally-scrollable quick-insert row above the keyboard (FR8): a
/// structure group and a project-token group, over the three mechanisms.
class EditorToolbar extends StatelessWidget {
  final TextEditingController controller;

  const EditorToolbar({super.key, required this.controller});

  void _apply(TextEditingValue Function(TextEditingValue) op) {
    controller.value = op(controller.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  () => _apply((v) => prefixLines(v, '# ')),
                ),
                _TextBtn(
                  'H2',
                  'Heading 2',
                  () => _apply((v) => prefixLines(v, '## ')),
                ),
                _TextBtn(
                  'H3',
                  'Heading 3',
                  () => _apply((v) => prefixLines(v, '### ')),
                ),
                _IconBtn(
                  Icons.format_list_bulleted,
                  'Bullet list',
                  () => _apply((v) => prefixLines(v, '- ')),
                ),
                _IconBtn(
                  Icons.format_list_numbered,
                  'Numbered list',
                  () => _apply((v) => prefixLines(v, '1. ')),
                ),
                _IconBtn(
                  Icons.format_bold,
                  'Bold',
                  () => _apply((v) => wrapSelection(v, '**', '**')),
                ),
                _IconBtn(
                  Icons.format_italic,
                  'Italic',
                  () => _apply((v) => wrapSelection(v, '_', '_')),
                ),
                const VerticalDivider(width: 8, indent: 8, endIndent: 8),
                _TextBtn(
                  '[[',
                  'Wikilink',
                  () => _apply((v) => wrapSelection(v, '[[', ']]')),
                ),
                _TextBtn(
                  '[',
                  'Open bracket',
                  () => _apply((v) => insertAtCursor(v, '[')),
                ),
                _TextBtn(
                  ']',
                  'Close bracket',
                  () => _apply((v) => insertAtCursor(v, ']')),
                ),
                _TextBtn(
                  '—',
                  'Em dash',
                  () => _apply((v) => insertAtCursor(v, '—')),
                ),
                _TextBtn(
                  '(emotion):',
                  'Dialogue emotion',
                  () => _apply((v) => insertAtCursor(v, '(emotion): ')),
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
  const _IconBtn(this.icon, this.tooltip, this.onPressed);

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 20),
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
  );
}

class _TextBtn extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  const _TextBtn(this.label, this.tooltip, this.onPressed);

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(label, style: const TextStyle(fontFamily: 'monospace')),
    ),
  );
}
