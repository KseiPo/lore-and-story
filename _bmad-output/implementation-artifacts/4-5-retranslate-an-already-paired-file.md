---
baseline_commit: dbfdcde6f494b9f05814771f2bcee25a23ed9b00
---

# Story 4.5: Re-translate an already-paired file, in either direction

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to re-run AI translation on a pair that already has content on both sides,
so that I can refresh a translation after editing the other language, instead of only being able to create a translation that's missing entirely.

## Context

**FR30, and the epics.md ACs for this story (`_bmad-output/planning-artifacts/epics.md`, Story 4.5):**

> Let the author (re-)translate a pair that already has content on **both** sides — not just a lone RU file missing its EN pair — in **either** direction (RU→EN or EN→RU), to refresh a translation after editing the source language. Translating into a tab that already has content (saved or unsaved) asks for confirmation before replacing it.

**Why this exists (KseiPo, 2026-08-08).** Story 4.3 built translation as create-only — the Translate action only ever appeared on the synthetic tab Story 2.9 adds for a lone `.ru.md` with no `.en.md`, and only ever ran RU→EN. In real use, a real pair (both `.ru.md` and `.en.md` already exist) needs to stay in sync as either side is edited. This story generalizes the rule: **Translate appears on a tab whenever the *other* language's tab has non-blank content**, and always translates FROM the other tab INTO the current one — regardless of whether the current tab is create-mode or already has saved content. That single rule subsumes Story 4.3's original RU→EN-create case, the mirrored EN→RU-create case (Story 2.18's synthetic RU tab), and this story's new case (refresh either side of a real, already-paired item).

**Sequenced after Story 4.4** (done) so it can extend that story's `ai-prompts.md` section scheme with a second, direction-aware instructions heading rather than redesigning a file format that just shipped. Backward-compatible: an existing unprefixed `# Translation Instructions` heading (Story 4.4's original, RU→EN-only shape) continues to mean the RU→EN variant.

## The unifying design: one visibility/direction rule replaces two hardcoded ones

Today's `_PairedEditorPageState` (`apps/mobile/lib/app/paired_editor_page.dart`) hardcodes both halves of Story 4.3's RU→EN-create-only scope directly:

```dart
bool get _canShowTranslate =>
    _activeVariant.lang == 'en' && _activeVariant.createIfMissing;

String get _ruText =>
    _variants.firstWhere((v) => v.lang == 'ru').key.currentState?.text ?? '';
```

This story replaces both with one direction-agnostic rule, expressed in terms of **the active tab (the translate target) and its counterpart (the source)**:

- **Target** = the active tab (`_activeVariant`).
- **Source** = the *other* `ru`/`en` variant in `_variants` (never `orig` — direction is defined only between `ru` and `en`; see "Why `orig` never participates" below).
- **Visible** whenever a source variant exists **and** its *live* buffer (not the on-disk file) is non-blank.
- **Direction**: target `en` ⇒ translating RU→EN; target `ru` ⇒ translating EN→RU.

Trace this rule through every case FR30 and Story 4.3 already named, to see why it's a strict generalization and not a rewrite:

| Scenario | `_variants` | Active tab | Source (counterpart) | Result |
|---|---|---|---|---|
| Story 4.3 original: lone `.ru.md`, synthetic empty EN tab | `ru` (real), `en` (`createIfMissing`, empty) | `en` (default when only `ru` present... see note) | `ru`, has content | Translate shown, RU→EN — **unchanged from today** |
| Same, but viewing the RU tab | as above | `ru` | `en`, empty (nothing typed yet) | Translate hidden — **unchanged from today** (today's code never even considers this case since it's hardcoded to the `en` tab) |
| Story 2.18 mirrored case: lone `.en.md`, synthetic empty RU tab | `ru` (`createIfMissing`, empty), `en` (real) | `en` (primary) | `ru`, empty | Translate hidden while viewing EN |
| Same, after switching to the synthetic RU tab | as above | `ru` | `en`, has content | Translate shown, EN→RU, a **create** — this is FR30's "Story 2.18's mirrored synthetic RU tab... Translate is now available there too" AC, and Story 4.3's AC5 restriction ("no Translate action on the mirrored tab") is superseded exactly here |
| Real, already-paired item, both sides have saved content | `ru` (real), `en` (real) | either | the other, has content | Translate shown on **both** tabs — this is the new headline case |

**Why `orig` never participates:** `orig` variants only reach `PairedEditorPage` in the rare edge case of a base name having a bare `.md` *and* a `.ru.md`/`.en.md` sibling simultaneously (`_langRe` no-match branch, `lore_loader.dart:361`) — not Story 2.18's single-file undetermined-language case, which `entity_detail_page.dart:91-92`/`undetermined_language_page.dart` routes to a **different** page entirely before `PairedEditorPage` is ever constructed. Since translation direction is only meaningful between `ru` and `en`, the counterpart lookup simply returns nothing for an `orig`-active tab, so Translate never shows there — no special-case code needed, it falls out of the rule.

