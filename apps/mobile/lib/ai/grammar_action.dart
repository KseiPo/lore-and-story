import 'dart:convert';

import 'package:flutter/material.dart';

import '../storage/storage.dart';
import 'ai_client.dart';
import 'ai_prompt_config.dart';
import 'context_preview.dart';

/// How serious a [GrammarFinding] is — a closed set so the panel (Story 4.6,
/// `app/grammar_panel.dart`) can style each finding consistently (icon/label
/// per level). An AI-reported severity string that doesn't match one of
/// these three values falls back to [GrammarSeverity.moderate] rather than
/// discarding the finding (AD-8 — degrade, don't drop).
enum GrammarSeverity { minor, moderate, major }

/// One AI-reported grammar/style finding (FR23) — a line-addressable,
/// read-only observation the author can jump to, read, and act on manually.
/// Never applied to the buffer automatically (AC3).
///
/// An independent type from `lore/convention_lint.dart`'s `LintFinding`:
/// that one is offline/syntax-only and `ConventionKind`-keyed; this one is
/// AI-produced prose judgment with its own `issue`/`suggestion`/`severity`
/// shape. The two panels share the same jump-to-line interaction pattern
/// (AD-7 at the pattern level), but forcing this data through `LintFinding`
/// would pollute that offline-only type for a second, unrelated caller.
@immutable
class GrammarFinding {
  /// 1-indexed line number the finding applies to, as reported by the AI —
  /// not independently verified against the file's actual line count;
  /// `FileEditorState.jumpToLine` already clamps a wild value safely.
  final int line;

  final String issue;
  final String suggestion;
  final GrammarSeverity severity;

  const GrammarFinding({
    required this.line,
    required this.issue,
    required this.suggestion,
    required this.severity,
  });

  @override
  bool operator ==(Object other) =>
      other is GrammarFinding &&
      other.line == line &&
      other.issue == issue &&
      other.suggestion == suggestion &&
      other.severity == severity;

  @override
  int get hashCode => Object.hash(line, issue, suggestion, severity);

  @override
  String toString() => 'GrammarFinding(line $line, ${severity.name}: $issue)';
}

/// The fixed system-prompt instructions for the grammar/style review request
/// — independently authored from `translate_action.dart`'s constants (those
/// are translation-mechanics text, e.g. "translate the name," which doesn't
/// apply here). This is this file's own factual restatement of the same
/// project markup conventions, so the reviewer doesn't misflag intentional
/// project syntax as a prose error.
const String _kGrammarInstructions = '''
You are reviewing a scene or lore file for a visual-novel project, written in Russian or English (detect which), for grammar, spelling, and prose-quality/style issues. Preserve the author's own voice — suggest fixes, never rewrite the whole passage.

This project uses markup conventions that are intentional, not errors — never flag any of the following as a mistake:
- Dialogue lines: `Name (emotion): phrase.` (the emotion is optional).
- Inner monologue: `Мысль: …` in Russian and `Thought: …` in English.
- Variable placeholders in readable square brackets, e.g. `[имя героя]`.
- Lore wikilinks: `[[Title]]` with no separator.
- Scene/passage links: `[[Choice text->Passage Name]]`, `[[Choice text|Passage Name]]`, and return links `[[back<-Label]]`.
- Em-dash conditional markers: `— если … — иначе … — конец условия —`.
- A leading `<!-- scene ⇄ passage: "Passage Name" · lang: xx -->` comment.''';

