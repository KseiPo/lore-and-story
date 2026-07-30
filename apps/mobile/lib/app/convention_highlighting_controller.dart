import 'package:flutter/material.dart';

import '../lore/lore.dart';
import 'convention_styles.dart';

/// Every convention kind — the editor highlights all of them (unlike the
/// preview, which lets markdown render the structural ones). Unmodifiable so a
/// future edit can't accidentally mutate the shared set for every controller.
final Set<ConventionKind> _allKinds = Set.unmodifiable(ConventionKind.values);

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
      final scheme = Theme.of(context).colorScheme;
      final base = style ?? const TextStyle();
      // The editor styles ALL kinds (the buffer is raw markdown, so structural
      // markers show too). Shared with the preview via convention_styles.dart —
      // one style map, one span builder, one span-text-equals-input invariant.
      final spans = buildConventionSpans(
        source,
        tokens,
        base: style,
        apply: _allKinds,
        styleFor: (kind) => styleForConvention(kind, scheme, base),
      );
      return TextSpan(style: style, children: spans);
    } catch (_) {
      // Never throw, never hide/drop text (AD-8 / NFR7).
      return TextSpan(text: source, style: style);
    }
  }
}