**Note on default-active-tab wording above:** `_PairedEditorPageState.initState`'s existing `primaryKey` logic (`paired_editor_page.dart:130-136`) already picks `orig ?? ru ?? en` as the default tab — for the Story 4.3 create-only case that's `ru` (not `en`), so "Active tab: `en`" in the table's first row means *after the author has already switched to the EN tab*, exactly as today's existing tests do (`tester.tap(find.text('EN'))` before checking for the translate action). No change to `primaryKey`/default-tab selection is in scope for this story.

## Acceptance Criteria

1. **(Bidirectional visibility, FR30)** Given a real, already-paired item (both `.ru.md` and `.en.md` exist with non-blank content), when I open either tab, then a Translate action is available on **both** — tapping it on the EN tab translates RU→EN (source = the live RU buffer, target = EN); tapping it on the RU tab translates EN→RU (source = the live EN buffer, target = RU).
2. **(Confirm-before-overwrite, regardless of dirty state)** Given the tab I'm translating INTO already has non-blank content — saved, unsaved, or both — when the translation completes and would overwrite it, then I'm asked to confirm before the buffer changes. This must fire even when the target tab is **not dirty** (a real, already-saved translation gets the same protection as an unsaved draft) — a strict widening of Story 4.3's existing `enState.isDirty`-gated confirm.
3. **(Direction-correct instructions and conventions)** Given the EN→RU direction, when the context pack is assembled, then both the `AI instructions` and `Conventions` preview sections are worded for translating INTO Russian (not the RU→EN text applied backwards). **Revised by review decision (KseiPo, 2026-08-08):** the glossary stays identical either direction (it's a plain alias list, genuinely direction-agnostic), but the hardcoded `Conventions` default is now a **direction-specific constant per direction** (`_kConventionsRuToEn`/`_kConventionsEnToRu`), not one shared generic constant — matching the same per-direction pattern as the instructions, and anticipating a future move to a per-direction config file. The `ai-prompts.md` `# Conventions` *override* (when an author sets one) still applies as a single shared field to whichever direction's default it's overriding — see Non-goals.
4. **(Story 2.18's mirrored tab unlocked)** Given Story 2.18's mirrored synthetic RU tab (an EN-original file with no RU pair yet), when I open it and it has EN content to translate from, then Translate is available there (EN→RU, a create) — Story 4.3's AC5 restriction ("no Translate action on the mirrored tab") is superseded by this story.
5. **(No regression to the RU→EN-create case)** Given everything Story 4.3 and Story 4.4 already shipped for the RU→EN create-only scenario, when this story ships, then that exact scenario — visibility (including the original "visible but disabled when blank" AC8 affordance, confirmed restored by review decision), the sent request (both instructions and conventions defaults are byte-for-byte the original text, confirmed by a dedicated test), and the `ai-prompts.md` override via the (unprefixed, backward-compatible) `# Translation Instructions` heading — keeps working byte-for-byte unchanged.
6. **(`ai-prompts.md` direction-aware override, extends Story 4.4)** Given an `ai-prompts.md` with a `# Translation Instructions (EN→RU)` section (case-insensitive; the ASCII-typable `(en->ru)` spelling is also recognized — see Task 1), when I request an EN→RU translation, then that section's text replaces the app's hardcoded EN→RU instructions in both the preview and the sent request, independently of whether `# Translation Instructions` (RU→EN) is also present. An empty body falls back to the hardcoded default (Design decision 3 from Story 4.4, unchanged).
7. **(Never crashes, AD-8)** Given any malformed, huge, or unreadable `ai-prompts.md`, or a target tab whose `FileEditorState` isn't ready when a translation result arrives, when a translate is attempted, then it degrades exactly as Story 4.3/4.4 already established (hardcoded defaults; a "the tab was not open to receive it" SnackBar) — no exception, no stranded page.

**Non-goals** (explicitly out of scope, per epics.md and to keep this story's blast radius matched to FR30):
- Automatic staleness detection — translation stays manually triggered every time (FR22's "mandatory, not automatic" framing).
- Canceling an in-flight translation (Story 4.3's own non-goal, unchanged).
- Any change to how a translated buffer is saved (still an explicit Save — unchanged since Story 2.9).
- A direction-specific `Conventions` *override* heading in `ai-prompts.md` (e.g. no `# Conventions (EN→RU)`) — the single `# Conventions` heading still applies to whichever direction's default it's overriding, matching FR29's existing single-piece-per-heading design. (Revised by review decision, 2026-08-08: this Non-goal is now specifically about the *override scheme*, not the hardcoded defaults — see AC3's revision, the hardcoded defaults ARE now direction-specific.)
- Widening `entity_detail_page.dart`'s `_needsTranslation`/"Needs translation" chip (`entity_detail_page.dart:82-83,355`) to also flag an EN-only item — that badge is Story 2.9/FR13's create-signal for the RU→EN case specifically; FR30 only asks that the *editor's* Translate action become bidirectional, not that the outer list's badge semantics change. Leave it as-is.
- New dialog copy distinguishing "unsaved edits" from "saved content about to be overwritten" — reuses `confirmDiscardUnsaved(context, lossy: false)` verbatim (its existing "Your changes have not been saved" text is a little imprecise for the saved-content case, but the underlying warning is still true: visible content is about to be replaced). A copy refinement is a candidate for `deferred-work.md`, not this story.
- User-facing documentation/template for `ai-prompts.md`'s heading set — already a standing gap noted in `deferred-work.md`'s Story 4.4 entry; not resolved here.
- Fixing the pre-existing "Translate button disappears from the AppBar when switching tabs mid-translation" gap (`deferred-work.md`, Story 4.3 entry) — unchanged by this story; verify it doesn't get *worse* (see Task 3's note), but don't fix it.

## Tasks / Subtasks

- [x] **Task 1: `ai_prompt_config.dart` — direction-aware instructions heading** (AC: 3, 5, 6, 7)
  - [x] 1.1 Rename `_Heading.instructions` → `_Heading.instructionsRuToEn`; add `_Heading.instructionsEnToRu`. `_Heading.conventions` unchanged.
  - [x] 1.2 Rename `AiPromptConfig.instructions` → `instructionsRuToEn`; add `final String? instructionsEnToRu`. `conventions` unchanged. Update `AiPromptConfig.empty`, the constructor, `==`/`hashCode`/`toString` accordingly (mirror the existing `toString` shape — `'default'`/`'overridden'` per field, now three entries).
  - [x] 1.3 Extend `_kKnownHeadings` (`Map<String, _Heading>`) with two additional entries mapping to `_Heading.instructionsEnToRu`: `'translation instructions (en→ru)'` (canonical, using the real arrow character U+2192) and `'translation instructions (en->ru)'` (ASCII-typable alias — cheap insurance against a keyboard/locale that can't easily produce `→`, matching this project's existing `->`-as-arrow convention used elsewhere, e.g. scene passage links). `'translation instructions'` (no direction suffix) keeps mapping to `_Heading.instructionsRuToEn` **unchanged** — this is Story 4.4's original heading and must keep meaning RU→EN for backward compatibility (AC5). Matching stays case-insensitive + trimmed, same as today.
  - [x] 1.4 Update `flush()`'s `switch (currentHeading)` to cover all three `_Heading` values, assigning into the three now-separate fields. "Empty body → not overridden" (Story 4.4 Design decision 3) and "last occurrence wins, including when the last occurrence is empty" (Story 4.4's own review fix) both apply identically to the new `instructionsEnToRu` field — no new logic branch, just a third case in the same switch.
  - [x] 1.5 Update the class doc comment to describe the three recognized headings and their fallback semantics (each independently `null` = "use my own hardcoded default"), and to note the dual `(en→ru)`/`(en->ru)` spelling. Keep `@immutable`.
  - [x] 1.6 `resolveAiPromptConfig` is unchanged (still `storage.read` + `AiPromptConfig.parse`, still never throws) — no edits needed beyond what Task 1.1–1.2's renames require to compile.

- [x] **Task 2: `translate_action.dart` — bidirectional `runTranslate`** (AC: 1, 3, 5, 6, 7)
  - [x] 2.1 Add `enum TranslationDirection { ruToEn, enToRu }` to this file (the feature owner — `ai_prompt_config.dart` does not need to know about direction, avoiding any risk of a circular import between the two files).
  - [x] 2.2 Rename `_kInstructions` → `_kInstructionsRuToEn`. Its text is **byte-for-byte unchanged** (AC5) — this is purely a rename.
  - [x] 2.3 Add `_kInstructionsEnToRu`, a genuinely-authored mirror (not a mechanical RU/EN find-replace) of `_kInstructionsRuToEn`'s content, worded for translating INTO Russian (AC3).
  - [x] 2.4 `_kConventions` — **discovered during implementation to need a small edit, not "unchanged" as originally planned**: two of its lines hardcoded the RU→EN direction (`"...English form"`, `` `lang: ru` to `lang: en` ``), which would have been actively wrong advice for an EN→RU request. Reworded both lines to be direction-neutral ("the language you are translating into") so the **same single constant** is correct either direction, per AC3's actual intent ("the same... conventions apply either direction") — not forked per direction. Verified no test asserts the old exact phrasing (`contains('lang: ru')`/`contains('lang: en')` still holds as substrings).
  - [x] 2.5 Change `runTranslate`'s signature: rename the `required String ruText` parameter to `required String sourceText`, and add `required TranslationDirection direction`.
  - [x] 2.6 Inside `runTranslate`, select the instructions text by direction via a `switch` expression (the one place the direction decision is made); `conventionsText` stays `promptConfig.conventions ?? _kConventions`; the `file` section's text becomes `sourceText`. The byte-for-byte `systemPrompt` concatenation and `AiRequest` construction are untouched.
  - [x] 2.7 Doc comments updated to describe both directions.

- [x] **Task 3: `paired_editor_page.dart` — generalize visibility, source/target resolution, and the overwrite confirm** (AC: 1, 2, 4)
  - [x] 3.1 Added `_counterpartOf(String lang)` exactly as specified.
  - [x] 3.2 Replaced `_canShowTranslate`.
  - [x] 3.3 Replaced `_ruText` with `_sourceText`; updated the `onPressed` guard.
  - [x] 3.4 Rewrote `_translate()` with target/source/direction resolution as specified.
  - [x] 3.5 The key behavior change (AC2) — overwrite guard now `targetState.text.trim().isNotEmpty` instead of `.isDirty`.
  - [x] 3.6 Tooltip now names the source language dynamically (`'Translate from ${label}'`).
  - [x] 3.7 Sanity-checked: `_translating` still gates `onPressed` globally across tab switches — unchanged.
  - [x] 3.8 **Discovered during implementation, not anticipated by this task's original text:** reading a counterpart tab's `key.currentState` returns `null` until that `TabBarView` page has actually been visited (`PageView` only builds pages near the viewport, not eagerly — verified empirically via a failing test, not assumed). This broke AC1's "available the moment either tab is opened" for a real already-paired item's non-default tab. Fixed with a `_textOf(_Variant? v)` helper: prefers the live buffer (`v.key.currentState?.text`) when the tab has been built, falling back to the *original* loaded text (`widget.item.langs[v.lang]?.text`) otherwise. Used by both `_sourceText`/`_canShowTranslate` (visibility) and `_translate()`'s actual `sourceText` resolution, so the two can never diverge (mirroring this story's own AD-11 discipline). A synthetic (`createIfMissing`) tab has no `widget.item.langs` entry, so it still correctly reads as blank until the author actually types into it — no regression to the create-tab cases.

- [x] **Task 4: Tests — invert the two now-superseded assertions, add bidirectional + saved-content-overwrite coverage** (AC: all)
  - [x] 4.1 Replaced `'Translate never appears for an already-paired RU/EN item'` with `'(Story 4.5/FR30) Translate appears on BOTH tabs of a real, already-paired item...'` plus a second test proving each tab fires the correct direction.
  - [x] 4.2 Replaced `'Translate never appears on the mirrored EN→RU synthetic tab...'` with `'(Story 4.5/FR30) Translate is now available on Story 2.18's mirrored synthetic RU tab...'`, covering visibility, EN→RU-worded preview instructions, the request, and the create landing in the RU tab.
  - [x] 4.3 Added EN→RU mirrors: blank-EN hides Translate; translates the EN tab's live unsaved buffer; translate-then-Save writes `.ru.md`; a failing EN→RU call shows a SnackBar and stays retryable. Also converted the AC8 test from "disabled" to "hidden" (Task 3's visibility-gates-on-content-not-just-enablement discovery, matching AC1's literal "appears... whenever... non-blank" wording).
  - [x] 4.4 Added the core AC2 test group (`'(Story 4.5/AC2) confirm-before-overwrite fires for SAVED, non-dirty target content...'`): a clean, disk-loaded (never-edited) target tab still triggers the "Discard changes?" dialog, with both "Keep editing" and "Discard" (overwrite) outcomes covered.
  - [x] 4.5 Regression-checked: all pre-existing RU→EN create-case tests pass unmodified in behavior.
  - [x] 4.6 `_pumpHost` gained an optional `direction` parameter (default `ruToEn`, so all ~15 existing call sites are untouched — AC5). Added a `Story 4.5: EN→RU direction` group: preview/request wording, `# Translation Instructions (EN→RU)` override, the `(en->ru)` ASCII alias, independent partial-override (only the RU→EN heading present leaves EN→RU on its default), and conventions-identical-either-direction.
  - [x] 4.7 Renamed `instructions` → `instructionsRuToEn` throughout; added the `Story 4.5: EN→RU direction-aware heading` group covering both spellings, independent-field population, empty-body fallback, repeated-heading-with-empty-last-occurrence, plus a `toString`/`==`/`hashCode` test covering all three fields.
  - [x] 4.8 Confirmed via `git status --porcelain` — exactly the six files in Task 5.3, no more, no less.

- [x] **Task 5: Regression and hygiene gates** (AC: all)
  - [x] 5.1 Full `flutter test`: 568 tests, all green.
  - [x] 5.2 `flutter analyze`: no issues found.
  - [x] 5.3 Changed-file set confirmed exactly as predicted: `apps/mobile/lib/ai/ai_prompt_config.dart`, `apps/mobile/lib/ai/translate_action.dart`, `apps/mobile/lib/app/paired_editor_page.dart`, `apps/mobile/test/ai/ai_prompt_config_test.dart`, `apps/mobile/test/ai/translate_action_test.dart`, `apps/mobile/test/app/paired_editor_page_test.dart`. No `lore/`/`storage/`/`ai_client.dart`/`context_preview.dart`/`messages_api_client.dart` changes were needed.

### Review Findings

Cross-model adversarial review (Blind Hunter + Edge Case Hunter + Acceptance Auditor, all on Opus; implementation was on Sonnet 5) against the uncommitted diff. Findings below are deduplicated and severity-rated after reading the actual current source (not from diff hunks alone).

- [x] [Review][Decision] **AC5's "byte-for-byte unchanged" conflicts with AC3's "same conventions apply either direction."** **Resolved by KseiPo (2026-08-08): option (b)** — forked `_kConventions` into `_kConventionsRuToEn` (reverted to the exact byte-for-byte pre-story text) and `_kConventionsEnToRu` (its EN→RU mirror). KseiPo's reasoning: "we might want to extract this constant to a configuration file and make it language dependent, so better have one const for each language direction for now." AC3's text was updated accordingly — the hardcoded *defaults* are now direction-specific; the `ai-prompts.md` `# Conventions` *override* stays a single shared field applied to whichever default it overrides (this story's Non-goals on a direction-specific override still hold — only the hardcoded defaults were forked). [apps/mobile/lib/ai/translate_action.dart]
- [x] [Review][Decision] **Translate-button visibility changed from Story 4.3's "visible but disabled when blank" (AC8) to "hidden when blank."** **Resolved by KseiPo (2026-08-08): option (b)** — restored `_canShowTranslate` to a structural check (`_counterpartOf(...) != null`), matching Story 4.3's original AC8 affordance exactly; `onPressed` still gates on content via `_sourceText`. [apps/mobile/lib/app/paired_editor_page.dart]
- [x] [Review][Patch] **AC2's overwrite guard is not a strict superset of Story 4.3's `isDirty` check — a dirty-but-blank target is silently overwritten with no confirm.** Fixed: `if (targetState.isDirty || targetState.text.trim().isNotEmpty)`. New regression test added proving an unsaved deletion is protected. [apps/mobile/lib/app/paired_editor_page.dart]
- [x] [Review][Patch] **`_textOf` treats any built tab as "live" regardless of load state.** Fixed: gated on `state.isReady`, not just `state != null`. [apps/mobile/lib/app/paired_editor_page.dart]
- [x] [Review][Patch] **Translate SOURCE text for a never-visited counterpart tab was read from a stale in-memory snapshot.** Fixed: `_translate()` now calls a new `_freshTextOf` that prefers the live ready buffer, otherwise does a fresh `widget.storage.read`, falling back to the static snapshot only on a read failure. The synchronous `_textOf`/`_sourceText` (used only for the cheap enable/disable check) still use the static fallback. [apps/mobile/lib/app/paired_editor_page.dart]
- [x] [Review][Patch] **No symmetric `(RU→EN)` heading alias.** Fixed: added `'translation instructions (ru→en)'`/`'(ru->en)'` to `_kKnownHeadings`, mapped to the existing `_Heading.instructionsRuToEn`. [apps/mobile/lib/ai/ai_prompt_config.dart]
- [x] [Review][Patch] **Test title at line 138 was stale and contradicted the two tests immediately following it.** Fixed: retitled and rewritten to assert the actual current (visible-but-disabled) behavior. [apps/mobile/test/app/paired_editor_page_test.dart]
- [x] [Review][Patch] **The "fires the correct direction" test only asserted source text, not direction.** Fixed: added `_previewInstructionsText` assertions pinning down the actual instructions text sent for each leg. [apps/mobile/test/app/paired_editor_page_test.dart]
- [x] [Review][Patch] **`_kInstructionsEnToRu`'s doc comment overclaimed "not a mechanical RU/EN swap."** Fixed: removed the false claim. [apps/mobile/lib/ai/translate_action.dart]
- [x] [Review][Patch] **Stale doc comments left over from Story 4.3's single-direction scope.** Fixed: `PairedEditorPage.aiClient`'s doc and `_textOf`'s "Story 4.3's own lesson" mis-attribution both corrected. [apps/mobile/lib/app/paired_editor_page.dart]
- [x] [Review][Patch] ~~Dead `_sourceText.trim().isEmpty` clause in the Translate button's `onPressed`~~ — **moot after the visibility decision above**: with `_canShowTranslate` reverted to a structural check, the `onPressed` content check is no longer dead code (visibility and enablement now test different things again). No change needed.
- [x] [Review][Defer] Reused `confirmDiscardUnsaved` dialog copy ("Your changes have not been saved... Discard") reads ambiguously for the new saved-content overwrite case — already an explicit story Non-goal; flagged again here because AC2's widening makes it reachable far more often. [apps/mobile/lib/app/paired_editor_page.dart:324] — deferred, pre-existing tradeoff explicitly accepted in this story's own Non-goals
- [x] [Review][Defer] `_kMaxTokens` (16384) was not re-derived for Cyrillic output token density on the new EN→RU direction — speculative, no observed truncation. [apps/mobile/lib/ai/translate_action.dart] — deferred, no evidence of an actual problem
- [x] [Review][Defer] The Translate spinner can appear on a tab whose direction isn't the one actually in flight if the author switches tabs mid-translation — cosmetic only (button stays disabled, no functional harm); explicitly non-goal'd by this story ("verify it doesn't get worse, don't fix it"). [apps/mobile/lib/app/paired_editor_page.dart] — deferred, matches the story's own stated non-goal
- [x] [Review][Defer] Heading-spelling recognition is narrow (exact arrow/ASCII forms only) — spacing variants, `⇄`, or "to"-worded headings aren't recognized. [apps/mobile/lib/ai/ai_prompt_config.dart] — deferred, no AC requires broader fuzzy matching
- [x] [Review][Defer] `confirmDiscardUnsaved` is always called with `lossy: false`, never reflecting the target's actual `isLossy` state — pre-existing since Story 4.3, now reachable via more paths. [apps/mobile/lib/app/paired_editor_page.dart] — deferred, pre-existing gap widened but not introduced by this story
- [x] [Review][Defer] AC7's "tab was not open to receive it" SnackBar path has zero test coverage — pre-existing gap since Story 4.3. [apps/mobile/lib/app/paired_editor_page.dart:312-316] — deferred, pre-existing gap

**Dismissed as noise / false alarm / pre-existing unchanged behavior:** declining the overwrite silently drops the translation (this is the correct, intended effect of the user's explicit "Keep editing" choice — unchanged since Story 4.3, not a bug); dead-code/unreachable-else defensive fallbacks in the tooltip and direction inference (harmless style consistent with the rest of the file); `_translate`'s guard returning silently if the source empties between visibility-computation and tap (identical pre-existing pattern since Story 4.3, not a new regression); a pre-existing Story 4.4 `ai-prompts.md` `# Conventions` override now applying to both directions (this is literally what AC3 requires — folded into the first Decision item above, not a separate defect); `runTranslate` lacking an internal blank-`sourceText` guard (no reachable call site is unguarded today — speculative hardening, not a current bug).

## Dev Notes

### What changes, precisely

- **Modified only — no new files** (unlike Story 4.4, which added `ai_prompt_config.dart` itself; this story extends three already-existing files and their three already-existing test files).
- **Unchanged:** `ai_client.dart`, `messages_api_client.dart`, `context_preview.dart` (the 4-section preview shape stays identical, just fed different text), `key_store.dart`, the glossary-assembly logic (`loadLore` + alias join), `_kMaxTokens`, the empty-response guard, all `AiClientException` handling, `entity_detail_page.dart`'s routing/badge logic (see Non-goals), `undetermined_language_page.dart`'s in-place delegation to `PairedEditorPage` after a language-confirm rename (already exercises the mirrored-tab case this story unlocks Translate on — no changes needed there, only in `PairedEditorPage` itself).

### Architecture constraints

- **AD-8 (total, never throw, never strand):** the direction-aware `AiPromptConfig` parsing and `runTranslate` must stay unconditionally total, exactly as Story 4.4 established — a malformed `ai-prompts.md`, a target tab that isn't ready, or an AI failure all degrade to a safe, reported state, never an exception or a blocked UI.
- **AD-11 (byte-for-byte preview-vs-sent):** Story 4.3's fix — `systemPrompt` is built *only* from the already-built `ContextSection.text` values, never re-derived from a raw constant — must hold for **both** directions. The easiest way to violate this by accident is picking the right preview text but the wrong constant when building `systemPrompt`, or vice versa; Task 2.6's `switch` expression is written so there is exactly one place the direction decision is made, and everything downstream just reads `instructionsText`.
- **AD-7 (extend the shared mechanism, don't fork it):** `ai-prompts.md`'s section-heading scheme gains a third heading via the same `Map<String, _Heading>` + `switch` pattern Story 4.4 built — not a second parser, not a different file.
- **Testing standard for this story:** `paired_editor_page_test.dart`'s two now-inverted tests (Task 4.1/4.2) are the highest-risk part of this story to get wrong — a dev who *adds* new tests without *removing/replacing* the old, now-false assertions will ship a suite that contradicts itself (one test asserting Translate never appears on an already-paired item, another asserting it does). Grep the file for `'Translate never appears for an already-paired'` and `'mirrored EN→RU synthetic tab'` before considering Task 4 done.

### Previous story intelligence

Story 4.4 (most recently completed, done 2026-08-08) is the direct dependency:
- Its `AiPromptConfig`/`resolveAiPromptConfig` never-throw/BOM-strip/re-read-every-call contract (`ai_prompt_config.dart`) is extended, not replaced — Task 1 keeps `resolveAiPromptConfig` itself untouched.
- Its review found and fixed "last occurrence wins is false when the last occurrence's body is empty" by rewriting the field-routing from a stringly-typed map to an enum switch specifically so a typo can't silently degrade to "never overridden." Task 1.1's rename preserves that enum-switch shape for the third field — don't reintroduce a `Map<String,String>`-keyed alternative.
- Its review also found three stale story-number references in comments (`translate_action.dart`, `context_preview.dart`, `ai_prompt_config.dart`) calling the wrong story "grammar review"/"grammar instructions" — while touching these same files, verify no fresh stale reference to *this* story's number gets introduced, and that any reference to "Story 4.5" elsewhere in the codebase still correctly means *this* story (retranslation), not something else.
- Story 4.3's own review fixes (`_kMaxTokens` = 16384, the empty-response guard, `AiClientException` handling, the AD-11 byte-for-byte concatenation) are all untouched by this story — don't re-litigate them.
- **Correction, confirmed false during implementation:** the assumption that "`TabBarView` builds all tabs' `FileEditor`s eagerly, so a counterpart's live text is always readable" turned out to be **wrong** — `TabBarView`'s underlying `PageView` only builds a page once it has actually been the active page at least once; a tab the author has never switched to has `key.currentState == null`. The pre-Story-4.5 `_ruText` getter never exposed this because it only ever ran while viewing the EN tab and reading the RU tab specifically — and RU was always the *default* (initial, always-built) tab in every case it was used for. This story's `_sourceText`/`_canShowTranslate` read a counterpart from *either* tab, including a real pair's non-default tab on first open, which surfaced the gap immediately as a failing test. Fixed via `_textOf`'s original-text fallback (Task 3.8) — recorded here as the concrete lesson for any future story reading cross-tab `FileEditorState`.

### Project Structure Notes

Confined to `ai/` (2 files) and `app/` (1 file, `paired_editor_page.dart` — the same file Story 4.3 and Story 2.9 both already own the translate/create-tab logic in). No `lore/`, `storage/`, or navigation-routing (`entity_detail_page.dart`, `entity_navigation.dart`) changes are expected — the bidirectional rule is entirely internal to how `PairedEditorPage` already receives and displays a multi-variant `LoreItem`; nothing about *which* items reach that page changes.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 4.5 (FR30), including its Context paragraph explaining the "Translate appears whenever the other tab has content" unifying rule and the post-4.4 sequencing rationale]
- [Source: apps/mobile/lib/app/paired_editor_page.dart — `_canShowTranslate`/`_ruText`/`_translate` (lines ~229-286), the exact hardcoded RU→EN-create-only logic this story generalizes; `_Variant`/`_variants`/`initState`'s synthetic-tab construction (lines ~12-144) for both the Story 2.9 and Story 2.18 synthetic-tab cases]
- [Source: apps/mobile/lib/ai/translate_action.dart — `runTranslate`, `_kInstructions`, `_kConventions` (the RU→EN text this story renames and mirrors, not rewrites)]
- [Source: apps/mobile/lib/ai/ai_prompt_config.dart — `AiPromptConfig`, `_Heading`, `_kKnownHeadings`, `flush()`'s enum-switch field routing (the exact pattern this story's third heading extends)]
- [Source: apps/mobile/lib/lore/lore_loader.dart:358-420 — `byBase`/`orig`/`ru`/`en` variant construction, confirming `orig` and the single-file undetermined-language case (`entity_detail_page.dart:91-92`) never overlap with the bidirectional-translate cases this story touches]
- [Source: apps/mobile/lib/app/undetermined_language_page.dart:260-270 — the in-place delegation to `PairedEditorPage` after a language-confirming rename, which is how the Story 2.18 mirrored-tab case this story unlocks actually reaches `PairedEditorPage` in practice (not via `entity_detail_page.dart`'s route-based navigation)]
- [Source: apps/mobile/test/app/paired_editor_page_test.dart — the two tests this story must invert (`'Translate never appears for an already-paired RU/EN item'`, `'...mirrored EN→RU synthetic tab...'`), and the existing overwrite-confirm tests (`'(review fix) translating over a manually-edited EN draft asks before overwriting it'` and its confirm counterpart) this story's new saved-content-overwrite tests mirror the shape of]
- [Source: apps/mobile/test/ai/translate_action_test.dart — `_pumpHost`, `_sectionText`, `_storageWithPromptOverride` (the fixture-building patterns this story's EN→RU tests reuse)]
- [Source: _bmad-output/implementation-artifacts/4-4-customize-the-ai-translation-prompt.md — most recent story; source of the enum-switch field-routing fix, the "empty body = not overridden" design decision, and the never-throw/BOM-strip contract this story's third heading follows]
- [Source: _bmad-output/implementation-artifacts/4-3-translate-ru-en-release-checkpoint.md — source of the AD-11 byte-for-byte fix and the confirm-before-overwrite pattern (`confirmDiscardUnsaved`) this story widens from dirty-only to any-non-blank-content]
- [Source: _bmad-output/implementation-artifacts/deferred-work.md — Story 4.3 entry ("Translate button disappears from the AppBar when switching tabs mid-translation") and Story 4.4 entry ("`ai-prompts.md` heading not documented anywhere a user would find it") — both relevant context this story deliberately does not resolve, see Non-goals]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5.

### Debug Log References

- `TabBarView`/`PageView` does not build every tab eagerly — a page is only constructed once it has actually been the active page. Confirmed by a failing test (`(Story 4.5/FR30) Translate appears on BOTH tabs...` initially failed with "Found 0 widgets with key translate-action" when checking the default tab immediately after opening a real pair, before ever switching tabs) rather than assumed from reading the widget source. See Task 3.8 and the corrected "Previous story intelligence" note above.
- `_kConventions` was not actually direction-neutral as Task 2.4 originally assumed — two lines hardcoded the RU→EN direction (`"...English form"`, `` `lang: ru` to `lang: en` ``). Caught by re-reading the full constant during implementation rather than trusting the story's "unchanged" claim; fixed by rewording both lines to reference "the language you are translating into" generically, verified against the existing test that asserts `contains('lang: ru')`/`contains('lang: en')` (still holds as substrings of the reworded sentence).
- A newly-added widget test (`'Conventions are identical either direction...'`) initially produced a hit-test warning from re-pumping a second `_pumpHost` without dismissing the first preview sheet — fixed by tapping `context-preview-cancel` between the two pumps, matching the established pattern from the pre-existing AC6 re-read test.
- The new saved-content-overwrite test needed an explicit `enterEditMode(tester)` call after switching tabs (the paired editor opens a freshly-switched-to tab in read-only preview mode, not the raw editor) — an existing helper already used by other tests in this file, just missed on the first pass.

### Completion Notes List

- All 7 ACs implemented: bidirectional Translate visibility and firing (AC1), confirm-before-overwrite widened from `isDirty` to "`isDirty` OR any non-blank content" (AC2), direction-correct instructions AND conventions (AC3, revised — see below), Story 2.18's mirrored tab unlocked (AC4), byte-for-byte non-regression of the RU→EN create case including visibility (AC5, revised — see below), the direction-aware `ai-prompts.md` heading with dual arrow/ASCII spelling in both directions (AC6), and AD-8 total-never-throw preserved throughout (AC7).
- Two corrections to the story's own plan, both discovered (not assumed) during implementation: `_kConventions` needed two lines genericized (it wasn't already direction-neutral) and `TabBarView` needed a fallback-to-original-text mechanism (it doesn't eagerly build every tab). See Task 2.4/3.8 and the Debug Log above.
- **Cross-model code review round (Opus reviewing Sonnet 5's implementation — Blind Hunter + Edge Case Hunter + Acceptance Auditor):** 2 decision-needed, 9 patch, 5 defer, 6 dismissed as noise/pre-existing. Both decisions resolved by KseiPo (2026-08-08) in favor of matching Story 4.3's original behavior more closely: (1) `_kConventions` forked into per-direction constants (`_kConventionsRuToEn`/`_kConventionsEnToRu`) instead of one genericized shared constant — AC3/AC5/Non-goals updated accordingly; (2) Translate-button visibility reverted to "visible but disabled when blank" (AC8's original affordance) instead of "hidden when blank." All 9 patches applied: the AC2 guard is now `isDirty || text.isNotEmpty` (a real data-loss bug — a dirty-but-blank target was previously silently overwritten with no confirm, now covered by a regression test); `_textOf`'s live-buffer check now gates on `isReady` (a built-but-loading/errored counterpart no longer misreads as blank); translate-time source text is now re-read fresh from disk via a new `_freshTextOf` when the live buffer isn't ready, instead of trusting a potentially-stale in-memory snapshot; `ai-prompts.md` now recognizes the symmetric `(RU→EN)` heading (arrow and ASCII) as an explicit synonym of the unprefixed heading; a stale pre-4.5 test title was fixed; the "fires the correct direction" test now actually asserts the direction sent, not just the source text; two inaccurate/stale doc comments were corrected. Findings and resolutions are recorded in the Review Findings section below and in `deferred-work.md`.
- Full regression: 572 `flutter test` passing, `flutter analyze` clean, changes confined to exactly the 6 files the story predicted (3 lib + 3 test, no `lore/`/`storage/`/other `ai/` files touched) — the review round only edited within those same 6 files.

### File List

**Modified:**
- `apps/mobile/lib/ai/ai_prompt_config.dart`
- `apps/mobile/lib/ai/translate_action.dart`
- `apps/mobile/lib/app/paired_editor_page.dart`
- `apps/mobile/test/ai/ai_prompt_config_test.dart`
- `apps/mobile/test/ai/translate_action_test.dart`
- `apps/mobile/test/app/paired_editor_page_test.dart`

## Change Log

| Date | Change |
|------|--------|
| 2026-08-08 | Story drafted via create-story workflow (ultimate context engine), auto-discovered as the first backlog story in Epic 4 following Story 4.4. |
| 2026-08-08 | Implemented Story 4.5: bidirectional AI translation (RU↔EN) for `PairedEditorPage`, a direction-aware `# Translation Instructions (EN→RU)` heading in `ai-prompts.md` (backward-compatible with Story 4.4's unprefixed RU→EN heading), and a widened overwrite-confirm guard (any non-blank target content, not just a dirty draft). Two real gaps found and fixed beyond the story's original plan: `_kConventions` had two direction-hardcoded lines (genericized), and `TabBarView` doesn't eagerly build every tab (added an original-text fallback so Translate is available on both tabs from the moment a real pair is opened, per AC1). Full regression green (568 tests); status → review. |
| 2026-08-08 | Cross-model code review (Opus reviewing Sonnet 5's implementation): 2 decision-needed, 9 patch, 5 defer, 6 dismissed. KseiPo resolved both decisions in favor of Story 4.3 parity: `_kConventions` forked per direction (not genericized) and Translate-button visibility restored to visible-but-disabled (not hidden) when blank. All 9 patches applied, including a real data-loss bug fix (AC2's overwrite guard missed an unsaved deletion) and a staleness fix (translate-time source now re-reads fresh from disk instead of a cached snapshot). AC3/AC5/Non-goals text revised to match the resolved decisions. Full regression re-verified green (572 tests, `flutter analyze` clean); status → review (unchanged — no unresolved high/medium findings remain, but see completion workflow for final status determination).
