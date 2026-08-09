import 'package:flutter/material.dart';

import '../lore/lore.dart';
import '../storage/storage.dart';
import 'ai_client.dart';
import 'ai_prompt_config.dart';
import 'ai_server_config.dart';
import 'context_preview.dart';

/// Which way a translate request runs (Story 4.5/FR30) — determines which of
/// [_kInstructionsRuToEn]/[_kInstructionsEnToRu] (or their `ai-prompts.md`
/// overrides) is sent, and which tab is the source vs. the target in
/// `PairedEditorPage`.
enum TranslationDirection { ruToEn, enToRu }

/// The fixed system-prompt preamble for the RU→EN direction — the part of
/// what's sent that is neither "the file," "the glossary," nor "the
/// conventions" (FR22's three literal sections). Shown as its own `AI
/// instructions` preview section so every byte of [AiRequest.system] is
/// represented by exactly one section (AD-11 — Story 4.2's own
/// deferred-work.md flagged this gap in advance; this closes it).
const String _kInstructionsRuToEn =
    'You are translating a Russian scene or lore file for a visual-novel '
    'project into natural, readable English prose for the same project. '
    'Preserve markdown structure (headings, lists, emphasis) and every '
    'non-prose marker exactly as written — translate only the human-readable '
    'prose text, never the markup syntax itself. Use the glossary below so '
    'every mention of a character or place is translated identically '
    'wherever it appears. Output only the translated file — no commentary, '
    'no preamble.';

/// The mirror of [_kInstructionsRuToEn] for the EN→RU direction (Story 4.5),
/// worded for translating INTO Russian.
const String _kInstructionsEnToRu =
    'You are translating an English scene or lore file for a visual-novel '
    'project into natural, readable Russian prose for the same project. '
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
///
/// Forked per direction (Story 4.5 review decision, 2026-08-08 — KseiPo:
/// "we might want to extract this constant to a configuration file and make
/// it language dependent, so better have one const for each language
/// direction for now"), reverting an earlier single-shared-constant attempt
/// that traded away RU→EN's byte-for-byte history (AC5) for a generic
/// wording. This constant is byte-for-byte identical to what Story 4.3/4.4
/// shipped. [_kConventionsEnToRu] is its EN→RU mirror. The `ai-prompts.md`
/// `# Conventions` override (`AiPromptConfig.conventions`) stays a single
/// shared field applied to whichever of these two is the direction's
/// default — only the hardcoded defaults are forked, not the override
/// scheme (see this story's Non-goals).
const String _kConventionsRuToEn = '''
- Dialogue lines are `Name (emotion): phrase.` — the emotion is optional. Keep this exact shape; translate only the name and the phrase.
- Inner monologue is `Мысль: …` in Russian and `Thought: …` in English — use the English form.
- Variable placeholders are readable square brackets, e.g. `[имя героя]` — translate the words inside the brackets, keep the bracket form, never emit `<<=\$var>>` or other code syntax.
- Player-choice / passage links: `[[Choice text->Passage Name]]` or `[[Choice text|Passage Name]]` — translate the choice text (the label before the separator); never translate or alter the Passage Name (the target after the separator) — it is an identifier, not prose.
- Return links: `[[back<-Label]]` — translate the Label only; the backlink form itself never changes.
- Em-dash conditional markers: `— если … — иначе … — конец условия —` — these delimit authoring conditionals, not prose to render; preserve the em-dash markers and translate only the human-readable text between them.
- `[[Title]]` with no separator is a lore-entity wikilink (not a passage jump) — translate Title to that entity's English form from the glossary when the glossary lists one; otherwise leave it unchanged rather than guessing.
- A file may open with a `<!-- scene ⇄ passage: "Passage Name" · lang: ru -->` comment — keep the passage name unchanged, but update `lang: ru` to `lang: en` in the translated output; if no such comment exists, do not add one.''';

/// The EN→RU mirror of [_kConventionsRuToEn] (Story 4.5).
const String _kConventionsEnToRu = '''
- Dialogue lines are `Name (emotion): phrase.` — the emotion is optional. Keep this exact shape; translate only the name and the phrase.
- Inner monologue is `Мысль: …` in Russian and `Thought: …` in English — use the Russian form.
- Variable placeholders are readable square brackets, e.g. `[имя героя]` — translate the words inside the brackets, keep the bracket form, never emit `<<=\$var>>` or other code syntax.
- Player-choice / passage links: `[[Choice text->Passage Name]]` or `[[Choice text|Passage Name]]` — translate the choice text (the label before the separator); never translate or alter the Passage Name (the target after the separator) — it is an identifier, not prose.
- Return links: `[[back<-Label]]` — translate the Label only; the backlink form itself never changes.
- Em-dash conditional markers: `— если … — иначе … — конец условия —` — these delimit authoring conditionals, not prose to render; preserve the em-dash markers and translate only the human-readable text between them.
- `[[Title]]` with no separator is a lore-entity wikilink (not a passage jump) — translate Title to that entity's Russian form from the glossary when the glossary lists one; otherwise leave it unchanged rather than guessing.
- A file may open with a `<!-- scene ⇄ passage: "Passage Name" · lang: en -->` comment — keep the passage name unchanged, but update `lang: en` to `lang: ru` in the translated output; if no such comment exists, do not add one.''';

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

