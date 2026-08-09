import 'package:flutter/foundation.dart' show immutable;

import '../storage/storage.dart';

/// Repo-root filename holding the optional AI-prompt override (Story 4.4).
const String kAiPromptConfigFile = 'ai-prompts.md';

/// The pieces [AiPromptConfig] can hold — one per recognized `# ` heading.
/// An enum (not a `Map<String, String>` keyed by field name) so a typo in a
/// heading-to-field mapping is a compile error, not a silent "never
/// overridden" degradation (Review fix, Story 4.4).
enum _Heading {
  instructionsRuToEn,
  instructionsEnToRu,
  conventions,
  grammarInstructions,
}

/// Heading text (trimmed, lowercased) → the piece it fills. An unrecognized
/// heading's body is parsed (consumed) but discarded — forward-compatible
/// with a heading this parser doesn't yet recognize (the scheme Story 4.6's
/// `# Grammar Instructions` heading itself was added under) without this
/// parser needing to change.
///
/// `'translation instructions'` (no direction suffix) is Story 4.4's original
/// heading and keeps meaning RU→EN unchanged, for backward compatibility
/// (Story 4.5 AC5) — `'translation instructions (ru→en)'`/`(ru->en)` are
/// accepted as explicit synonyms of it (Review fix: an author who notices the
/// new `(EN→RU)` heading naturally writes the symmetric form for the other
/// direction; without this, that heading was silently discarded). The EN→RU
/// heading is recognized in two spellings — the canonical arrow form and an
/// ASCII-typable alias — so an author whose keyboard/locale can't easily
/// produce `→` isn't silently locked out (Story 4.5 Task 1.3).
///
/// `'grammar instructions'` (Story 4.6) is a fourth, independent heading for
/// the grammar/style review feature (`grammar_action.dart`) — no
/// arrow/direction variants needed, since grammar review isn't directional
/// the way translation is.
const Map<String, _Heading> _kKnownHeadings = {
  'translation instructions': _Heading.instructionsRuToEn,
  'translation instructions (ru→en)': _Heading.instructionsRuToEn,
  'translation instructions (ru->en)': _Heading.instructionsRuToEn,
  'translation instructions (en→ru)': _Heading.instructionsEnToRu,
  'translation instructions (en->ru)': _Heading.instructionsEnToRu,
  'conventions': _Heading.conventions,
  'grammar instructions': _Heading.grammarInstructions,
};

/// Resolved override for the AI translation prompt's `AI instructions`
/// (RU→EN and EN→RU independently, Story 4.5/FR30) and `Conventions` pieces
/// (`translate_action.dart`), plus the grammar/style review's own
/// instructions (Story 4.6, `grammar_action.dart`), read from
/// [kAiPromptConfigFile]. Conventions are not direction-specific — the same
/// text applies either direction. Grammar instructions are independent of
/// both translation directions and of Conventions.
///
/// Each field is `null` when not overridden — the caller (`runTranslate` /
/// `runGrammarReview`) applies its own hardcoded default in that case (e.g.
/// `promptConfig.instructionsRuToEn ?? _kInstructionsRuToEn`), the same
/// "field absent → caller's own default" shape `ProjectConfig` already uses
/// for `lore-story.json`. Pure value type — no I/O.
@immutable
class AiPromptConfig {
  final String? instructionsRuToEn;
  final String? instructionsEnToRu;
  final String? conventions;
  final String? grammarInstructions;

  const AiPromptConfig({
    this.instructionsRuToEn,
    this.instructionsEnToRu,
    this.conventions,
    this.grammarInstructions,
  });

  /// Config used when `ai-prompts.md` is missing, unreadable, or defines
  /// none of the recognized sections — every piece falls back to its
  /// hardcoded default (FR29 / AD-8).
  static const AiPromptConfig empty = AiPromptConfig();

