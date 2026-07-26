import 'package:flutter/material.dart';

import '../lore/lore.dart';

/// A [TextEditingController] that renders the raw buffer with convention-aware
/// syntax highlighting (FR9) by overriding [buildTextSpan] — the buffer stays
/// **raw markdown** (display-only; typing `**x**` shows `**x**`).
///
/// It holds **no** matching logic: it consumes [matchConventions] (the pure
/// `lore/` matcher — AD-7) and maps each [ConventionKind] to a [TextStyle].
///
/// **Total (AD-8):** on any failure `buildTextSpan` returns a plain span. The
/// concatenation of the emitted spans' text always equals the buffer exactly —
/// highlighting never drops, adds, reorders, or hides a character.
class ConventionHighlightingController extends TextEditingController {
  ConventionHighlightingController({super.text});

  // A tiny by-text memo: buildTextSpan runs on every rebuild (selection, focus,
  // theme), not only on text change — so reuse the last tokens when the buffer
  // is unchanged rather than re-matching. (Per-keystroke matching of very long
  // scenes is a separate, deferred concern; the regexes are linear.)
  String? _cachedText;
  List<ConventionToken>? _cachedTokens;

  List<ConventionToken> _tokensFor(String source) {
    if (source == _cachedText && _cachedTokens != null) return _cachedTokens!;
    final tokens = matchConventions(source);
    _cachedText = source;
    _cachedTokens = tokens;
    return tokens;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    try {
      final tokens = _tokensFor(source);
      final spans = <InlineSpan>[];
      var i = 0;
      for (final t in tokens) {
        // Defensive: ignore any out-of-range or overlapping token so a matcher
        // regression can never corrupt what the user sees.
        if (t.start < i || t.end > source.length || t.start >= t.end) continue;
        if (t.start > i) {
          spans.add(TextSpan(text: source.substring(i, t.start), style: style));
        }
        spans.add(TextSpan(
          text: source.substring(t.start, t.end),
          style: _styleFor(t.kind, context, style),
        ));
        i = t.end;
      }
      if (i < source.length) {
        spans.add(TextSpan(text: source.substring(i), style: style));
      }
      if (spans.isEmpty) return TextSpan(text: source, style: style);
      return TextSpan(style: style, children: spans);
    } catch (_) {
      // Never throw, never hide/drop text (AD-8 / NFR7).
      return TextSpan(text: source, style: style);
    }
  }

  TextStyle _styleFor(ConventionKind kind, BuildContext context, TextStyle? base) {
    final scheme = Theme.of(context).colorScheme;
    final b = base ?? const TextStyle();
    switch (kind) {
      case ConventionKind.heading:
        return b.copyWith(
          fontWeight: FontWeight.bold,
          color: scheme.primary,
          fontSize: (b.fontSize ?? 14) * 1.15,
        );
      case ConventionKind.bold:
        return b.copyWith(fontWeight: FontWeight.bold);
      case ConventionKind.italic:
        return b.copyWith(fontStyle: FontStyle.italic);
      case ConventionKind.listMarker:
        return b.copyWith(color: scheme.primary, fontWeight: FontWeight.bold);
      case ConventionKind.wikilink:
        return b.copyWith(color: scheme.tertiary, fontWeight: FontWeight.w600);
      case ConventionKind.dialogueSpeaker:
        return b.copyWith(color: scheme.secondary, fontWeight: FontWeight.w600);
      case ConventionKind.placeholder:
        return b.copyWith(color: scheme.tertiary, fontStyle: FontStyle.italic);
      case ConventionKind.emDash:
        return b.copyWith(color: scheme.primary);
    }
  }
}