/// Runs the Story 4.3/4.5 translate flow, in either [direction]: assembles
/// the FR22 context pack (this file, the alias glossary, the prose
/// conventions, and the direction-appropriate fixed instructions — four
/// sections, see [_kInstructionsRuToEn]/[_kInstructionsEnToRu]'s doc
/// comments), shows [showContextPreview], and on confirm streams a
/// translation via [aiClient].
///
/// [sourceText] is the buffer being translated FROM (the RU buffer for
/// [TranslationDirection.ruToEn], the EN buffer for
/// [TranslationDirection.enToRu]) — the caller (`PairedEditorPage`) decides
/// direction and resolves the correct source; this function is symmetric in
/// direction and does not itself know which tab is which.
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
  required String sourceText,
  required TranslationDirection direction,
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

  // Story 4.4/4.5: an author-supplied `ai-prompts.md` (never throws — Task 1's
  // own contract) can override any piece; a piece left `null` falls back to
  // this file's own hardcoded default. Which instructions/conventions
  // default is consulted depends on [direction] — the one place the
  // direction decision is made; everything downstream just reads
  // `instructionsText`/`conventionsText` (AD-11). The `# Conventions`
  // override itself stays a single shared field (`promptConfig.conventions`)
  // applied to whichever direction's default it's overriding — only the
  // hardcoded defaults are forked per direction, not the override scheme.
  final promptConfig = await resolveAiPromptConfig(storage);
  if (!context.mounted) return null;
  // Story 4.7: an author-configured `lore-story.json` `ai` object (never
  // throws — its own contract) can override the model/base URL a request
  // actually goes to; a piece left `null` falls back to `MessagesApiClient`'s
  // own hardcoded default (`AiRequest.model`/`.baseUrl`, both nullable).
  final serverConfig = await resolveAiServerConfig(storage);
  if (!context.mounted) return null;
  // Review fix (Story 4.7 code review): a config that signals intent to use
  // something other than plain Anthropic-direct but that this app can't
  // actually honor (an unusable `server`/`baseUrl` combination) must refuse
  // to send rather than silently falling back to Anthropic with whatever
  // key is saved — surfaced BEFORE the preview even opens, since there is
  // nothing valid to preview.
  final Uri? customOrigin;
  try {
    customOrigin = resolveCustomOrigin(serverConfig);
  } on AiConfigException catch (e) {
    if (context.mounted) _showError(context, e.message);
    return null;
  }
  final instructionsText = switch (direction) {
    TranslationDirection.ruToEn =>
      promptConfig.instructionsRuToEn ?? _kInstructionsRuToEn,
    TranslationDirection.enToRu =>
      promptConfig.instructionsEnToRu ?? _kInstructionsEnToRu,
  };
  final conventionsText = switch (direction) {
    TranslationDirection.ruToEn =>
      promptConfig.conventions ?? _kConventionsRuToEn,
    TranslationDirection.enToRu =>
      promptConfig.conventions ?? _kConventionsEnToRu,
  };

  // Review fix (AD-11): the sent `system` prompt is built ONLY by
  // concatenating these same section texts below (never any additional
  // label/glue text) so what's previewed is provably, byte-for-byte, what's
  // sent — not just similar to it.
  final instructions = ContextSection(
    label: 'AI instructions',
    text: instructionsText,
  );
  final file = ContextSection(label: 'The file', text: sourceText);
  final glossary = ContextSection(label: 'Glossary terms', text: glossaryText);
  final conventions = ContextSection(
    label: 'Conventions',
    text: conventionsText,
  );
  // Review fix (Story 4.7 code review Decision 1): AD-11 promises the
  // preview shows exactly what leaves the device — before this story the
  // destination was a hardcoded constant, but `lore-story.json` can now
  // redirect it, so the destination itself must be part of what's shown.
  // Appended last so every pre-Story-4.7 section keeps its existing index.
  final destination = ContextSection(
    label: 'Server',
    text: customOrigin?.toString() ?? kDefaultAnthropicEndpoint,
  );
  final sections = [instructions, file, glossary, conventions, destination];

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
    model: serverConfig.model,
    baseUrl: customOrigin,
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