/// The JSON response-format contract `_parseFindings` depends on — always
/// appended after [_kGrammarInstructions]/its `ai-prompts.md` override
/// (`AiPromptConfig.grammarInstructions`) and never itself overridable
/// (Review Decision 1, Story 4.6 code review). Splitting this out of the
/// overridable instructions means a well-intentioned `# Grammar
/// Instructions` override (tone/focus/emphasis) can only ever change what
/// the AI looks for, never break the response format the parser depends
/// on — previously an override replaced this paragraph too, and once an
/// author's override omitted it, the model would stop returning JSON and
/// every future review would fail with an opaque "could not parse" error
/// with nothing hinting the override was the cause. Shown as its own
/// preview section (AD-11) so the fixed/overridable split is visible, not
/// just silently enforced.
const String _kResponseFormatContract =
    'Respond with ONLY a strict JSON array, no markdown code fences, no '
    'commentary — one object per finding: {"line": <1-indexed integer>, '
    '"issue": "<string>", "suggestion": "<string>", "severity": "minor" | '
    '"moderate" | "major"}. If the file has no issues, respond with an '
    "empty array: []. Never rewrite or reproduce the file's content — "
    'report findings only.';

/// Upper bound on the response length for a review request. A findings list
/// is JSON, not prose, but `thinking: {type: 'adaptive'}`
/// (`messages_api_client.dart`) draws from the same token budget as the
/// visible response (the same factor `runTranslate`'s own `_kMaxTokens` doc
/// comment records raising its budget for) — a heavily-flagged long scene's
/// worth of reasoning plus JSON output can still exceed a budget sized only
/// for "a few dozen small JSON objects." Matches `runTranslate`'s 16384 for
/// the same reason, rather than assuming JSON-shaped output needs less
/// headroom than prose.
const int _kMaxTokens = 16384;

/// Runs the Story 4.6 grammar/style review flow (FR23): assembles the FR22
/// context pack (the fixed/overridable `AI instructions` plus the file's
/// [text] — no glossary, no direction, unlike `runTranslate`), shows
/// [showContextPreview], and on confirm sends the request via [aiClient],
/// parsing the response into a findings list.
///
/// Returns the parsed findings (possibly empty — a real, honest "no issues"
/// result) on success. Returns `null` if the author cancelled the preview
/// (nothing was sent), the request itself failed (network/auth/rate-limit/
/// server error), or the response could not be parsed as the expected JSON
/// shape at all — every `null`-returning path other than a plain cancel
/// already showed a `SnackBar`, so the caller has nothing further to report
/// (AD-8: never throws, never leaves the caller guessing).
Future<List<GrammarFinding>?> runGrammarReview(
  BuildContext context, {
  required RepoStorage storage,
  required AiClient aiClient,
  required String text,
}) async {
  // Story 4.4/4.6: an author-supplied `ai-prompts.md` (never throws — its own
  // contract) can override the instructions; left `null` falls back to this
  // file's own hardcoded default.
  final promptConfig = await resolveAiPromptConfig(storage);
  if (!context.mounted) return null;
  final instructionsText = promptConfig.grammarInstructions ?? _kGrammarInstructions;

  // AD-11: the sent `system` prompt is built ONLY by concatenating these
  // same section texts below (never any additional label/glue text) so
  // what's previewed is provably, byte-for-byte, what's sent. The response
  // format contract is a separate, always-appended section (Review
  // Decision 1) — never subject to the `ai-prompts.md` override above.
  final instructions = ContextSection(label: 'AI instructions', text: instructionsText);
  final responseFormat =
      ContextSection(label: 'Response format', text: _kResponseFormatContract);
  final file = ContextSection(label: 'The file', text: text);
  final sections = [instructions, responseFormat, file];

  final confirmed = await showContextPreview(context, sections: sections);
  if (!confirmed) return null;
  if (!context.mounted) return null;

  final request = AiRequest(
    system: [instructions.text, responseFormat.text].join('\n\n'),
    userContent: file.text,
    maxTokens: _kMaxTokens,
  );

  final String raw;
  try {
    final buffer = StringBuffer();
    await for (final chunk in aiClient.sendMessage(request)) {
      buffer.write(chunk);
    }
    raw = buffer.toString();
  } on AiClientException catch (e) {
    if (context.mounted) _showError(context, e.message);
    return null;
  } catch (_) {
    if (context.mounted) {
      _showError(context, 'Grammar review failed. Please try again.');
    }
    return null;
  }

  final findings = _parseFindings(raw);
  if (findings == null) {
    if (context.mounted) {
      _showError(context, "Could not parse the AI's response. Please try again.");
    }
    return null;
  }
  return findings;
}

