# Story 4.4: Customize the AI translation prompt

Status: ready-for-dev

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to override the AI translation instructions and conventions from a file in my synced repo,
so that I can tune how the AI translates without waiting for an app update.

## Context

**FR29, and the epics.md ACs for this story:**
> Let the author override the AI instructions/conventions text an AI action sends from a plain file in the synced repo (`ai-prompts.md` at the repo root) instead of the app's hardcoded defaults — per-section (an author may override only one piece), never blocking when the file is absent, unreadable, or defines neither recognized section.
>
> Given a file named `ai-prompts.md` at the repo root with a `# Translation Instructions` section, When I request a translation, Then that section's text replaces the app's hardcoded instructions in both the context preview and the request actually sent. Given `ai-prompts.md` has a `# Conventions` section, When I request a translation, Then that section's text replaces the app's hardcoded conventions the same way. Given `ai-prompts.md` is missing, unreadable, or defines neither recognized section, When I request a translation, Then today's hardcoded defaults are used unchanged. Given `ai-prompts.md` defines only one of the two sections, When I request a translation, Then only that piece is overridden — the other still falls back to its hardcoded default.

**Why this exists.** Story 4.3 hardcoded the `AI instructions` and `Conventions` preview sections as two private `const String` values in `translate_action.dart`. Real prompt-engineering work — matching this project's own conventions as they evolve, or just improving translation quality — currently requires an app code change and a rebuild. This story makes both pieces optionally overridable from a plain file in the synced repo.

