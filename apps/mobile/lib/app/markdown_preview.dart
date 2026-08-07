import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show GestureRecognizer, TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'convention_styles.dart';

/// A read-only rendered view of markdown [text] (FR10).
///
/// Standalone by design: it takes only the markdown string, so the editor's
/// preview toggle (Story 2.7) and the detail-card preview (Story 2.13) both use
/// it. Story 2.16 *extends* it (optional `storage`/`filePath`) to load local
/// repo images instead of showing alt-text-only — without restructuring. It
/// never edits — this is a distinct render mode, not a WYSIWYG surface.
///
/// **Total (AD-8 / NFR7):** parsing/building is wrapped so a malformed document
/// can never throw — it degrades to a plain-text rendering of the raw buffer.
/// Per-image load failures are a *separate* failure surface (missing/unreadable/
/// non-image/oversized/network) handled entirely inside the image widget itself
/// — see `_RepoImage` — so one bad image can never blank the whole preview.
///
/// The parser runs with `encodeHtml: false` so raw text (including this
/// project's `[[wikilinks]]`, `Name (emotion):`, and leaked `<<twee>>`/`<html>`)
/// survives into text nodes verbatim — that is what lets the convention styling
/// (see `_conventionSpans`) flag it, and what keeps the display free of
/// `&lt;`-style HTML entities.
class MarkdownPreview extends StatefulWidget {
  final String text;

  /// When non-null (together with [filePath]), a local-relative image `src` is
  /// resolved against [filePath]'s directory and loaded through this port
  /// (Story 2.16). When null, images render as alt text only (Story 2.7's
  /// original behavior) — the safe default for any caller that doesn't have a
  /// file context.
  final RepoStorage? storage;

  /// Repo-relative path of the file whose buffer is being previewed — the
  /// anchor a local image `src` is resolved relative to. Ignored unless
  /// [storage] is also set.
  final String? filePath;

  /// Called with an entity title when a `[[wikilink]]` is tapped (Story 3.2,
  /// FR19). `null` (the default) leaves wikilinks styled but not tappable —
  /// e.g. `EntityDetailPage`'s card preview, which is intentionally
  /// non-interactive (wrapped in `AbsorbPointer`).
  final void Function(String title)? onWikilinkTap;

  const MarkdownPreview({
    super.key,
    required this.text,
    this.storage,
    this.filePath,
    this.onWikilinkTap,
  });

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  /// Recognizers created by the current build's `_MarkdownRenderer` — a
  /// `TapGestureRecognizer` leaks if never disposed.
  List<TapGestureRecognizer> _recognizers = [];

  /// (Review fix) Disposal is deferred one frame past the build that
  /// orphaned these recognizers, not run synchronously at the start of the
  /// very next `build()`. A rebuild can land between a pointer-down and
  /// pointer-up on a wikilink (e.g. `_loadEntries`'s one-time `setState` in
  /// the hosting `FileEditor` while the user is mid-tap) — disposing the
  /// in-arena recognizer immediately risks silently dropping that gesture.
  /// Deferring past paint gives the current frame's gesture handling a
  /// chance to resolve first.
  void _scheduleDisposal(List<TapGestureRecognizer> orphaned) {
    if (orphaned.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in orphaned) {
        r.dispose();
      }
    });
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final newRecognizers = <TapGestureRecognizer>[];
    Widget child;
    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      );
      final nodes = document.parseLines(const LineSplitter().convert(widget.text));
      final blocks = _MarkdownRenderer(
        context,
        storage: widget.storage,
        filePath: widget.filePath,
        onWikilinkTap: widget.onWikilinkTap,
        registerRecognizer: newRecognizers.add,
      ).blocks(nodes);
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks.isEmpty ? const [SizedBox.shrink()] : blocks,
      );
    } catch (_) {
      // Never an error screen: show the raw buffer best-effort.
      child = SelectableText(widget.text);
    }
    _scheduleDisposal(_recognizers);
    _recognizers = newRecognizers;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

/// Walks the `markdown` AST into read-only Flutter widgets. Held per-build so it
/// can read the ambient [Theme].
class _MarkdownRenderer {
  final BuildContext context;
  final RepoStorage? storage;
  final String? filePath;

  /// Story 3.2 — fires with an entity title when a `[[wikilink]]` is tapped.
  /// Null when the host [MarkdownPreview] wasn't given `onWikilinkTap`.
  final void Function(String title)? onWikilinkTap;

