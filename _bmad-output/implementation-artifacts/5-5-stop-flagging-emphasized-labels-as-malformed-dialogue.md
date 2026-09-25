---
baseline_commit: f7cd977
---

# Story 5.5: Stop flagging emphasized labels as malformed dialogue

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want the linter to leave bold and italic labels like `**Role:** …` alone, and to tell me accurately when I've used the retired italic `*Thought:*` form,
so that an ordinary entity card's profile block lints clean and every finding I do get is true.

## Context

**The false positive (verified 2026-09-24 against the real matcher, probe script run via `dart run --packages=apps/mobile/.dart_tool/package_config.json`):**

- `matchConventions('**Role:** Previous keeper.')` → `malformedDialogue` over `**Role:` → the Lint panel says "Dialogue line is missing a space after the colon."
- `**Селена:** Привет.` behaves the same.
- `**Role**: value` (colon outside the bold) is clean — `_dialogue` matches it as a `dialogueSpeaker`, no error.
- `- **Role:** value` is clean only by accident: `_malformedDialogue` *does* match `- **Role:`, but `listMarker` (priority 0) wins the overlap.
- The repo's own sample card `lore/characters/mira.md` gets **five** false findings, one per labeled line: `**Role:**`, `**Appearance:**`, `**Voice / writing style:**`, and the end-of-line labels `**Secrets:**` / `**Relationships:**` (a label heading the list below it). ARCHITECTURE.md §3.2b describes every entity card as opening with a profile block (type, faction, age, occupation, …), so authors hit this on every profile line.
- Also flagged today, same cause: `**Age:** 42`, mid-line `Note that **the key:** value`, indented `  **Indented:** value`, `**Role (old):** value`, `*Note:* text`, `_Note:_ text` (exactly what the toolbar's italic button inserts — `editor_toolbar.dart:512` wraps with `_`/`_`), `__Role:__ value`, `***Role:*** value`.
- **Second symptom:** the error token (priority 5) suppresses the overlapping `bold` token (priority 7) in `_resolveOverlaps`, so the editor highlights `**Role:` with the wavy error squiggle instead of bold, and the toolbar's Bold button shows as **inactive** inside the label (`isFormattingActive` reads the `bold` token — `editor_toolbar.dart:209-234`, `:452`). Restoring the bold token fixes both for free.

**Cause:** `_malformedDialogue` (`apps/mobile/lib/lore/convention_matcher.dart:113-114`) ends with `:(?=[^\s/])` — any character except whitespace or `/` right after the colon means "missing space". The closing `**`/`*`/`_` of an emphasized label whose colon sits *inside* the emphasis satisfies that.

**The retired italic monologue.** Inner monologue was `*Thought:* …` (EN) until commit `2baf178` (Story 4.4, 2026-08-08) switched ARCHITECTURE.md §3.3 and the translate prompt constant to plain `Thought: …`; the grammar prompt (`_kGrammarInstructions`, Story 4.6) lists plain `Thought: …` too. The RU form `Мысль: …` was never italic. Today `*Thought:* …` is flagged **only by the same accident**, with a message that is wrong for it (there *is* a space).

**Decision (KseiPo, 2026-09-24), chosen from three options:** unflag all emphasized labels, **and** keep the retired italic monologue flagged under a **new dedicated error kind with an accurate message**. Rejected: (a) unflag `*Thought:*` entirely (loses the only signal on pre-2026-08-08 content); (b) exempt bold closers only (leaves every italic label — including the toolbar's own `_…_` — flagged with the wrong message).

## Acceptance Criteria

1. **(Emphasized labels are clean)** Given a line with an emphasized label whose colon sits inside the emphasis — bold or italic, `*` or `_` delimiters (including nested runs like `**_Role:_**`), at line start or mid-line, followed by a value or by end of line (`**Role:** …`, `**Селена:** …`, `**Secrets:**`, `_Note:_ …`) — when the matcher runs, then it yields no `malformedDialogue` token, and the emphasis token the error used to suppress is back (`matchConventions('**Role:** Previous keeper of Saltmere Light.')` is exactly `[ConventionToken(0, 9, ConventionKind.bold)]`).
2. **(Real missing spaces are still flagged)** Given a genuinely missing space — `Frank:hello`, `Frank:**hello**`, `Frank:_hello_`, `*Note:*text`, or `**Role:**value` (nothing between the closing emphasis and the value) — when the matcher runs, then it is still `malformedDialogue`; and every existing guard is unchanged: digits (`12:30`, `Ratio 3:1`), `/` and URLs (`http://…`, `See [link](http://x) here`), and the single-symbol emoticon guard (`>:( face`).
3. **(The retired italic monologue gets its own, accurate finding)** Given a line that starts (after optional spaces/tabs) with `*Thought:*` or `_Thought:_`, or the RU mirror `*Мысль:*` / `_Мысль:_` — case-insensitive, optionally with an emotion inside the emphasis (`*Thought (tired):*`), followed by whitespace or end of line — when I lint the file, then it is reported as the new error kind `ConventionKind.italicMonologue` with the message ``Inner monologue is plain `Thought:` / `Мысль:` — the italic form is retired.``, never as a missing space. Plain `Thought: …` / `Мысль: …` stay valid (`dialogueSpeaker`, no finding). Bold `**Thought:**` was never a convention and is out of scope (just bold, no finding).
4. **(Matcher invariants hold)** Given the changed `_malformedDialogue` and the new pattern, when this story ships, then both stay linear (ReDoS-safe: bounded quantifiers / negated classes, no nested unbounded quantifiers); `_dialogue`, `_malformedDialogue`, and the new pattern are mutually exclusive on the same colon; and `matchConventions`'s sorted, non-overlapping, CRLF-safe, never-throws contract (AD-8) is unchanged.
5. **(Regression coverage)** Given `test/lore/convention_matcher_test.dart` and `test/lore/convention_lint_test.dart`, when this story ships, then they cover AC1-AC4 — including the full `mira.md` card linting clean — and the whole existing suite (788 tests at baseline) stays green.

**Non-goals** (explicitly out of scope):
- No new check for a bold or italic *speaker* (`**Селена:** Привет.` is no longer flagged; it just loses the dialogue highlight — ARCHITECTURE §3.3's dialogue form is plain `Name (emotion): phrase.`). Whether non-plain speakers deserve their own finding is a separate, undecided question.
- No change to `_dialogue`, to `**Role**: value` being highlighted as a `dialogueSpeaker`, or to list items (`- **Role:** value` stays clean via `listMarker`).
- No modelling of `__bold__` as `bold` (the matcher recognizes only `**…**`); AC1 only requires such labels to produce no error.
- No change to the preview (`previewConventionKinds` never included `malformedDialogue`; `italicMonologue` stays out for the same reason — an authoring-time, line-anchored signal).
- No JS reference / golden-fixture change: `convention_matcher.dart` has no JS twin.
- `_bmad-output/project-context.md` line 191 (stale `*Thought:*`) is **not** edited here — it is already fixed on `main` by the parallel "Prose rules documentation" session (coordinated 2026-09-24), and will arrive when this branch syncs with `main`.

## Tasks / Subtasks

- [x] **Task 1: Narrow `_malformedDialogue`** (AC: 1, 2, 4)
  - [x] 1.1 In `apps/mobile/lib/lore/convention_matcher.dart`, append the negative lookahead `(?![*_]{1,3}(?:\s|$))` after the existing `(?=[^\s/])`:
    ```dart
    final RegExp _malformedDialogue = RegExp(
        r'^[ \t]*[^\s:.!?\[\d][^\n:.!?\d]{1,39}?(?:\s*\([^)\n]*\))?[ \t]*:(?=[^\s/])(?![*_]{1,3}(?:\s|$))');
    ```
    Rule: a colon immediately followed by a closing emphasis-delimiter run (1-3 of `*`/`_`, mixed allowed — `**_Role:_**` closes with `_**`) and then whitespace or end of line is the end of an emphasized label, not a missing space. A closer followed by anything else (`**Role:**value`) is still flagged. Leave the prefix untouched.
  - [x] 1.2 Extend the pattern's comment block with a `(Story 5.5)` paragraph: the rule, why (profile labels, ARCHITECTURE §3.2b), the accepted residual (an opener-less `Frank:** hi` is not flagged — the lookahead doesn't check that the run closes a real opener; implausible in prose, not worth a backreference), and that exclusivity with `_dialogue` still holds (this only narrows `(?=[^\s/])`, itself disjoint from `_dialogue`'s `(?=\s|$)`).
- [x] **Task 2: Add the `italicMonologue` error kind** (AC: 3, 4)
  - [x] 2.1 `ConventionKind`: add `italicMonologue` after `unpairedConditional`, under its own comment (`// Error kind (Story 5.5) — the retired italic inner-monologue form …`).
  - [x] 2.2 Add it to `errorKinds`.
  - [x] 2.3 New pattern beside `_malformedDialogue`, with a comment (decision + date, both delimiters, the optional emotion, case-insensitivity, why `(?=\s|$)` keeps it disjoint from `_malformedDialogue`):
    ```dart
    final RegExp _italicMonologue = RegExp(
        r'^[ \t]*[*_](?:Thought|Мысль)(?:\s*\([^)\n]*\))?[ \t]*:[*_](?=\s|$)',
        caseSensitive: false);
    ```
    Single delimiter on each side only — `[*_]` then the keyword means `**Thought:**` can't match (the 2nd char is `*`, not `T`). The delimiters needn't match each other (`*Thought:_` is a malformed attempt at the same retired form; flagging it is more useful than letting it pass). Case-insensitive Cyrillic works in Dart's non-unicode mode — `_condOpen` already relies on it and its test proves it. **Don't use `\b`** (ASCII-only in Dart — Story 3.1's finding); the `:` after the keyword/emotion already bounds the word (`*Thoughts:*` can't match).
  - [x] 2.4 `_matchLine`: after the `badDlg` block, `matchAsPrefix` the new pattern and add a `ConventionToken(0, m.end, ConventionKind.italicMonologue)` candidate — the token spans the whole emphasized label including both delimiters (`*Thought:*` → `[0, 10)`).
  - [x] 2.5 `_priority`: `case ConventionKind.italicMonologue: return 5;` — same slot as `malformedDialogue`/`dialogueSpeaker`. Comment: mutually exclusive with both on the same colon by construction; in the one pathological overlap (a colon *inside* the emotion parens, e.g. `*Thought (a: b):* x`, where `_dialogue`/`_malformedDialogue` stop at the inner colon), all three start at 0 and the existing longer-first tie-break keeps `italicMonologue`, whose span always extends past the closing delimiter. Also update the existing `malformedDialogue` case comment to mention the new kind.
- [x] **Task 3: The two exhaustive consumers** (AC: 3)
  - [x] 3.1 `apps/mobile/lib/lore/convention_lint.dart` `_messageFor`: `case ConventionKind.italicMonologue: return 'Inner monologue is plain `Thought:` / `Мысль:` — the italic form is retired.';` (use a single-quoted Dart string; the message contains backticks, not single quotes). Place it after the `unpairedConditional` case.
  - [x] 3.2 `apps/mobile/lib/app/convention_styles.dart` `styleForConvention`: add `case ConventionKind.italicMonologue:` to the shared error-style group. No change to `previewConventionKinds`.
  - [x] 3.3 There are exactly three exhaustive `switch`es over `ConventionKind` (`_priority`, `_messageFor`, `styleForConvention` — confirmed by grep); `flutter analyze` failing on a missed one is the safety net. `convention_highlighting_controller.dart` applies `ConventionKind.values`, so the editor squiggle is automatic.
- [x] **Task 4: Matcher tests** — `apps/mobile/test/lore/convention_matcher_test.dart`, new groups placed after `'matchConventions — malformed dialogue (Story 3.1, FR18)'` (AC: 1, 2, 3, 4, 5)
  - [x] 4.1 Group `'matchConventions — emphasized labels are not malformed dialogue (Story 5.5)'`:
    - exact tokens for the report: `'**Role:** Previous keeper of Saltmere Light.'` → `[ConventionToken(0, 9, bold)]`; `'**Селена:** Привет.'` → `{bold}`;
    - end of line + CRLF: `'**Secrets:**'` → `[ConventionToken(0, 12, bold)]`; `'**Secrets:**\r\n- Knew the Light burns memories.'` → `{bold, listMarker}`;
    - italic/underscore/nested closers: `'*Note:* see arc.md'` → `{italic}`; `'_Note:_ see arc.md'` → `{italic}`; `'**_Role:_** value'` → `{bold}`; `'__Role:__ value'` and `'***Role:*** value'` → no error kinds (`.where(isError)` empty — the matcher doesn't model `__bold__`/bold-italic);
    - other shapes the old pattern tripped on: `'**Voice / writing style:** Terse, precise.'`, `'**Age:** 42'`, `'  **Indented:** value'` → `{bold}`; `'Note that **the key:** matters'` → `{bold}`;
    - genuine misses still flagged: `'**Role:**value'`.first == `ConventionToken(0, 7, malformedDialogue)`; `'Frank:**hello**'`, `'Frank:_hello_'` contain `malformedDialogue`; `'*Note:*text'` → `{malformedDialogue}`; `'*Thought:*text'` → exactly `{malformedDialogue}` (disjoint from `italicMonologue`);
    - ReDoS guard: `'ab:${'*' * 50000}'`, `'**ab:${'_' * 50000}x'`, `'*Thought (${'x' * 50000}'`, `'*Thought${' ' * 50000}x'`, `'_${'_' * 50000}:'` all finish well under the file's existing 500 ms bound.
  - [x] 4.2 Group `'matchConventions — retired italic inner monologue (Story 5.5)'`:
    - `'*Thought:* She knew.'` → exactly `[ConventionToken(0, 10, italicMonologue)]`; `isError(italicMonologue)` and `errorKinds.contains(...)`;
    - `'_Thought:_ She knew.'`, `'*Мысль:* Она знала.'`, `'*Thought (tired):* Not again.'`, `'*Мысль (устало):* Опять.'`, `'*Thought:*'` (end of line), `'*Thought:*\r\nnext'` (CRLF) → `{italicMonologue}`;
    - case-insensitive: `'*thought:* x'`, `'*МЫСЛЬ:* x'` → `{italicMonologue}`;
    - the current plain form stays valid: `'Thought: She knew.'`.first == `ConventionToken(0, 8, dialogueSpeaker)`; `'Мысль (устало): Опять.'` → `{dialogueSpeaker}`;
    - only the retired shape: `'**Thought:** x'` → `{bold}`; `'*Thoughts:* x'` → `{italic}`; mid-line `'He had one *thought:* only.'` → no error kinds.
  - [x] 4.3 Assert kinds via the `ConventionKind` enum (never literal kind-name strings — Story 2.15's review gap: an enum rename is a compile error only where the enum is named).
- [x] **Task 5: Linter tests** — `apps/mobile/test/lore/convention_lint_test.dart`, new group `'lintText — emphasized labels and the retired italic monologue (Story 5.5)'` before the `LintFinding` group (AC: 1, 3, 5)
  - [x] 5.1 The full `lore/characters/mira.md` card (inline `const` copy of the file, noted as a copy) → `lintText(card)` is empty (5 findings before this story).
  - [x] 5.2 `lintText('**Role:** Previous keeper.')` is empty; `lintText('**Role:**value')` → a single `malformedDialogue` finding.
  - [x] 5.3 `'Intro.\n*Thought:* She knew.\nThought: plain is fine.'` → exactly one finding: line 2, `italicMonologue`, message contains `` `Thought:` ``, and the message differs from the `malformedDialogue` one (compare against `lintText('Frank:hello').single.message`, not a hardcoded string).
- [x] **Task 6: Doc sync** (AC: 3)
  - [x] 6.1 `ARCHITECTURE.md` §3.3, the inner-monologue bullet (line 231): add that it is plain, not italic — the earlier `*Thought:* …` form is retired (2026-08-08) and the linter flags it. Touch only that bullet (the parallel Story 5.7 edits the "Authoring conditionals" bullet of the same list).
- [x] **Task 7: Gates**
  - [x] 7.1 `flutter analyze` clean; `flutter test` full suite green (baseline 788).
  - [x] 7.2 Contract git-clean: `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` prints nothing (`npm test` is only required if that gate is dirty — this story touches no JS).

### Review Findings

Code review 2026-09-25, cross-model: implemented on Opus 5.5, all three layers run on Sonnet 5 (a first launch on Fable 5.1 failed on usage credits). Result: 5 patch, 0 decision-needed, 0 defer, 1 dismissed (the Acceptance Auditor's note that the ReDoS inputs were split across two groups — already disclosed in the Completion Notes, coverage equivalent). The auditor found AC1-AC5 met.

- [x] [Review][Patch] The closer exemption doesn't check that an emphasis opened before the colon, so a real missing space followed by an emphasis run and a space passes: `Frank:* sighs heavily* Look.`, `Selena:** frowns** Careful.`, `Note:_ дальше_ …`, and the comment's own "accepted" `Frank:** hi` all yield no finding [apps/mobile/lib/lore/convention_matcher.dart:130]
- [x] [Review][Patch] The retired form followed by punctuation instead of a space (`*Thought:*, she thought`, `*Мысль:*.`) falls through to `malformedDialogue` — the "missing a space" message AC3 rules out [apps/mobile/lib/lore/convention_matcher.dart:146]
- [x] [Review][Patch] A label whose closer is followed by punctuation (`**Role:**, value`, `**Role:**.`, `(**Note:**) aside`) is still the AC1 false positive [apps/mobile/lib/lore/convention_matcher.dart:130]
- [x] [Review][Patch] Closer runs of 4+ delimiters (`****Role:**** value`, `**__Role:__** value`) are still the AC1 false positive; the `{1,3}` cap isn't documented as a residual — and a doubled `****` is exactly what pressing Bold on a label produced while the old bug hid the bold token [apps/mobile/lib/lore/convention_matcher.dart:130]
- [x] [Review][Patch] The retired form with a mismatched closer count (`*Thought:** value`, `*Thought:**`) produces no finding at all — plain italic [apps/mobile/lib/lore/convention_matcher.dart:146]

## Dev Notes

### Current state → change → must preserve (files read in full)

- **`lib/lore/convention_matcher.dart`** (AD-7 keystone, pure Dart, AD-9). `_matchLine` runs three anchored line-start patterns (`_listMarker`, `_dialogue`, `_malformedDialogue`) via `matchAsPrefix`, collects inline/error candidates, then `_resolveOverlaps` keeps by `(_priority, start, longer-first)` using a `covered` bitmap. **Change:** one lookahead appended to `_malformedDialogue`; one new pattern + candidate; enum/errorKinds/`_priority` entries. **Preserve:** `_dialogue` untouched; the Story 3.1 review-fix exclusions (digits in the prefix class and after the colon, `/` after the colon, the ≥2-char prefix); the cross-line conditional pass (`_condOpen`/`_condClose` — the parallel Story 5.7 edits those; don't touch them); every existing comment's claims must stay true (update the exclusivity comments you affect).
- **`lib/lore/convention_lint.dart`** — wraps every `isError` token as a `LintFinding(line, kind, _messageFor(kind))`; never reimplements detection (AD-7). **Change:** one `_messageFor` case. **Preserve:** detection stays in the matcher — no `Thought`-specific logic in the linter.
- **`lib/app/convention_styles.dart`** — one style map for editor + preview; all error kinds share the wavy `scheme.error` style (`test/app/convention_styles_test.dart:18` iterates `errorKinds`, so it covers the new kind automatically). **Change:** one grouped `case`.

### Why these exact regexes are safe

- `_malformedDialogue`'s new lookahead is bounded (`{1,3}` then one char / end) and evaluated once per anchored attempt — O(1) added; the probe timed the old and new patterns identically on 50 000-char adversarial lines.
- `_italicMonologue` has a fixed-literal head (no lazy prefix loop), one optional emotion group, and `[ \t]*`; worst case is O(line length) for one anchored attempt (e.g. an unterminated `(`), the same bound `_dialogue` already has.
- Mutual exclusivity on the same colon: `_dialogue` needs `(?=\s|$)` after the colon; `_malformedDialogue` needs a non-space that is not a closer-run-plus-space; `_italicMonologue` needs a closer delimiter right after the colon and then whitespace/end. Pairwise disjoint.
- Dart `RegExp` defaults (`multiLine: false`): `$` is end of the matched line string; a CRLF line keeps its trailing `\r`, which `\s` matches — so `**Secrets:**\r` and `*Thought:*\r` behave like their LF forms.

### Previous story intelligence

- **Story 3.1** (origin of `malformedDialogue`): its cross-model review found the URL/time/ratio false positives by *live probes*, and the implementer found the `>:(` emoticon and the Dart-`\b`-is-ASCII-only traps by failing tests — verify regex behavior by running it, never by reading it. Precision over recall is this file's standing tradeoff.
- **Story 2.15**: a test that asserts via literal strings instead of the enum escaped a rename — always name `ConventionKind.x`.
- **Story 5.4**: cross-model review (implemented on one model, reviewed on another) found real defects again; baseline suite was 788 and must stay green.

### Git intelligence

- The matcher/lint/styles files were last touched by Stories 3.1/3.2 (`7ad39fe`, `8f2806e`); Epic 5 so far (`19c62e3`…`f7cd977`) never touched them — no drift to reconcile. One commit per story on a `story/5-5-…` branch, ff-merged into local `main`, never pushed.
- **Parallel work (coordinated with the "Prose rules documentation" session, 2026-09-24):** Stories 5.6/5.7 are landing on `main` concurrently. 5.7 edits `_condOpen`/`_condClose` (and their comment block), the `unpairedConditional` message in `_messageFor`, conditional tests in `convention_matcher_test.dart`, ARCHITECTURE §3.3's conditionals bullet, and `project-context.md`. Expect small textual conflicts when syncing — near `_messageFor`'s `unpairedConditional` case and the test-file group boundary — resolve by keeping both sides. Sync with `main` before the final ff-merge.

### Latest tech information

No new dependency, API, or SDK feature. Dart 3.12.2 / Flutter 3.44.7 `RegExp` (ECMAScript semantics): lookahead / negative lookahead, bounded quantifiers, and `caseSensitive: false` with Cyrillic are all already used in this file.

### Testing standards

Business-logic tests only (`_bmad-output/project-context.md` → Testing emphasis): pure `matchConventions` / `lintText` unit tests; no widget tests (the editor squiggle and toolbar state are derived from these same tokens).

### Project Structure Notes

- Modified: `apps/mobile/lib/lore/convention_matcher.dart`, `apps/mobile/lib/lore/convention_lint.dart`, `apps/mobile/lib/app/convention_styles.dart`, `apps/mobile/test/lore/convention_matcher_test.dart`, `apps/mobile/test/lore/convention_lint_test.dart`, `ARCHITECTURE.md` (one bullet). Planning: `_bmad-output/planning-artifacts/epics.md`, `_bmad-output/implementation-artifacts/sprint-status.yaml`, this file.
- No new files. No `lore/` slice export change (`lore.dart` already exports both files). No UI file beyond the one style `case`.
- **Follow-up outside this commit:** `docs/agent-writing-rules.md` (untracked in this branch; lands on `main` via Stories 5.6/5.7) currently tells external agents to avoid `**Type:** value` because of this false positive — update its §5.1 and §10 (and the §6.1/§6.2 lines that repeat the claim) after syncing with `main`.

### References

- [Source: apps/mobile/lib/lore/convention_matcher.dart#L80-114] — `_dialogue` / `_malformedDialogue` and the Story 3.1 review-fix rationale.
- [Source: apps/mobile/lib/lore/convention_matcher.dart#L285-344] — `_matchLine` candidate collection.
- [Source: apps/mobile/lib/lore/convention_matcher.dart#L352-432] — `_priority` / `_resolveOverlaps`.
- [Source: apps/mobile/lib/lore/convention_lint.dart#L84-109] — `_messageFor`.
- [Source: apps/mobile/lib/app/convention_styles.dart#L19-57] — `styleForConvention`'s error group.
- [Source: apps/mobile/lib/app/editor_toolbar.dart#L209-234, #L452, #L505-512] — bold/italic active state reads the matcher's tokens; the italic button wraps with `_`.
- [Source: lore/characters/mira.md] — the sample card with five false findings.
- [Source: ARCHITECTURE.md#3.2b, #3.3] — profile block; inner monologue `Мысль: …` / `Thought: …`.
- [Source: apps/mobile/lib/ai/translate_action.dart#L60-73, apps/mobile/lib/ai/grammar_action.dart#L66-77] — prompt constants using plain `Thought: …`.
- [Source: _bmad-output/implementation-artifacts/3-1-lint-a-file-for-convention-errors.md] — AC2's "narrow, conservative" mandate and review history.
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-7, AD-8, AD-9] — one matcher, total, pure.
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR9a, FR18] — highlighter error style and the linter.
- [Source: _bmad-output/planning-artifacts/epics.md#Story 5.5] — the epic-level ACs this file expands.

## Dev Agent Record

### Agent Model Used

Claude Opus 5.5

### Debug Log References

- Baseline before any change: `flutter test` 788/788 green.
- Task 1 red: the new "emphasized labels" group plus the first two lint tests failed exactly as predicted. That was 6 failures (4 matcher, 2 lint), e.g. `Expected: [ConventionToken(0, 9, bold)] Actual: [ConventionToken(0, 7, malformedDialogue)]`. The missing-space and ReDoS guard tests already passed. Green after the one-lookahead change: 79/79 in the two files.
- Tasks 2-3 red: the "retired italic inner monologue" group and the lint message test failed to compile (`Member not found: 'italicMonologue'`). Green after the enum, pattern, candidate, and priority changes plus the two consumer cases: 95/95 across the matcher, lint, and styles test files. `convention_styles_test.dart`'s "all error kinds share the distinct wavy error style" iterates `errorKinds`, so it now covers the new kind too.
- Probe (`dart run --packages=apps/mobile/.dart_tool/package_config.json`, scratchpad script): I re-ran the 44-line edge-case corpus against the fixed matcher, and every line behaves as the story specifies. `matchConventions` over the adversarial set took 64 ms after the change and 63 ms before.
- Probe: Dart normalizes a CRLF source file's line breaks to `\n` inside a `'''` multi-line literal (`[97, 10, 98]`). The inline `mira.md` copy is therefore LF on every checkout, and the CRLF variant has to be built explicitly (Completion Notes).
- Final gates: `flutter analyze` reports "No issues found!"; `flutter test` passes 804/804 (+16); the contract gate (`git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart`) is empty; `npm test` passes 4/4.

**Review-fix round (2026-09-25):**

- A triage probe reproduced all 5 patch findings against the current matcher. It compared the old and new pattern pairs over the review's inputs plus the original corpus.
- An exhaustive disjointness check covered 444,440 generated lines. It found 4 overlaps, all a colon inside emotion parens (`*Thought(:):*`): the patterns match at different colons, the existing longer-first tie-break resolves it, and the old pair behaves the same way.
- Adversarial 100k-character lines take 96 ms for both new patterns.
- Red: the 3 new review-fix tests failed. Green: 178/178 across `test/lore/` and the styles test.
- `flutter analyze` flagged `prefer_interpolation_to_compose_strings` on the `+` concatenations, so I switched to adjacent literals (raw regex text plus an interpolated `_afterCloser`).
- Final: analyze reports "No issues found!"; `flutter test` passes 807/807 (+3); the contract gate is empty; `npm test` passes 4/4.
- Probe note: `dart run` on a script that imports the `lore.dart` barrel crashes the VM's FFI transformer (a toolchain issue, not ours). Import `lore/convention_matcher.dart` directly, as the dev-story probes did.

### Completion Notes List

- **`_malformedDialogue`** got one appended negative lookahead, `(?![*_]{1,3}(?:\s|$))`. A colon followed by a closing emphasis run and then whitespace or end of line ends an emphasized label; it isn't a missing space. The prefix, the Story 3.1 digit, `/`, and minimum-length guards, and `_dialogue` are all untouched. `**Role:**value` is still flagged. The accepted residual is documented in the pattern comment: an opener-less `Frank:** hi` passes, because the lookahead doesn't check for an opener.
- **New error kind `ConventionKind.italicMonologue`** (added to `errorKinds`). The pattern is `^[ \t]*[*_](?:Thought|Мысль)(?:\s*\([^)\n]*\))?[ \t]*:[*_](?=\s|$)` with case-insensitive matching. The token spans the whole emphasized label (`*Thought:*` → `[0, 10)`). The lint message is "Inner monologue is plain `Thought:` / `Мысль:` — the italic form is retired." The editor shows it with the shared error squiggle, and it is not added to `previewConventionKinds`.
- **`_priority`**: `italicMonologue` shares slot 5 with `dialogueSpeaker`/`malformedDialogue`. I replaced the old `malformedDialogue` comment, which claimed "never actually competes in practice" and wasn't accurate for a colon inside the emotion parens (`Frank (a:b): hi`, a pre-existing case). The new comment is one shared-slot comment explaining the only overlap, a colon inside the emotion parens, and how the longer-first tie-break resolves it.
- **Beyond the task text** (in scope, noted for review):
  - The ReDoS inputs are split by the pattern they target. The closer-lookahead inputs sit in the labels group; the monologue inputs sit in the monologue group, plus one extra `'_Мысль' + '\t' * 50000 + ':'`.
  - One added test, `'*Thought (a: b):* x'` → exactly `[ConventionToken(0, 17, italicMonologue)]`, proves the tie-break claim in the `_priority` comment.
  - The `mira.md` lint test also asserts a CRLF copy of the card, since files authored on Windows arrive byte-for-byte via Syncthing.
- **ARCHITECTURE.md §3.3**: only the inner-monologue bullet changed. It now says the form is plain, not italic; the earlier `*Thought:*` form is retired (2026-08-08); and the linter flags it. The conditionals bullet is left alone because parallel Story 5.7 edits it.
- **Not done here, by design:** `_bmad-output/project-context.md:191` is already fixed on `main` by the parallel session. The `docs/agent-writing-rules.md` updates wait until this branch has synced with `main`, where that file lands.
- **Review-fix round.** The review had 5 patch findings, all applied. Two rules changed, and both patterns now share one follower set, `_afterCloser`: whitespace, closing punctuation (`.,;!?)]"»”’…—–`), or end of line. A different set in each pattern is what let `*Thought:*, …` fall between them.
  - **`_malformedDialogue`**: the exemption now reads `(?!(?<=[*_][^\n]*:)[*_]+` + `_afterCloser` + `)`. The closer run has any length, which fixes `****Role:****`. The closer may be followed by punctuation, which fixes `**Role:**,` and `(**Note:**)`. A new lookbehind requires an opener delimiter before the colon. Because of it, a real missing space followed by an emphasis run is flagged again (`Frank:* sighs* …`, `Frank:** hi`), which also retires the "opener-less passes" residual the first version accepted. The new accepted residual is documented in the comment: the lookbehind can't tell whether that opener is still open (`_Note_ Frank:* hi` passes).
  - **`_italicMonologue`**: the closer is now `[*_]+` followed by `_afterCloser`. That catches `*Thought:*, …`, `*Мысль:*.`, and `*Thought:** value`. The two patterns stay exact complements on the colon.
  - Tests: +3 (two in the labels group, one in the monologue group), plus two extra ReDoS inputs: the lookbehind's worst case, and a long closer run after the monologue colon.
- AC check. **AC1**: the labels group and `mira.md` lints clean with both LF and CRLF. **AC2**: the missing-space test, plus the Story 3.1 URL, time, ratio, and emoticon tests still green. **AC3**: the monologue group and the lint message test. **AC4**: the ReDoS guards, the disjointness assertions (`*Thought:*text` → `{malformedDialogue}` only), the tie-break test, and the existing sorted, non-overlapping, CRLF, and never-throws tests. **AC5**: +16 tests, 804/804.

### File List

- `apps/mobile/lib/lore/convention_matcher.dart` (modified: `_malformedDialogue` emphasized-label exemption with opener lookbehind; shared `_afterCloser` follower set; new `ConventionKind.italicMonologue`, `errorKinds` entry, `_italicMonologue` pattern, `_matchLine` candidate, `_priority` case and shared-slot comment)
- `apps/mobile/lib/lore/convention_lint.dart` (modified: `_messageFor` case)
- `apps/mobile/lib/app/convention_styles.dart` (modified: `styleForConvention` error-group case)
- `apps/mobile/test/lore/convention_matcher_test.dart` (modified: two new Story 5.5 groups, 16 tests)
- `apps/mobile/test/lore/convention_lint_test.dart` (modified: new Story 5.5 group, 3 tests)
- `ARCHITECTURE.md` (modified: §3.3 inner-monologue bullet)
- `_bmad-output/planning-artifacts/epics.md` (modified: Story 5.5 entry and both "Stories so far" lines)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (modified: `5-5-…` entry, `last_updated`)
- `_bmad-output/implementation-artifacts/5-5-stop-flagging-emphasized-labels-as-malformed-dialogue.md` (new: this story file)

## Change Log

- 2026-09-24 — Story created (create-story): false positive verified by probe, `*Thought:*` handling decided with KseiPo (own error kind + accurate message).
- 2026-09-24 — Implemented (dev-story):
  - `_malformedDialogue` no longer reads a closing emphasis delimiter as a missing space, so profile labels like `**Role:** …` lint clean and their bold token is back.
  - The retired italic monologue (`*Thought:*` / `_Thought:_` / `*Мысль:*`) is its own error kind, `italicMonologue`, with an accurate message.
  - ARCHITECTURE §3.3 notes the retirement.
  - `flutter analyze` is clean; `flutter test` passes 788 → 804; the contract gate is clean; `npm test` passes 4/4.
- 2026-09-25 — Code review (cross-model: implemented on Opus 5.5; Blind Hunter, Edge Case Hunter, and Acceptance Auditor all on Sonnet 5). The auditor found AC1-AC5 met. 5 patch findings, all applied:
  - The emphasized-label exemption now requires an opener before the colon, accepts closer runs of any length, and accepts punctuation after the closer.
  - The italic-monologue closer mirrors it through one shared follower set.
  - 1 finding dismissed (the ReDoS test placement, already disclosed).
  - `flutter analyze` is clean; `flutter test` passes 804 → 807; the contract gate is clean; `npm test` passes 4/4.
- 2026-09-25 — Marked done.
