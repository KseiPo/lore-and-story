import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'ai_client.dart';
import 'ai_prompt_config.dart';
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
/// Story 4.6's grammar review, needs the identical text).
const String _kConventions = '''
- Dialogue lines are `Name (emotion): phrase.` — the emotion is optional. Keep this exact shape; translate only the name and the phrase.
- Inner monologue is `Мысль: …` in Russian and `Thought: …` in English — use the English form.
- Variable placeholders are readable square brackets, e.g. `[имя героя]` — translate the words inside the brackets, keep the bracket form, never emit `<<=\$var>>` or other code syntax.
- Player-choice / passage links: `[[Choice text->Passage Name]]` or `[[Choice text|Passage Name]]` — translate the choice text (the label before the separator); never translate or alter the Passage Name (the target after the separator) — it is an identifier, not prose.
- Return links: `[[back<-Label]]` — translate the Label only; the backlink form itself never changes.
- Em-dash conditional markers: `— если … — иначе … — конец условия —` — these delimit authoring conditionals, not prose to render; preserve the em-dash markers and translate only the human-readable text between them.
- `[[Title]]` with no separator is a lore-entity wikilink (not a passage jump) — translate Title to that entity's English form from the glossary when the glossary lists one; otherwise leave it unchanged rather than guessing.
- A file may open with a `<!-- scene ⇄ passage: "Passage Name" · lang: ru -->` comment — keep the passage name unchanged, but update `lang: ru` to `lang: en` in the translated output; if no such comment exists, do not add one.''';

/// Review fix: a full scene plus glossary and conventions is a few thousand
/// input tokens (MOBILE.md §6.4), but the translated *output* of a full
/// scene can run to several thousand tokens on its own, and
/// `thinking: {type: 'adaptive'}` (`messages_api_client.dart`) draws from the
/// same budget as the visible response — the port's own 8192 default leaves
/// too little headroom for "a full scene translation is genuinely long
/// output" (Design decision 6). Doubled: still bounded, comfortably covers a
/// full scene.
const int _kMaxTokens = 16384;

/// Placeholder shown (and sent) for the `Glossary terms` section when the
/// project genuinely has no other lore entries — `loadLore` degrades an
/// empty/unreadable `loreDir` to zero entries rather than throwing (AD-8), so
/// an empty glossary is a real, silent outcome that must still be shown
/// honestly (Review fix) rather than sent as a blank, easy-to-miss section.
const String _kNoGlossaryPlaceholder =
    '(no other lore entries found in this project)';

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
    glossaryText = model.entries.isEmpty
        ? _kNoGlossaryPlaceholder
        : model.entries.map((e) => e.aliases.join(', ')).join('\n');
  } catch (_) {
    if (context.mounted) {
      _showError(context, 'Could not build the translation glossary.');
    }
    return null;
  }
  if (!context.mounted) return null;

  // Story 4.4: an author-supplied `ai-prompts.md` (never throws — Task 1's
  // own contract) can override either piece; a piece left `null` falls back
  // to this file's own hardcoded default, unchanged from Story 4.3.
  final promptConfig = await resolveAiPromptConfig(storage);
  if (!context.mounted) return null;
  final instructionsText = promptConfig.instructions ?? _kInstructions;
  final conventionsText = promptConfig.conventions ?? _kConventions;

  // Review fix (AD-11): the sent `system` prompt is built ONLY by
  // concatenating these same section texts below (never any additional
  // label/glue text) so what's previewed is provably, byte-for-byte, what's
  // sent — not just similar to it.
  final instructions = ContextSection(
    label: 'AI instructions',
    text: instructionsText,
  );
  final file = ContextSection(label: 'The file', text: ruText);
  final glossary = ContextSection(label: 'Glossary terms', text: glossaryText);
  final conventions = ContextSection(
    label: 'Conventions',
    text: conventionsText,
  );
  final sections = [instructions, file, glossary, conventions];

  final confirmed = await showContextPreview(context, sections: sections);
  if (!confirmed) return null;
  if (!context.mounted) return null;

  final systemPrompt = [
    instructions.text,
    glossary.text,
    conventions.text,
  ].join('\n\n');
  final request = AiRequest(
    system: systemPrompt,
    userContent: file.text,
    maxTokens: _kMaxTokens,
  );

  try {
    final buffer = StringBuffer();
    await for (final chunk in aiClient.sendMessage(request)) {
      buffer.write(chunk);
    }
    final translated = buffer.toString();
    // Review fix: a stream that yields nothing (or only whitespace) is a
    // real, silent failure shape — never treat it as a successful, if empty,
    // translation (AD-8 — never lie by omission, mirroring Story 4.2's own
    // "an empty list is a real state to show" precedent).
    if (translated.trim().isEmpty) {
      if (context.mounted) {
        _showError(
          context,
          'The AI returned an empty translation. Please try again.',
        );
      }
      return null;
    }
    return translated;
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