  /// Story 3.2 — every `TapGestureRecognizer` this renderer creates is handed
  /// to the host state via this callback so it can be disposed later; this
  /// renderer itself is a fresh, per-build, non-State object with nowhere to
  /// own that lifecycle.
  final void Function(TapGestureRecognizer recognizer) registerRecognizer;

  late final ThemeData theme = Theme.of(context);
  late final TextTheme textTheme = theme.textTheme;
  late final ColorScheme scheme = theme.colorScheme;

  _MarkdownRenderer(
    this.context, {
    this.storage,
    this.filePath,
    this.onWikilinkTap,
    required this.registerRecognizer,
  });

  static const _blockGap = SizedBox(height: 8);

  /// Renders a list of block-level nodes, gap-separated.
  List<Widget> blocks(List<md.Node> nodes) {
    final out = <Widget>[];
    for (final node in nodes) {
      final w = _block(node);
      if (w == null) continue;
      if (out.isNotEmpty) out.add(_blockGap);
      out.add(w);
    }
    return out;
  }

  Widget? _block(md.Node node) {
    if (node is md.Text) {
      // Stray top-level text (rare) — render as a paragraph.
      return _paragraph([node]);
    }
    if (node is! md.Element) return null;
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'h1':
        return _heading(children, textTheme.headlineMedium);
      case 'h2':
        return _heading(children, textTheme.headlineSmall);
      case 'h3':
        return _heading(children, textTheme.titleLarge);
      case 'h4':
        return _heading(children, textTheme.titleMedium);
      case 'h5':
        return _heading(children, textTheme.titleSmall);
      case 'h6':
        return _heading(children, textTheme.labelLarge);
      case 'p':
        return _paragraph(children);
      case 'ul':
        return _list(node, ordered: false);
      case 'ol':
        return _list(node, ordered: true);
      case 'blockquote':
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: scheme.outline, width: 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: blocks(children),
          ),
        );
      case 'pre':
        return _codeBlock(node);
      case 'hr':
        return Divider(color: scheme.outlineVariant, height: 16);
      case 'table':
        return _table(node);
      default:
        // Unknown block: render its inline content so nothing is dropped.
        return _paragraph(children);
    }
  }

  Widget _heading(List<md.Node> children, TextStyle? style) {
    final base = (style ?? textTheme.titleLarge ?? const TextStyle())
        .copyWith(color: scheme.primary);
    return Text.rich(TextSpan(children: _inline(children, base, atLineStart: true)));
  }

  Widget _paragraph(List<md.Node> children) {
    final base = textTheme.bodyMedium ?? const TextStyle();
    return Text.rich(TextSpan(children: _inline(children, base, atLineStart: true)));
  }

  /// A fenced/indented code block: `pre > code > text`, rendered verbatim in a
  /// monospace, tinted container.
  Widget _codeBlock(md.Element pre) {
    final buffer = StringBuffer();
    void collect(md.Node n) {
      if (n is md.Text) {
        buffer.write(n.text);
      } else if (n is md.Element) {
        for (final c in n.children ?? const <md.Node>[]) {
          collect(c);
        }
      }
    }

    for (final c in pre.children ?? const <md.Node>[]) {
      collect(c);
    }
    var code = buffer.toString();
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        code,
        style: (textTheme.bodyMedium ?? const TextStyle())
            .copyWith(fontFamily: 'monospace'),
      ),
    );
  }

  /// An ordered/unordered list. Each `li` renders its own inline content plus
  /// any nested block lists, prefixed with a bullet or index marker.
  Widget _list(md.Element list, {required bool ordered}) {
    final base = textTheme.bodyMedium ?? const TextStyle();
    final items = <Widget>[];
    // Honor a list that doesn't start at 1 (`5. …` sets the `start` attribute).
    var index = ordered ? (int.tryParse(list.attributes['start'] ?? '') ?? 1) : 1;
    for (final li in list.children ?? const <md.Node>[]) {
      if (li is! md.Element || li.tag != 'li') continue;
      final marker = ordered ? '$index.' : '•';
      index++;

      // Split an li's children into inline runs and nested BLOCK children.
      // Classify by the known set of *inline* tags — anything else (a nested
      // heading, `hr`, table, …) is a block, so it isn't flattened into the
      // inline run (which would lose its structure, or drop a childless `hr`).
      final inlineKids = <md.Node>[];
      final blockKids = <md.Node>[];
      for (final c in li.children ?? const <md.Node>[]) {
        if (c is md.Element && !_inlineTags.contains(c.tag)) {
          blockKids.add(c);
        } else {
          inlineKids.add(c);
        }
      }

      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(marker, style: base.copyWith(color: scheme.primary)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (inlineKids.isNotEmpty)
                    Text.rich(TextSpan(
                        children: _inline(inlineKids, base, atLineStart: true))),
                  ...blocks(blockKids),
                ],
              ),
            ),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }

  /// A GFM table: `table > thead/tbody > tr > th/td`. Rendered as a simple
  /// bordered [Table] so cells stay in columns instead of running together.
  Widget _table(md.Element table) {
    final base = textTheme.bodyMedium ?? const TextStyle();
    final rows = <TableRow>[];
    void addRows(md.Element section, {required bool header}) {
      for (final tr in section.children ?? const <md.Node>[]) {
        if (tr is! md.Element || tr.tag != 'tr') continue;
        final cells = <Widget>[];
        for (final cell in tr.children ?? const <md.Node>[]) {
          if (cell is! md.Element) continue;
          final style = header ? base.copyWith(fontWeight: FontWeight.bold) : base;
          cells.add(Padding(
            padding: const EdgeInsets.all(6),
            child: Text.rich(TextSpan(
                children: _inline(cell.children ?? const [], style, atLineStart: true))),
          ));
        }
        if (cells.isNotEmpty) rows.add(TableRow(children: cells));
      }
    }

    for (final section in table.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      if (section.tag == 'thead') addRows(section, header: true);
      if (section.tag == 'tbody') addRows(section, header: false);
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    // Table requires every row to have the same column count; pad short rows.
    final cols = rows.map((r) => r.children.length).fold(0, (a, b) => a > b ? a : b);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.children.length < cols) {
        rows[i] = TableRow(children: [
          ...r.children,
          for (var j = r.children.length; j < cols; j++) const SizedBox.shrink(),
        ]);
      }
    }
    return Table(
      border: TableBorder.all(color: scheme.outlineVariant),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: rows,
    );
  }

  /// Markdown element tags that are inline (vs. block). Used to route a list
  /// item's children and to know a text run's line-start position.
  static const _inlineTags = {
    'strong', 'em', 'del', 'code', 'a', 'br', 'img', 'input',
  };

  /// Renders inline nodes to spans against [base]. An `img` becomes a
  /// [WidgetSpan] (alt text placeholder in this story — Story 2.16 loads it).
  ///
  /// [atLineStart] is true when these nodes begin a block (paragraph/heading/li)
  /// — only then may a line-anchored convention (dialogue speaker) match the
  /// first text run. It never carries into a nested element's children, so a
  /// text fragment after inline emphasis is treated as mid-line (correctly).
  List<InlineSpan> _inline(List<md.Node> nodes, TextStyle base,
      {bool atLineStart = false}) {
    final spans = <InlineSpan>[];
    var lineStart = atLineStart;
    for (final node in nodes) {
      final thisAtStart = lineStart;
      lineStart = false; // anything after the first run is mid-line
      if (node is md.Text) {
        spans.addAll(_conventionSpans(node.text, base, atLineStart: thisAtStart));
      } else if (node is md.Element) {
        switch (node.tag) {
          case 'strong':
            spans.addAll(_inline(node.children ?? const [],
                base.copyWith(fontWeight: FontWeight.bold)));
            break;
          case 'em':
            spans.addAll(_inline(node.children ?? const [],
                base.copyWith(fontStyle: FontStyle.italic)));
            break;
          case 'del':
            spans.addAll(_inline(node.children ?? const [],
                base.copyWith(decoration: TextDecoration.lineThrough)));
            break;
          case 'code':
            spans.add(TextSpan(
              text: node.textContent,
              style: base.copyWith(
                fontFamily: 'monospace',
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ));
            break;
          case 'a':
            // Styled, not tappable. Story 3.2 (FR19) made [[wikilinks]]
            // tap-navigable (see `_wikilinkRecognizer` below) but did not
            // extend that to markdown `[label](url)` links — this remains
            // display-only.
            spans.addAll(_inline(
              node.children ?? const [],
              base.copyWith(
                color: scheme.primary,
                decoration: TextDecoration.underline,
              ),
            ));
            break;
          case 'br':
            spans.add(const TextSpan(text: '\n'));
            break;
          case 'input':
            // GFM task-list checkbox — render a glyph so the item isn't lost.
            final checked = node.attributes['checked'] == 'true';
            spans.add(TextSpan(text: checked ? '☑ ' : '☐ ', style: base));
            break;
          case 'img':
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _image(node.attributes['src'], node.attributes['alt'], base),
            ));
            break;
          default:
            spans.addAll(_inline(node.children ?? const [], base));
        }
      }
    }
    return spans;
  }

  /// Styles a plain markdown text run for this project's conventions by reusing
  /// the shared matcher (AD-7). Markdown already rendered the structural markup
  /// (heading/bold/italic/list), so only the conventions it leaves as literal
  /// text — `[[wikilinks]]`, `[placeholders]`, em-dash, `Name (emotion):`, and
  /// the flagged FR9a error kinds — are styled here. The line-anchored dialogue
  /// speaker is applied only when [atLineStart] (a block's first run), so a
  /// mid-line `… intro:` after inline markup isn't mistaken for a speaker.
  List<InlineSpan> _conventionSpans(String text, TextStyle base,
      {required bool atLineStart}) {
    final tokens = matchConventions(text);
    return buildConventionSpans(
      text,
      tokens,
      base: base,
      apply: atLineStart
          ? previewLineStartConventionKinds
          : previewConventionKinds,
      styleFor: (kind) => styleForConvention(kind, scheme, base),
      recognizerFor: _wikilinkRecognizer,
    );
  }

  /// Story 3.2 (AC6) — only `wikilink` gets a tap recognizer; `sceneLink` (a
  /// separator-bearing `[[a->b]]` pair, disjoint from `wikilink` by the
  /// matcher's own precedence — see `convention_matcher.dart`) is never
  /// tappable here. Returns null (no recognizer) when there's no callback to
  /// invoke, so a bare `MarkdownPreview` stays exactly as inert as before.
  GestureRecognizer? _wikilinkRecognizer(ConventionKind kind, String matchedText) {
    final onTap = onWikilinkTap;
    if (kind != ConventionKind.wikilink || onTap == null) return null;
    final title = matchedText.substring(2, matchedText.length - 2);
    final recognizer = TapGestureRecognizer()..onTap = () => onTap(title);
    registerRecognizer(recognizer);
    return recognizer;
  }

  /// Renders an `img` node: a local-relative `src` loads via [_RepoImage]
  /// (Story 2.16); anything else (missing src, an `http(s)://` URL, or no
  /// `storage`/`filePath` context) falls back to the alt-text placeholder,
  /// unchanged from Story 2.7.
  Widget _image(String? src, String? alt, TextStyle base) {
    final label = (alt != null && alt.isNotEmpty) ? alt : (src ?? 'image');
    final placeholder = _imagePlaceholder(label, base, scheme);
    final resolved = _resolveImage(src);
    if (resolved == null) return placeholder;
    return _RepoImage(
      storage: resolved.storage,
      path: resolved.path,
      placeholder: placeholder,
    );
  }

  /// Resolves [src] to a `(storage, repo-relative path)` pair to load, or
  /// `null` when the caller should fall back to the alt-text placeholder
  /// without attempting any read:
  /// - `src` is null/empty.
  /// - `src` is an `http://`/`https://` URL — **never fetched**, this app is
  ///   offline-first except for the user-configured AI provider (NFR4/NFR5).
  /// - [storage]/[filePath] is null — no file context to resolve against
  ///   (Story 2.7's original behavior for a bare `MarkdownPreview(text: ...)`).
  ///
  /// A local `src` is resolved against [filePath]'s directory with genuine
  /// `.`/`..` segment handling (`..` pops the preceding directory segment) —
  /// this matters for real usage: `media/` lives at the **entity root** and is
  /// referenced by both the card and its sub-entries (ARCHITECTURE.md), so a
  /// sub-entry two folders deep (e.g. `characters/selena/events/x.md`) needs
  /// `../media/y.png` to reach it. `RepoStorage`'s own path normalization
  /// (`AllFilesRepoStorage._normalizeRepoPath`) only *drops* `..` segments
  /// (an anti-escape measure, not a resolver), which would silently break that
  /// case — so resolution happens here, not by relying on the port. An
  /// excess `..` (more than [filePath]'s depth) simply stops popping once the
  /// segment list is empty, rather than escaping upward — still safe, still
  /// total.
  ({RepoStorage storage, String path})? _resolveImage(String? src) {
    if (src == null || src.isEmpty) return null;
    final lower = src.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return null;
    }
    final st = storage;
    final fp = filePath;
    if (st == null || fp == null) return null;
    final normalizedSrc = src.replaceAll('\\', '/');
    final lastSlash = fp.lastIndexOf('/');
    final dir = lastSlash == -1 ? '' : fp.substring(0, lastSlash);
    final segments = dir.isEmpty ? <String>[] : dir.split('/');
    for (final seg in normalizedSrc.split('/')) {
      if (seg.isEmpty || seg == '.') {
        continue;
      } else if (seg == '..') {
        if (segments.isNotEmpty) segments.removeLast();
      } else {
        segments.add(seg);
      }
    }
    return (storage: st, path: segments.join('/'));
  }
}

