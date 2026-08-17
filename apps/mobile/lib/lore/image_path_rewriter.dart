/// Rewrites local-relative image references so they survive an entity card
/// moving one directory level deeper (Story 5.1, `<slug>.md` →
/// `<slug>/<slug>.md`, FR26).
///
/// Story 2.16's `_resolveImage` (`app/markdown_preview.dart`) resolves an
/// `![alt](src)` image relative to the card's *current* directory, recomputed
/// fresh on every render — there is no stored absolute path. Story 2.17's
/// promotion (`app/category_entities_page.dart`) moves the card without
/// touching its content, so any relative `src` that resolved correctly before
/// the move silently breaks after it. Promotion always adds exactly one
/// directory level, so prepending `../` to every local-relative `src` exactly
/// compensates — no `.`/`..` segment resolution needed on this (write) side;
/// that walk already exists, purely for reading, in `_resolveImage`.
///
/// **Surgical, not a re-serialize (AD-4 — writes are byte-exact except the
/// intended change):** this is a targeted substring replace of just the `src`
/// inside each recognized `![alt](src)` / `![alt](src "title")` — every other
/// byte, including any image markup this simple scan doesn't recognize, is
/// left untouched rather than round-tripped through a markdown AST.
///
/// Pure Dart — no Flutter, no `dart:io` (AD-9). **Total** (AD-8): never
/// throws; a `src` that can't be confidently identified as local-relative
/// (network, absolute) is left unchanged, and markup this scan can't parse is
/// simply not matched, not corrupted.
library;

/// Matches `![alt](src)` or `![alt](src "title")`. Alt text (group 1) may not
/// contain `]` or a newline; the src+optional-title tail (group 2) is
/// captured whole and split apart in [_rewriteTail] — deliberately
/// conservative (mirrors this project's "parser stays shallow" convention,
/// ADR 3): anything outside this shape is left untouched rather than guessed
/// at.
final RegExp _imagePattern = RegExp(
    r'!\[([^\]\n]*)\]\(((?:<[^>\n]*>|[^()\s]+)(?:\s+"[^"\n]*")?)\)');

/// Rewrites every local-relative image `src` in [content] by prepending
/// `../`, leaving network (`http://`/`https://`) and filesystem-absolute
/// (leading `/`, or a Windows drive letter like `C:\`) references untouched.
/// Returns [content] unchanged if it contains no recognized image markup, or
/// on any internal failure.
String rewriteRelativeImagePaths(String content) {
  try {
    final matches = _imagePattern.allMatches(content).toList();
    if (matches.isEmpty) return content;

    final buffer = StringBuffer();
    var last = 0;
    for (final match in matches) {
      final alt = match.group(1) ?? '';
      final tail = match.group(2) ?? '';
      final rewrittenTail = _rewriteTail(tail);
      if (rewrittenTail == null) continue; // nothing to rewrite here

      buffer.write(content.substring(last, match.start));
      buffer.write('![$alt]($rewrittenTail)');
      last = match.end;
    }
    buffer.write(content.substring(last));
    return buffer.toString();
  } catch (_) {
    return content;
  }
}

/// Splits [tail] (everything between `](` and `)`, e.g. `media/x.jpg`,
/// `media/x.jpg "title"`, or `<media/x.jpg>`) into its src token and the
/// unchanged remainder (an optional ` "title"` suffix), rewrites the src if
/// it's local-relative, and reassembles — or returns `null` if [tail] needs
/// no change (network/absolute src).
String? _rewriteTail(String tail) {
  String srcToken;
  String rest;
  var angleWrapped = false;
  if (tail.startsWith('<')) {
    final closeIndex = tail.indexOf('>');
    angleWrapped = closeIndex != -1;
    srcToken = angleWrapped ? tail.substring(1, closeIndex) : tail;
    rest = angleWrapped ? tail.substring(closeIndex + 1) : '';
  } else {
    final spaceIndex = tail.indexOf(' ');
    srcToken = spaceIndex == -1 ? tail : tail.substring(0, spaceIndex);
    rest = spaceIndex == -1 ? '' : tail.substring(spaceIndex);
  }

  if (!_needsRewrite(srcToken)) return null;
  final rewrittenSrc = '../$srcToken';
  return (angleWrapped ? '<$rewrittenSrc>' : rewrittenSrc) + rest;
}

/// A Windows drive-letter absolute path, e.g. `C:\images\hero.png`.
final RegExp _windowsDrivePath = RegExp(r'^[A-Za-z]:[\\/]');

/// Whether [src] is a local-relative reference that should be rewritten —
/// false for empty strings, network URLs, and filesystem-absolute paths.
bool _needsRewrite(String src) {
  if (src.isEmpty) return false;
  final lower = src.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return false;
  }
  if (src.startsWith('/')) return false;
  if (_windowsDrivePath.hasMatch(src)) return false;
  return true;
}
