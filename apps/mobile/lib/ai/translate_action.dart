import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'ai_client.dart';
import 'context_preview.dart';

/// The fixed system-prompt preamble — the part of what's sent that is neither
/// "the file," "the glossary," nor "the conventions" (FR22's three literal
/// sections). Shown as its own `AI instructions` preview section so every byte
/// of [AiRequest.system] is represented by exactly one section (AD-11 — Story
/// 4.2's own deferred-work.md flagged this gap in advance; this closes it).
const String _kInstructions =
    'You are translating a Russian scene or lore file for a visual-novel '
    'project into natural, readable English prose for the same project. '
    'Preserve markdown structure (headings, lists, emphasis) and every '
    'non-prose marker exactly as written — translate only the human-readable '
    'prose text, never the markup syntax itself. Use the glossary below so '
    'every mention of a character or place is translated identically '
    'wherever it appears. Output only the translated file — no commentary, '
    'no preamble.';

/// Transcribes the operative rules from `ARCHITECTURE.md` §3.3 (this app does
/// not ship that document, so this is the app's own AI-ready copy — Story
/// 4.3's design decision 5, kept private/inline until a second consumer, e.g.
/// Story 4.4's grammar review, needs the identical text).
const String _kConventions = '''
- Dialogue lines are `Name (emotion): phrase.` — the emotion is optional. Keep this exact shape; translate only the name and the phrase.
- Inner monologue is `Мысль: …` in Russian and `*Thought:* …` in English — use the English form.
- Variable placeholders are readable square brackets, e.g. `[имя героя]` — translate the words inside the brackets, keep the bracket form, never emit `<<=\$var>>` or other code syntax.
- Player-choice / passage links: `[[Choice text->Passage Name]]` or `[[Choice text|Passage Name]]` — translate the choice text (the label before the separator); never translate or alter the Passage Name (the target after the separator) — it is an identifier, not prose.
- Return links: `[[back<-Label]]` — translate the Label only; the backlink form itself never changes.
- Em-dash conditional markers: `— если … — иначе … — конец условия —` — these delimit authoring conditionals, not prose to render; preserve the em-dash markers and translate only the human-readable text between them.
- `[[Title]]` with no separator is a lore-entity wikilink (not a passage jump) — translate Title to that entity's English form from the glossary when the glossary lists one; otherwise leave it unchanged rather than guessing.''';

/// Runs the Story 4.3 RU→EN translate flow: assembles the FR22 context pack
/// (this file, the alias glossary, the prose conventions, and the fixed
/// instructions — four sections, see [_kInstructions]'s doc comment), shows
/// [showContextPreview], and on confirm streams a translation via [aiClient].
///
/// Returns the translated text on success. Returns `null` if the author
/// cancelled the preview (nothing was sent) or if anything failed along the
/// way — a failure already showed a `SnackBar`, so the caller has nothing
/// further to report (AD-8: never throws, never leaves the caller guessing).
Future<String?> runTranslate(
  BuildContext context, {
  required RepoStorage storage,
  required String loreDir,
  required AiClient aiClient,
  required String ruText,
}) async {
  final String glossaryText;
  try {
    final model = await loadLore(storage, loreDir);
    glossaryText = model.entries.map((e) => e.aliases.join(', ')).join('\n');
  } catch (_) {
    if (context.mounted) {
      _showError(context, 'Could not build the translation glossary.');
    }
    return null;
  }
  if (!context.mounted) return null;

  final sections = [
    const ContextSection(label: 'AI instructions', text: _kInstructions),
    ContextSection(label: 'The file', text: ruText),
    ContextSection(label: 'Glossary terms', text: glossaryText),
    const ContextSection(label: 'Conventions', text: _kConventions),
  ];

  final confirmed = await showContextPreview(context, sections: sections);
  if (!confirmed) return null;
  if (!context.mounted) return null;

  final systemPrompt =
      '$_kInstructions\n\nProse conventions to preserve:\n$_kConventions\n\n'
      'Glossary — name variants (keep every mention of an entity consistent '
      'with one of its listed forms):\n$glossaryText';
  final request = AiRequest(system: systemPrompt, userContent: ruText);

  try {
    final buffer = StringBuffer();
    await for (final chunk in aiClient.sendMessage(request)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  } on AiClientException catch (e) {
    if (context.mounted) _showError(context, e.message);
    return null;
  } catch (_) {
    if (context.mounted) {
      _showError(context, 'Translation failed. Please try again.');
    }
    return null;
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