/// The alt-text-with-icon placeholder shown when an image isn't loaded — by
/// choice ([_MarkdownRenderer._resolveImage] declined to try) or by failure
/// ([_RepoImage] tried and it didn't work out). One look, every failure mode.
Widget _imagePlaceholder(String label, TextStyle base, ColorScheme scheme) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_outlined, size: (base.fontSize ?? 14) + 2, color: scheme.outline),
        const SizedBox(width: 4),
        Text(label, style: base.copyWith(fontStyle: FontStyle.italic, color: scheme.outline)),
      ],
    ),
  );
}

/// A defensive sanity cap on decoded image size — not a product requirement,
/// just a guard against a huge/corrupt file janking the preview at decode time
/// (Story 2.16). Note: [RepoStorage.readBytes] has no streaming/size-probe
/// primitive, so the full file is already read into memory *before* this
/// check runs — this cap bounds the `Image.memory` decode cost, not the
/// read's own memory spike. Closing that gap needs a new port capability
/// (e.g. a byte-length probe); deferred, see deferred-work.md.
const int _maxImageBytes = 15 * 1024 * 1024;

/// Caps the on-screen size of a loaded image so a full-resolution phone photo
/// can't blow out the inline text flow it's embedded in (a `WidgetSpan` has no
/// natural width constraint of its own to fall back on). `BoxFit.contain`
/// preserves aspect ratio within the cap.
const double _maxImageDisplaySize = 280;