**Why a repo file, not an in-app settings page (KseiPo's explicit decision, 2026-08-08):** this project's own stated philosophy treats files as the single source of truth (`project-context.md`); the file syncs automatically via Syncthing across every device without any new sync mechanism; and a multi-paragraph prompt is uncomfortable to hand-edit on a phone keyboard compared to a real desktop text editor. The tradeoff, accepted explicitly: the raw-file picker was retired in Story 2.12, so there is currently no in-app way to open or edit this file — it is edited entirely outside the app, on the synced repo, with any text editor. (See this story's own Non-goals: no in-app editor is in scope.)

**Why *before* Story 4.5 (grammar findings), not after (KseiPo's explicit decision):** once grammar review exists, it will want its own instructions text and likely share the same conventions text translation uses (both operate over the same kind of file). Building the override mechanism now, while there is exactly one consumer, lets Story 4.5 add a `# Grammar Instructions` section to the same file/parser without any redesign — avoiding hardcode-then-refactor a second time.

**Design decision 1 — new file, not new keys in `lore-story.json`.** `lore-story.json` (`ARCHITECTURE.md` §3.4, `apps/mobile/lib/lore/project_config.dart`) is JSON — fine for short scalar/array config (`loreDir`, `codeDirs`, …) but hostile to multi-paragraph prose (JSON string escaping of embedded quotes, newlines, and markdown punctuation is exactly the friction this story exists to remove). A new plain-markdown file, `ai-prompts.md` at the repo root, sidesteps that entirely — the author writes normal markdown, no escaping.

**Design decision 2 — a single file with named `# ` (H1) sections, not one file per piece.** Mirrors `lore-story.json`'s own "one config file, several named pieces, unknown/missing pieces ignored (forward-compatible)" shape (`project_config.dart`'s own doc comment: "Other `lore-story.json` keys … are ignored here"). One file is simpler for the author to find/edit than several conventionally-named files, and it composes cleanly with Story 4.5 adding a third heading later. Section keys for this story: `# Translation Instructions` and `# Conventions` (heading text matched trimmed + case-insensitively; body is everything up to the next `# `-level heading or EOF, verbatim, no further parsing — a `##`/`###` heading inside a section's own body is part of that section's content, not a new top-level section).

**Design decision 3 — an empty section body is treated as "not overridden," not as "override with empty text."** A `# Conventions` heading with nothing under it (before the next `# ` heading or EOF) most plausibly signals an incomplete edit, not a deliberate "send no conventions at all" — and translating with a genuinely empty instructions/conventions section would silently degrade quality with no clear signal to the author. Falling back to the hardcoded default in that case is always safe, and the gap between "what I meant to write" and "what's actually used" is visible in the context preview (it shows the hardcoded default text, not blank), where the author can notice and fix their file.

**Design decision 4 — parsing never throws, mirroring `ProjectConfig.parse` exactly** (same BOM-strip guard, same catch-all around any unexpected exception/`Error`, same "malformed input → default" resolution, same "re-read on every call, no caching" policy — an edited `ai-prompts.md` takes effect on the very next translate, matching `resolveProjectConfig`'s "next repo open" behavior). This is FR29's own "never blocks" requirement and AD-8.

**Non-goals (explicitly out of scope):** an in-app editor or viewer for `ai-prompts.md` (see "why a repo file" above); validating or linting the file's content beyond section-boundary parsing; any change to Story 4.3's confirm gate, the 4-section context-preview shape, `AiRequest`'s fields, or the `AiClient` threading — this story only changes *where the instructions/conventions text comes from*, nothing about how it's shown or sent; a third `# Grammar Instructions` section (Story 4.5's job, once it exists, using the same parser/file this story builds); per-feature or per-file overrides (one global override per project, matching `lore-story.json`'s own per-*project*, not per-file, scope).

## Acceptance Criteria

1. **(FR29 — instructions override)** Given `ai-prompts.md` exists at the repo root with a `# Translation Instructions` section, when I request a translation, then that section's text — not the hardcoded default — appears in the `AI instructions` context-preview section and is what's actually sent in `AiRequest.system`.
2. **(FR29 — conventions override)** Given `ai-prompts.md` has a `# Conventions` section, when I request a translation, then that section's text — not the hardcoded default — appears in the `Conventions` context-preview section and is what's actually sent.
3. **(Never blocks — AD-8/FR2 precedent)** Given `ai-prompts.md` is missing, unreadable, or contains neither recognized heading, when I request a translation, then today's hardcoded defaults are used for both pieces, unchanged from Story 4.3's shipped behavior — translation is never blocked or degraded by this feature's own failure modes.
4. **(Partial override)** Given `ai-prompts.md` defines only one of the two sections, when I request a translation, then only that piece is overridden — the other piece still falls back to its hardcoded default.
5. **(Empty section = not overridden)** Given `ai-prompts.md` has a `# Conventions` (or `# Translation Instructions`) heading with an empty or whitespace-only body, when I request a translation, then that piece falls back to its hardcoded default (Design decision 3) — not an empty string sent to the provider.
6. **(Re-read every time, no stale cache)** Given I edit `ai-prompts.md` on my desktop between two translate requests, when I request a translation the second time, then the second request reflects the edited file — no caching across calls.
7. **(Never throws — parser totality)** Given `ai-prompts.md` contains pathological input (extremely deep/large content, non-UTF8-clean bytes already decoded lossily by `RepoStorage.read`, a BOM, no headings at all, only `##`/`###` headings and no `# `), when parsed, then `AiPromptConfig.parse` never throws — worst case, both pieces fall back to their hardcoded defaults.
8. **(No regression to Story 4.3)** Given the full existing `translate_action_test.dart` and `paired_editor_page_test.dart` suites (none of which seed an `ai-prompts.md` file), when this story ships, then every existing test still passes unmodified — proving the missing-file path is exactly as safe as before.

## Tasks / Subtasks

- [ ] **Task 1: `AiPromptConfig` — the pure parser** (AC: 1, 2, 4, 5, 7)
  - [ ] 1.1 New file `apps/mobile/lib/ai/ai_prompt_config.dart`: `const String kAiPromptConfigFile = 'ai-prompts.md';` and a pure value type `AiPromptConfig` with `final String? instructions` and `final String? conventions` (both `null` = "not overridden, caller should use its own default" — mirrors `ProjectConfig`'s "field absent → caller applies its own default" shape, not a sentinel string). `const AiPromptConfig.empty` (both null).
  - [ ] 1.2 `factory AiPromptConfig.parse(String raw)`: strip a single leading BOM (`raw.startsWith('\u{FEFF}') ? raw.substring(1) : raw`, exact precedent: `project_config.dart:51`). Split into lines; walk them tracking the current top-level (`# ` prefix, i.e. exactly one `#` then a space — not `##`/`###`) heading and accumulating its body until the next top-level heading or EOF. Match heading text trimmed + lowercased against `'translation instructions'` → `instructions`, `'conventions'` → `conventions`; unknown headings' bodies are parsed (consumed) but discarded, not stored (forward-compatible with a future `# Grammar Instructions`). A body that is empty after `.trim()` is treated as absent (Design decision 3) — leave that field `null`, don't set it to `''`. Last occurrence of a given heading wins if repeated. Wrap the whole body in `try`/`catch` (catch-all, not just specific exception types — mirrors `project_config.dart:39-44`'s reasoning about `Error` subtypes not being caught by an `Exception`-typed clause) returning `AiPromptConfig.empty` on any unexpected failure — this factory must never throw (AC7).
  - [ ] 1.3 `Future<AiPromptConfig> resolveAiPromptConfig(RepoStorage storage)`: `storage.read(kAiPromptConfigFile)` then `AiPromptConfig.parse(...)`, with the read itself wrapped in `try`/`catch` returning `AiPromptConfig.empty` for a missing file, I/O error, or any other read failure (exact shape of `resolveProjectConfig`, `project_config.dart:98-109`) — this function must never throw either (AC3).
  - [ ] 1.4 Export `ai_prompt_config.dart` from `apps/mobile/lib/ai/ai.dart`'s barrel.

- [ ] **Task 2: Wire the override into `runTranslate`** (AC: 1, 2, 3, 6)
  - [ ] 2.1 In `apps/mobile/lib/ai/translate_action.dart`'s `runTranslate`, call `final promptConfig = await resolveAiPromptConfig(storage);` (no wrapping try/catch needed at the call site — Task 1.3 already makes it total) before building `sections`.
  - [ ] 2.2 Change the `instructions`/`conventions` local `ContextSection`s (currently `const`, using the raw `_kInstructions`/`_kConventions` constants directly) to `final`, built from `promptConfig.instructions ?? _kInstructions` and `promptConfig.conventions ?? _kConventions` respectively. No other line in `runTranslate` changes — `sections`, `showContextPreview`, the byte-for-byte `systemPrompt` concatenation (Story 4.3's own review fix), and the empty-response/error handling all operate on whatever text ends up in these two `ContextSection`s, unaware of where it came from.
  - [ ] 2.3 Re-read every call, no caching (AC6) — falls out for free from calling `resolveAiPromptConfig` fresh inside `runTranslate` every time, the same way `loadLore` is already called fresh for the glossary on every translate (Story 4.3's own Design decision 4 precedent).

- [ ] **Task 3: Tests** (AC: all)
  - [ ] 3.1 New file `apps/mobile/test/ai/ai_prompt_config_test.dart` (plain `test()`, not `testWidgets` — pure parsing logic, no widget tree needed; mirrors `apps/mobile/test/lore/project_config_test.dart`'s own style exactly): both sections present → both fields populated; only `# Translation Instructions` present → `conventions` stays null; only `# Conventions` present → `instructions` stays null; neither recognized heading present → both null; an unrelated `## Something Else` heading is ignored, not mistaken for a top-level section; a heading with only whitespace/blank lines under it → that field stays null (Design decision 3, AC5); a BOM-prefixed file parses correctly (mirrors `project_config_test.dart`'s own BOM test); pathologically large/malformed input never throws (`expect(() => AiPromptConfig.parse(huge), returnsNormally)`, mirroring that same test file's deep-JSON-nesting test's shape) (AC7); a repeated heading — last occurrence wins.
  - [ ] 3.2 `apps/mobile/test/ai/translate_action_test.dart` additions: seed a `FakeRepoStorage` with `ai-prompts.md` containing both sections, confirm the rendered preview AND the sent `AiRequest.system` reflect the overridden text (reuse the existing byte-for-byte assertion pattern from Story 4.3's own review-fix test — read the rendered section text via `_sectionText`, confirm, then assert the sent `system` matches); a second test seeds only one section and confirms the other piece still shows/sends the hardcoded default (AC4); confirm every *existing* test in this file (none of which seed `ai-prompts.md`) still passes unmodified (AC8 — this is a pure regression check, not a new test to write).
  - [ ] 3.3 Confirm `resolveAiPromptConfig` reading a missing file returns `AiPromptConfig.empty` via `FakeRepoStorage` with no `ai-prompts.md` seeded (already implicitly exercised by every pre-existing Translate test, but add one explicit assertion at the `ai_prompt_config_test.dart` or `translate_action_test.dart` level rather than relying purely on absence-of-failure).

- [ ] **Task 4: Regression and hygiene gates** (AC: all)
  - [ ] 4.1 Full `flutter test` green — confirm the count is exactly the pre-story baseline plus this story's new tests (no accidental deletions/skips).
  - [ ] 4.2 `flutter analyze` clean.
  - [ ] 4.3 Confirm `git status --porcelain` under `lib/`/`test/` touches only `ai/ai_prompt_config.dart` (new), `ai/translate_action.dart` (modified), `ai/ai.dart` (barrel export, modified), and their test counterparts — no `app/`, `lore/`, `storage/` file touched (this story needs no `AiClient`-threading-style navigation-chain changes; `runTranslate` already receives `storage` and `loreDir`).

## Dev Notes

### What changes, precisely

- **New:** `apps/mobile/lib/ai/ai_prompt_config.dart` (`AiPromptConfig` + `resolveAiPromptConfig`), `apps/mobile/test/ai/ai_prompt_config_test.dart`.
- **Modified:** `apps/mobile/lib/ai/translate_action.dart` (`runTranslate` resolves the override before building `sections`), `apps/mobile/lib/ai/ai.dart` (barrel export), `apps/mobile/test/ai/translate_action_test.dart` (new override/partial-override tests).
- **Unchanged:** everything about *how* the context pack is shown or sent (Story 4.3's 4-section shape, the byte-for-byte `systemPrompt` concatenation, the empty-response guard, `maxTokens`, the glossary assembly) — this story only changes where two of the four sections' *text* comes from. No `app/` file changes; no new `AiClient`/navigation-chain threading (unlike Story 4.3, `runTranslate` already has `storage`/`loreDir` in scope). `lore-story.json`/`ProjectConfig` are untouched — `ai-prompts.md` is a sibling file, not an extension of that one.

### Architecture constraints

- **AD-8 (total, never throw, never strand):** both `AiPromptConfig.parse` and `resolveAiPromptConfig` must be unconditionally total — a malformed, huge, or unreadable `ai-prompts.md` degrades to "use the hardcoded defaults," never an exception, never a blocked translation. This is the same discipline `ProjectConfig`/`resolveProjectConfig` already established for `lore-story.json` (`project_config.dart`) — follow that file's exact shape, don't reinvent a different resolution policy.
- **AD-9 (purity scope) / AD-12 (barrel-only cross-slice access):** `ai_prompt_config.dart` lives in `ai/` (an AI-prompt-content concern, not a lore concern) and must be exported from `ai/ai.dart`'s barrel, matching `context_preview.dart`/`translate_action.dart`'s own precedent from Stories 4.2/4.3. It depends on `storage/` (for `RepoStorage.read`) the same way `translate_action.dart` already does since Story 4.3 — no new slice-dependency direction introduced.
- **NFR4/offline-first:** reading a local repo file requires no network — this story adds zero new network-capable code paths; it only changes what text feeds into the *existing* Story 4.3 send path.
- **Testing standard for this story:** the parser (`AiPromptConfig.parse`) is pure logic with real failure-mode branches (missing/partial/malformed/empty-section/BOM/pathological input) — cover it thoroughly with plain unit tests per this project's testing-emphasis policy (a data-correctness concern: an author's carefully-written custom prompt silently not applying, or a malformed file silently blocking translation, are both real regressions this story exists to prevent). The wiring in `runTranslate` (Task 2) needs only enough integration coverage to prove the override actually reaches the sent payload — don't re-test parsing logic at the widget-test level.

### Previous story intelligence

Story 4.3 (most recently completed, done 2026-08-08, review-fixed same day) is the direct dependency — its own review findings are directly relevant here:
- **The AD-11 "glue text" bug** (Story 4.3's most severe review finding — the sent `system` prompt had contained label text not shown in any preview section) was fixed by building `systemPrompt` as a literal concatenation of the *already-built* `ContextSection`s' `.text` fields (`translate_action.dart:98-99`: `[instructions.text, glossary.text, conventions.text].join('\n\n')`). This story's Task 2.2 must preserve that property exactly — `instructions`/`conventions` become `final` (not `const`) and their `.text` comes from `promptConfig.instructions ?? _kInstructions` / `promptConfig.conventions ?? _kConventions`, but the concatenation logic downstream must not be touched or re-derived from the raw constants directly (that would silently reintroduce a "preview shows override, but sent text uses the hardcoded default" divergence — the exact bug class Story 4.3 just fixed, in a new place).
- **`_kMaxTokens` (16384), the empty-response guard, and the `AiClientException` handling** (all Story 4.3 review fixes) are untouched by this story — don't re-litigate them.
- **Story 4.3's own review found and fixed a byte-for-byte test gap** — this story's Task 3.2 deliberately asks for the same "read the rendered preview, then assert the sent payload matches" test shape (via `_sectionText`, already defined in `translate_action_test.dart`), not a weaker `contains(...)` check, for exactly the reason Story 4.3's review called out.
- **Story 4.1's "verify empirically, don't assume" lesson** applies here too: don't assume `RepoStorage.read`'s BOM-handling behavior for a non-JSON file matches `ProjectConfig`'s JSON case from reading the code alone — the BOM test in Task 3.1 (mirroring `project_config_test.dart`'s own) is how this gets confirmed, not skipped as "probably fine."

### Project Structure Notes

This is the second new file in `ai/` (after Story 4.3's `translate_action.dart`) and the first to mirror a `lore/`-slice pattern (`ProjectConfig`) rather than an `ai/`-internal one (`context_preview.dart`, `lint_panel.dart`). No changes to `apps/mobile/lib/lore/**` — `ProjectConfig`/`resolveProjectConfig` are read as *reference*, not modified or reused directly (a separate, parallel type for a separate file, not a shared abstraction — two config files with different shapes don't need a forced common interface). No changes to `apps/mobile/lib/storage/**` — `RepoStorage.read` already exists and is sufficient; no new port method needed.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 4.4 (FR29), and the Epic 4 summary's "Prompt customization" paragraph explaining the before-4.5 sequencing]
- [Source: ARCHITECTURE.md §3.4 — `lore-story.json`'s shape, the precedent this story's `ai-prompts.md` deliberately does NOT extend (Design decision 1)]
- [Source: apps/mobile/lib/lore/project_config.dart — `ProjectConfig`/`resolveProjectConfig`, the exact pattern (never-throw, BOM-strip, re-read-every-call, missing-key-ignored) this story's `AiPromptConfig`/`resolveAiPromptConfig` mirrors]
- [Source: apps/mobile/test/lore/project_config_test.dart — the pure-unit-test style (plain `test()`, no widget pump) this story's `ai_prompt_config_test.dart` mirrors, including the exact BOM and pathological-input test shapes]
- [Source: apps/mobile/lib/ai/translate_action.dart — `runTranslate`, specifically the `sections`-building block (`instructions`/`file`/`glossary`/`conventions` locals, lines ~84-93) and the byte-for-byte `systemPrompt` concatenation (lines ~98-99) this story wires into without altering]
- [Source: apps/mobile/test/ai/translate_action_test.dart — `_sectionText` helper (reads a rendered preview section's actual text) and the byte-for-byte AD-11 test this story's new override tests reuse the same shape of]
- [Source: _bmad-output/implementation-artifacts/4-3-translate-ru-en-release-checkpoint.md — most recent story; source of the AD-11 glue-text fix, the `_kMaxTokens`/empty-response-guard fixes, and the review-fix testing patterns cited above]
- [Source: project-context.md — "Strip a BOM before parsing text as data… apply the same guard to any new config/JSON reader" (the general rule this story's BOM handling follows, extended here to a non-JSON text file for the same underlying reason — Windows editors prepending one)]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
