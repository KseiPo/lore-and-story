import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../lore/lore.dart';
import 'convention_styles.dart';

/// A read-only rendered view of markdown [text] (FR10).
///
/// Standalone by design: it takes only the markdown string, so the editor's
/// preview toggle (Story 2.7) and the detail-card preview (Story 2.13) both use
/// it, and Story 2.16 can *extend* it (adding `storage`/`filePath` for image
/// loading) without restructuring. It never edits — this is a distinct render
/// mode, not a WYSIWYG surface.
///
/// **Total (AD-8 / NFR7):** parsing/building is wrapped so a malformed document
/// can never throw — it degrades to a plain-text rendering of the raw buffer.
///
/// The parser runs with `encodeHtml: false` so raw text (including this
/// project's `[[wikilinks]]`, `Name (emotion):`, and leaked `<<twee>>`/`<html>`)
/// survives into text nodes verbatim — that is what lets the convention styling
/// (see `_conventionSpans`) flag it, and what keeps the display free of
/// `&lt;`-style HTML entities.
class MarkdownPreview extends StatelessWidget {
  final String text;

  const MarkdownPreview({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    Widget child;
    try {
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      );
      final nodes = document.parseLines(const LineSplitter().convert(text));
      final blocks = _MarkdownRenderer(context).blocks(nodes);
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks.isEmpty ? const [SizedBox.shrink()] : blocks,
      );
    } catch (_) {
      // Never an error screen: show the raw buffer best-effort.
      child = SelectableText(text);
    }
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
  late final ThemeData theme = Theme.of(context);
  late final TextTheme textTheme = theme.textTheme;
  late final ColorScheme scheme = theme.colorScheme;

  _MarkdownRenderer(this.context);

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
            // Styled, not tappable in v0.1 (navigation is Story 3.2 / FR19).
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
    );
  }

  /// Image placeholder for this story: alt text with a small icon. Story 2.16
  /// replaces this with a real load via `RepoStorage.readBytes`.
  Widget _image(String? src, String? alt, TextStyle base) {
    final label = (alt != null && alt.isNotEmpty) ? alt : (src ?? 'image');
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
}