/// Loads [path] from [storage] **once** (the future is created in [initState],
/// not on every rebuild) and renders it via [Image.memory], or [placeholder]
/// on any failure: a missing/unreadable file (`readBytes` throws), oversized
/// bytes (checked before attempting to decode), or bytes that don't decode as
/// an image (caught by [Image.memory]'s own `errorBuilder`). AD-8/NFR7: every
/// one of those failure modes converges on [placeholder] — none of them throw
/// past this widget, so one bad image can never blank the rest of the preview.
class _RepoImage extends StatefulWidget {
  final RepoStorage storage;
  final String path;
  final Widget placeholder;

  const _RepoImage({
    required this.storage,
    required this.path,
    required this.placeholder,
  });

  @override
  State<_RepoImage> createState() => _RepoImageState();
}

class _RepoImageState extends State<_RepoImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _readBytes();
  }

  @override
  void didUpdateWidget(covariant _RepoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different image node (e.g. the buffer changed under a live preview
    // toggle) needs a fresh read; re-fetching only on an actual change is what
    // keeps this from re-reading on every unrelated rebuild.
    if (oldWidget.storage != widget.storage || oldWidget.path != widget.path) {
      _future = _readBytes();
    }
  }

  /// `Future.sync` guarantees no exception from [RepoStorage.readBytes] can
  /// ever escape synchronously to the caller (`initState`/`didUpdateWidget`),
  /// even from a hypothetical non-`async` implementation — the interface only
  /// promises a `Future<Uint8List>` return type, not that every implementer
  /// defers all failures into it. Total by construction, not by convention.
  Future<Uint8List> _readBytes() =>
      Future.sync(() => widget.storage.readBytes(widget.path));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // A small fixed-size box while loading avoids a layout jump once the
          // image (or the placeholder) arrives.
          return const SizedBox(width: 24, height: 24);
        }
        final bytes = snapshot.data;
        if (snapshot.hasError || bytes == null || bytes.length > _maxImageBytes) {
          return widget.placeholder;
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _maxImageDisplaySize,
            maxHeight: _maxImageDisplaySize,
          ),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => widget.placeholder,
          ),
        );
      },
    );
  }
}
