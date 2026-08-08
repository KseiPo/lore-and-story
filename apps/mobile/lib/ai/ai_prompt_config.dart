import 'package:flutter/foundation.dart' show immutable;

import '../storage/storage.dart';

/// Repo-root filename holding the optional AI-prompt override (Story 4.4).
const String kAiPromptConfigFile = 'ai-prompts.md';

/// The pieces [AiPromptConfig] can hold — one per recognized `# ` heading.
/// An enum (not a `Map<String, String>` keyed by field name) so a typo in a
/// heading-to-field mapping is a compile error, not a silent "never
/// overridden" degradation (Review fix).
enum _Heading { instructions, conventions }

/// Heading text (trimmed, lowercased) → the piece it fills. An unrecognized
/// heading's body is parsed (consumed) but discarded — forward-compatible
/// with a future heading (e.g. Story 4.6's grammar instructions) without this
/// parser needing to change.
const Map<String, _Heading> _kKnownHeadings = {
  'translation instructions': _Heading.instructions,
  'conventions': _Heading.conventions,
};

/// Resolved override for the AI translation prompt's `AI instructions` and
/// `Conventions` pieces (`translate_action.dart`), read from [kAiPromptConfigFile].
///
/// Each field is `null` when not overridden — the caller (`runTranslate`)
/// applies its own hardcoded default in that case (`promptConfig.instructions
/// ?? _kInstructions`), the same "field absent → caller's own default" shape
/// `ProjectConfig` already uses for `lore-story.json`. Pure value type — no I/O.
@immutable
class AiPromptConfig {
  final String? instructions;
  final String? conventions;

  const AiPromptConfig({this.instructions, this.conventions});

  /// Config used when `ai-prompts.md` is missing, unreadable, or defines
  /// neither recognized section — both pieces fall back to their hardcoded
  /// defaults (FR29 / AD-8).
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
  /// [_kKnownHeadings]. A body that is empty after trimming is treated as
  /// *not overridden* (left `null`), not as "override with empty text" — an
  /// empty heading most plausibly signals an incomplete edit, and translating
  /// with genuinely empty instructions would silently degrade quality with no
  /// clear signal. A repeated heading: the last occurrence wins outright —
  /// including when that last occurrence is empty, which correctly clears an
  /// earlier non-empty override rather than leaving it in place (Review fix).
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
      String? instructions;
      String? conventions;

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
            case _Heading.instructions:
              instructions = value;
            case _Heading.conventions:
              conventions = value;
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

      return AiPromptConfig(instructions: instructions, conventions: conventions);
    } catch (_) {
      return empty;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AiPromptConfig &&
      other.instructions == instructions &&
      other.conventions == conventions;

  @override
  int get hashCode => Object.hash(instructions, conventions);

  @override
  String toString() => 'AiPromptConfig(instructions: '
      '${instructions == null ? 'default' : 'overridden'}, conventions: '
      '${conventions == null ? 'default' : 'overridden'})';
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