  /// Parses raw `ai-prompts.md` text, best-effort. **Never throws**: any
  /// failure or unexpected shape falls back to [empty] for the affected
  /// piece(s) (FR29 / AD-8), mirroring `ProjectConfig.parse`'s own contract
  /// (`lore/project_config.dart`).
  ///
  /// Sections are delimited by a top-level (`# `, exactly one `#` then a
  /// space) markdown heading; a `##`/`###` heading is part of its enclosing
  /// section's body, not a new section. Any text before the first recognized
  /// top-level heading is discarded (there is nowhere for it to go). A
  /// section's body is everything up to the next top-level heading or EOF,
  /// trimmed of leading/trailing whitespace — otherwise verbatim (not further
  /// parsed). Heading text is matched trimmed and case-insensitively against
  /// [_kKnownHeadings] — four recognized headings: `# Translation
  /// Instructions` (RU→EN, backward-compatible with Story 4.4), `# Translation
  /// Instructions (EN→RU)` (or the ASCII `(en->ru)` spelling), `# Conventions`
  /// (shared by both directions), and `# Grammar Instructions` (Story 4.6,
  /// independent of the other three). A body that is empty after
  /// trimming is treated as *not overridden* (left `null`), not as "override
  /// with empty text" — an empty heading most plausibly signals an incomplete
  /// edit, and translating with genuinely empty instructions would silently
  /// degrade quality with no clear signal. A repeated heading: the last
  /// occurrence wins outright — including when that last occurrence is empty,
  /// which correctly clears an earlier non-empty override rather than leaving
  /// it in place (Review fix, Story 4.4).
  factory AiPromptConfig.parse(String raw) {
    // The entire body is guarded by a catch-all (not just specific exception
    // types), mirroring `ProjectConfig.parse`'s own reasoning: an `Error`
    // subtype is not caught by an `Exception`-typed clause, and this factory
    // must never throw regardless of what a malformed file produces.
    try {
      // Strip a single leading BOM before parsing — Windows editors/PowerShell
      // write one (see `ProjectConfig.parse`'s identical guard).
      final cleaned = raw.startsWith('\u{FEFF}') ? raw.substring(1) : raw;

      _Heading? currentHeading;
      final buffer = StringBuffer();
      String? instructionsRuToEn;
      String? instructionsEnToRu;
      String? conventions;
      String? grammarInstructions;

      // Review fix: an unconditional assignment (not "write only if
      // non-empty") — this is what makes a later, empty occurrence of a
      // heading correctly erase an earlier non-empty one, matching "last
      // occurrence wins" literally rather than "last non-empty occurrence
      // wins."
      void flush() {
        if (currentHeading != null) {
          final body = buffer.toString().trim();
          final value = body.isEmpty ? null : body;
          switch (currentHeading) {
            case _Heading.instructionsRuToEn:
              instructionsRuToEn = value;
            case _Heading.instructionsEnToRu:
              instructionsEnToRu = value;
            case _Heading.conventions:
              conventions = value;
            case _Heading.grammarInstructions:
              grammarInstructions = value;
          }
        }
        buffer.clear();
      }

      for (final rawLine in cleaned.split('\n')) {
        // CRLF-safe: strip a trailing \r so it never ends up embedded mid-body
        // on a Windows-authored file, and never affects the heading check.
        final line = rawLine.endsWith('\r')
            ? rawLine.substring(0, rawLine.length - 1)
            : rawLine;
        if (line.startsWith('# ')) {
          flush();
          currentHeading = _kKnownHeadings[line.substring(2).trim().toLowerCase()];
        } else if (currentHeading != null) {
          buffer.writeln(line);
        }
      }
      flush();

      return AiPromptConfig(
        instructionsRuToEn: instructionsRuToEn,
        instructionsEnToRu: instructionsEnToRu,
        conventions: conventions,
        grammarInstructions: grammarInstructions,
      );
    } catch (_) {
      return empty;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AiPromptConfig &&
      other.instructionsRuToEn == instructionsRuToEn &&
      other.instructionsEnToRu == instructionsEnToRu &&
      other.conventions == conventions &&
      other.grammarInstructions == grammarInstructions;

  @override
  int get hashCode => Object.hash(
        instructionsRuToEn,
        instructionsEnToRu,
        conventions,
        grammarInstructions,
      );

  @override
  String toString() => 'AiPromptConfig(instructionsRuToEn: '
      '${instructionsRuToEn == null ? 'default' : 'overridden'}, '
      'instructionsEnToRu: '
      '${instructionsEnToRu == null ? 'default' : 'overridden'}, '
      'conventions: ${conventions == null ? 'default' : 'overridden'}, '
      'grammarInstructions: '
      '${grammarInstructions == null ? 'default' : 'overridden'})';
}

/// Reads and resolves [kAiPromptConfigFile] from the repo root via [storage].
///
/// A missing file, read error, or invalid content resolves to
/// [AiPromptConfig.empty] — this **never throws and never blocks** (FR29 /
/// AD-8), mirroring `resolveProjectConfig` (`lore/project_config.dart`).
/// Re-read on every call (no caching), so an edited file takes effect on the
/// very next translate.
Future<AiPromptConfig> resolveAiPromptConfig(RepoStorage storage) async {
  try {
    final raw = await storage.read(kAiPromptConfigFile);
    return AiPromptConfig.parse(raw);
  } catch (_) {
    // Missing file, I/O error, or any other read failure → empty. A
    // catch-all (not just `on RepoStorageException`) so a storage
    // implementation that surfaces a different failure type still can't
    // break FR29's "never blocks" guarantee.
    return AiPromptConfig.empty;
  }
}