/// Parses [raw] (the AI's buffered response) into a findings list. Returns
/// `null` on a total parse failure — the text (after stripping a possible
/// code fence) is not valid JSON, or is valid JSON but not a `List` — AC7's
/// "never crashes" guarantee turns that into a caught, reported failure
/// rather than an uncaught exception, never a silently-empty result.
///
/// Returns a (possibly empty) list otherwise; an individual list entry that
/// isn't a well-formed finding is skipped, not fatal to the whole parse
/// (mirrors `lintText`'s own best-effort, total collection philosophy —
/// `lore/convention_lint.dart`). Review fix: a non-empty decoded array whose
/// every entry fails per-entry validation is itself a parse failure
/// (`null`), not a false "no issues" — only a genuinely empty decoded array
/// is the real AC6 "no issues" result; otherwise the panel would silently
/// claim a clean review for a response it couldn't actually understand.
List<GrammarFinding>? _parseFindings(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_stripCodeFence(raw));
  } catch (_) {
    return null;
  }
  if (decoded is! List) return null;

  final findings = <GrammarFinding>[];
  for (final entry in decoded) {
    final finding = _parseFinding(entry);
    if (finding != null) findings.add(finding);
  }
  if (findings.isEmpty && decoded.isNotEmpty) return null;
  return findings;
}

/// Review fix: `suggestion` defaults to `''` rather than being hard-required
/// — a finding with a usable `line`+`issue` but no `suggestion` is degraded,
/// not dropped, matching the same "degrade, don't drop" contract
/// [_asSeverity]'s fallback already honors.
GrammarFinding? _parseFinding(Object? entry) {
  if (entry is! Map) return null;
  final line = _asInt(entry['line']);
  final issue = entry['issue'];
  if (line == null || issue is! String) return null;
  final suggestionRaw = entry['suggestion'];
  return GrammarFinding(
    line: line,
    issue: issue,
    suggestion: suggestionRaw is String ? suggestionRaw : '',
    severity: _asSeverity(entry['severity']),
  );
}

/// Accepts a JSON `int`, a numeric `String`, or a JSON `double` (Review
/// fix — `jsonDecode` yields a Dart `double` for any JSON number written
/// with a decimal point/exponent, e.g. `"line": 3.0`; rejecting that shape
/// dropped an otherwise-valid finding).
int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Falls back to [GrammarSeverity.moderate] for anything unrecognized —
/// missing, wrong type, or a string that isn't one of the three known
/// levels — matching Task 2.1's "degrade, don't drop" contract.
GrammarSeverity _asSeverity(Object? value) {
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'minor':
        return GrammarSeverity.minor;
      case 'moderate':
        return GrammarSeverity.moderate;
      case 'major':
        return GrammarSeverity.major;
    }
  }
  return GrammarSeverity.moderate;
}

/// Strips markdown code-fence markers and any leading/trailing prose some
/// models wrap JSON output in despite being told not to (cheap insurance,
/// not a structural requirement) — handles a fence on its own line, a
/// single-line fence with no newline after the opening backticks, and
/// prose before/after the array (e.g. "Here are the findings:\n[...]").
/// Review fix: rather than requiring one specific fence shape, strip every
/// ``` /```json marker wherever it appears, then extract the substring
/// from the first `[` to the last `]` — text with no brackets at all (a
/// genuinely non-JSON response) is returned unchanged so `jsonDecode`'s own
/// failure still reports a parse error.
String _stripCodeFence(String raw) {
  final stripped =
      raw.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '').trim();
  final start = stripped.indexOf('[');
  final end = stripped.lastIndexOf(']');
  if (start == -1 || end == -1 || end < start) return stripped;
  return stripped.substring(start, end + 1);
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
