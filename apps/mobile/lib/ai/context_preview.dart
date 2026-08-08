import 'package:flutter/material.dart';

/// One labeled block of text shown by [showContextPreview] — e.g. "The file",
/// "Glossary terms", "Conventions" for a translation request (Story 4.3), or
/// whatever a grammar-review request (Story 4.4) needs. Deliberately generic:
/// no field is named after any specific feature's payload, so this type never
/// needs to change as new AI actions are added.
@immutable
class ContextSection {
  final String label;
  final String text;

  const ContextSection({required this.label, required this.text});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContextSection && other.label == label && other.text == text);

  @override
  int get hashCode => Object.hash(label, text);
}

/// Shows exactly what would be sent to an AI provider and gates sending
/// behind explicit confirmation (FR22 / AD-11 — "nothing is sent until the
/// user confirms a context-preview showing exactly what leaves the device").
///
/// Every [sections] entry is rendered in full, verbatim — never truncated or
/// summarized, so "exactly what will leave the device" is literally true.
/// Resolves `true` only on an explicit Confirm tap; **every** other way of
/// leaving the sheet (Cancel, the system back gesture, tapping outside the
/// sheet) resolves `false`. `showModalBottomSheet`'s own barrier/back dismiss
/// pops with no result (`null`), not `false` — normalized here so callers
/// never have to handle a third, ambiguous outcome. An empty [sections] list
/// disables Confirm entirely — there is nothing to consent to sending.
///
/// Lives in `ai/`, not `app/` (where this codebase's other dialogs/sheets —
/// e.g. `lint_panel.dart` — otherwise live): `ARCHITECTURE-SPINE.md`'s
/// slice-ownership table names "context-preview... UI" as part of `ai/`'s
/// own ownership, not a general-purpose `app/` concern.
///
/// This function assembles nothing and sends nothing itself — it has no
/// dependency on `AiClient` or the network. The caller assembles [sections]
/// and, on a `true` result, is responsible for actually sending.
Future<bool> showContextPreview(
  BuildContext context, {
  required List<ContextSection> sections,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ContextPreviewSheet(sections: List.unmodifiable(sections)),
  );
  return result ?? false;
}

class _ContextPreviewSheet extends StatelessWidget {
  final List<ContextSection> sections;

  const _ContextPreviewSheet({required this.sections});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will be sent', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Flexible(child: _buildBody(context)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('context-preview-cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('context-preview-confirm'),
                  // Nothing to consent to sending when there's nothing to
                  // preview (AC5) — disabled, not just discouraged.
                  onPressed: sections.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // AD-8: an empty list is a real, honest state to show — never a blank
    // sheet that looks broken.
    if (sections.isEmpty) {
      return const Padding(
        key: Key('context-preview-empty'),
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Nothing to preview.')),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: sections.length,
      itemBuilder: (context, i) => Padding(
        key: Key('context-preview-section-$i'),
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sections[i].label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            // SelectableText, not Text — the author can genuinely
            // inspect (and copy) exactly what's about to be sent, not
            // just glance at it.
            SelectableText(sections[i].text),
          ],
        ),
      ),
    );
  }
}
