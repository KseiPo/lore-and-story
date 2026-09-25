---
baseline_commit: 9c8facc4a58abdfcd0aa30b155c820de43435e42
---

# Story 5.7: Translate emotions and conditional keywords, and lint English conditionals

Status: ready-for-dev

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want English files to use English conditional keywords and translated emotions — produced by the app's AI translation and checked by the linter,
so that an English scene reads fully in English while keeping the authoring conventions intact.

## Context

**Decisions (KseiPo, 2026-09-24):** two translation conventions change.

1. **Conditional keywords are translated.**
   - Russian: `— если <condition> — … — иначе — … — конец условия —`
   - English: `— if <condition> — … — else — … — end if —`

   KseiPo chose `if / else / end if` over the literal
   `if / otherwise / end of condition`.
2. **A dialogue line's emotion is translated** along with the name and the phrase:
   `Селена (спокойно): …` → `Selena (calmly): …`.

**What the app does today, in three places:**

- **Translate prompt defaults** (`apps/mobile/lib/ai/translate_action.dart`,
  `_kConventionsRuToEn` / `_kConventionsEnToRu`, Stories 4.3/4.4/4.5):
  - The dialogue line tells the model "Keep this exact shape; translate only the
    name and the phrase", so the emotion stays in the source language.
  - The conditionals line tells it to "preserve the em-dash markers and translate
    only the human-readable text between them", so the Russian keywords stay.
- **Convention matcher** (`apps/mobile/lib/lore/convention_matcher.dart`,
  `_condOpen` / `_condClose`, Story 3.1): recognizes only `— если … —` and
  `— конец условия —`. English markers are never pair-checked by the linter,
  whose finding message also names only the Russian keywords.
- **Grammar-review default instructions** (`apps/mobile/lib/ai/grammar_action.dart`,
  `_kGrammarInstructions`, Story 4.6): list only the Russian markers as intentional
  markup. An English file's `— if … — end if —` could therefore be flagged as a
  prose error, which is exactly what that list exists to prevent.

**This intentionally supersedes one pinned test.** `translate_action_test.dart`'s
test "(Review decision, 2026-08-08, AC5) the RU→EN conventions default is
byte-for-byte the same text Story 4.3/4.4 shipped" pins the old text exactly. That
pin protected against *accidental* drift. This story is a deliberate, owner-approved
convention change, so the test is **updated to pin the new text**, not deleted and
not treated as a regression (the same handling as Story 2.19's superseded test). The
constant's own doc comment claims the same byte-for-byte identity and must be
reworded too.

**Out of scope:**
- The `ai-prompts.md` override mechanism (Story 4.4) is unchanged. An author-supplied
  `# Conventions` section still wins over these defaults, so an author who has one
  updates its text themselves.
- No in-repo migration of existing English files that still carry Russian markers.
  The author runs the regexes below (Story 2.15 precedent).
- No highlighter styling for paired markers. Paired conditional markers are not a
  token kind today (only unpaired ones are), and that stays.

### Migration regexes (deliver these to KseiPo; not implementation work)

Run them on `*.en.md` files only. Case-insensitive (VS Code: leave "Match Case"
off, since a capitalized «Если» becomes «if»). Three passes, in any order:

```
Find:    —(\s*)если(\s)
Replace: —$1if$2

Find:    —(\s*)иначе(\s*)—
Replace: —$1else$2—

Find:    —(\s*)конец(\s+)условия(\s*)—
Replace: —$1end$2if$3—
```

The old prompt already translated the condition and branch text in English files,
so only the keywords need replacing. Emotions left in Russian by the old prompt
(`Selena (спокойно):`) are not mechanically fixable; re-translate or edit those by
hand.

## Acceptance Criteria

1. **(English conditionals are recognized, FR18)** Given an English conditional (an
   `— if <condition> —` opener and an `— end if —` closer, case-insensitive, with
   `if` a whole word followed by whitespace), when the matcher runs, then it pairs
   and flags unpaired markers exactly like the Russian ones:
   - the same `ConventionKind.unpairedConditional` token (no new kind);
   - the same file-level gate (no findings at all unless the text contains at
     least one closer, in either language);
   - the same opener limits (one line, condition ≤ 300 chars, no `[`/`]` in the
     condition);
   - the same stack pairing and the same overlap handling.

   Russian behavior is byte-for-byte unchanged: every existing test in the
   "unpaired conditional markers" group passes untouched.
2. **(Word boundary on `if`)** Given English prose where "if" is only a prefix
   (`— iffy —`, `— ifs and buts —`), when the matcher runs in a file that has a
   closer, then no opener is recognized there.
3. **(Lint message)** Given an unpaired-conditional finding, when the linter lists
   it, then the message names both keyword sets:
   `Em-dash conditional marker («если» / «конец условия», or «if» / «end if») has no matching counterpart.`
4. **(Translate defaults, FR21/FR30)** Given no `ai-prompts.md` `# Conventions`
   override, when a translation runs, then the conventions text instructs:
   - in either direction, translate the dialogue **emotion** together with the name
     and the phrase, keeping the `Name (emotion): phrase.` shape;
   - **RU→EN:** convert the conditional keywords
     (`если` → `if`, `иначе` → `else`, `конец условия` → `end if`);
   - **EN→RU:** convert them the reverse way;
   - in both directions, keep the em-dash marker shape and translate the condition
     and branch text.

   The exact texts are in Dev Notes. Every other line of both constants is unchanged.
5. **(Grammar defaults, FR23)** Given no `# Grammar Instructions` override, when a
   review runs, then the intentional-markup list names both the Russian and the
   English conditional markers.
6. **(Docs)** Given the convention change, when this ships, then these document the
   English keywords and the translated-emotion rule:
   - ARCHITECTURE.md §3.3 (the Dialogue and Authoring conditionals bullets);
   - `_bmad-output/project-context.md` (scene conventions);
   - `docs/agent-writing-rules.md` (§4.1, §6.7, §10).

## Tasks / Subtasks

- [ ] **Task 1: Matcher — English conditional markers** (AC: 1, 2)
  - [ ] 1.1 In `apps/mobile/lib/lore/convention_matcher.dart`, widen the two
        patterns by adding alternatives. Do not add new patterns or new passes:
        ```dart
        final RegExp _condOpen = RegExp(
            r'—\s*(?:если|if(?=\s))[^—\n\[\]]{1,300}—', caseSensitive: false);
        final RegExp _condClose = RegExp(
            r'—\s*(?:конец\s+условия|end\s+if)\s*—', caseSensitive: false);
        ```
        `(?=\s)` is the word boundary for `if`. Don't use `\b`: Story 3.1
        documented that Dart's `\b` is ASCII-only, and using it for the English
        branch alone would be inconsistent. A lookahead needs no boundary class at
        all. Both patterns stay linear: a two-way literal alternation and the same
        bounded negated class.
  - [ ] 1.2 Leave `_matchConditionalMarkers` alone. The gate
        (`_condClose.hasMatch`), the adjacency dedupe, the LIFO stack and the
        unpaired-token emission already work per match. Pairing is
        language-agnostic by design: an opener in one language closed in the other
        counts as paired. Author files are single-language, so this can't hide a
        real mistake, and it keeps the code free of language bookkeeping. Say so in
        the doc comment.
  - [ ] 1.3 Update the comments that name only the Russian form:
        - the `ConventionKind.unpairedConditional` enum comment (currently
          "(`— если …` / `— конец условия —`)");
        - the large comment block above `_condOpen` (add the English form and the
          `(?=\s)` rationale; keep the existing false-positive and 300-char
          reasoning intact);
        - `_matchConditionalMarkers`'s doc comment.

        Credit the decision to KseiPo, 2026-09-24.
  - [ ] 1.4 **Do not touch** the enum values, `errorKinds`, `_priority()`, or any
        other pattern. Story 5.5 (in parallel, own branch) adds an
        `italicMonologue` kind and edits `_malformedDialogue`, so keeping this story
        inside the conditional block keeps the merge trivial.

- [ ] **Task 2: Lint message** (AC: 3)
  - [ ] 2.1 `apps/mobile/lib/lore/convention_lint.dart`, `_messageFor`: reword the
        `unpairedConditional` case to the exact AC3 string. Change no other case.
        Story 5.5 inserts a new case right after this one, so expect an adjacent-line
        merge.

- [ ] **Task 3: Translate prompt defaults** (AC: 4)
  - [ ] 3.1 `apps/mobile/lib/ai/translate_action.dart`: in **both**
        `_kConventionsRuToEn` and `_kConventionsEnToRu`, replace the dialogue line
        and the conditionals line with the exact texts in Dev Notes → "New
        conventions lines". Change no other line (inner monologue, placeholders,
        links, wikilinks, the `scene ⇄ passage` comment line).
  - [ ] 3.2 Update the doc comment above `_kConventionsRuToEn`. Today it says the
        constant "is byte-for-byte identical to what Story 4.3/4.4 shipped". Reword
        it: the text was deliberately changed in Story 5.7 (KseiPo, 2026-09-24:
        translated emotions and conditional keywords), and the per-direction fork
        and the shared `# Conventions` override scheme are unchanged.
  - [ ] 3.3 `AiPromptConfig`, `runTranslate` and the section layout stay unchanged;
        the preview still shows exactly what's sent (AD-11), just with the new text.

- [ ] **Task 4: Grammar defaults** (AC: 5)
  - [ ] 4.1 `apps/mobile/lib/ai/grammar_action.dart`, `_kGrammarInstructions`:
        replace the line
        ``- Em-dash conditional markers: `— если … — иначе … — конец условия —`.``
        with
        ``- Em-dash conditional markers: `— если … — иначе — … — конец условия —` in Russian and `— if … — else — … — end if —` in English.``
        Leave `_kResponseFormatContract` untouched; it is never overridable and not
        part of this change.

- [ ] **Task 5: Tests** (AC: 1–5)
  - [ ] 5.1 `apps/mobile/test/lore/convention_matcher_test.dart`: add an English
        subgroup (or tests) next to the existing "unpaired conditional markers"
        group, mirroring its Russian cases one-for-one:
        - a fully paired `— if the player knows Julia — text — else — other — end if —` → no finding;
        - no closer anywhere → no finding (the gate), including a literary aside
          `She would come — if he asked — and stay.`;
        - an unpaired opener when a closer exists elsewhere → exactly one token,
          spanning the English opener;
        - a stray `— end if —` → one token;
        - multi-line (opener line, text line, closer line) → paired;
        - case-insensitive (`— If … — END IF —`) → paired;
        - AC2: `— iffy —` / `— ifs and buts —` in a file with a closer are not openers;
        - a wikilink in an English condition → the opener isn't recognized and the
          closer is flagged (same bracket rule as Russian);
        - mixed: a Russian opener closed by `— end if —` → paired (documents the
          language-agnostic pairing decision).

        Keep every existing Russian test unchanged; they are AC1's regression proof.
  - [ ] 5.2 `apps/mobile/test/lore/convention_lint_test.dart`: an English
        unpaired-opener finding lands on its own line with kind
        `unpairedConditional`; the ARCHITECTURE-style English example produces no
        findings; and one assertion on the reworded message (the message is
        business output the author reads, not UI chrome).
  - [ ] 5.3 `apps/mobile/test/ai/translate_action_test.dart`:
        - update the byte-for-byte pinned RU→EN test to the new full text and
          retitle it `(Story 5.7) the RU→EN conventions default is exactly the text
          KseiPo approved on 2026-09-24` (see Context);
        - add `contains` assertions to the existing per-direction test for the
          EN→RU keyword mapping (`end if` → `конец условия`) and for the emotion
          wording in both directions.
  - [ ] 5.4 `apps/mobile/test/ai/grammar_action_test.dart`: next to the existing
        "(Review fix) … inner-monologue convention" test, assert that section 0
        contains `end if` (and `конец условия`).
  - [ ] 5.5 No UI presence tests (project testing emphasis).

- [ ] **Task 6: Docs** (AC: 6)
  - [ ] 6.1 `ARCHITECTURE.md` §3.3:
        - Dialogue bullet: add that a translation translates the name, the emotion
          and the phrase (example `Селена (спокойно): …` → `Selena (calmly): …`).
        - Authoring conditionals bullet: add the English form
          `— if … — else — … — end if —`, say that EN files use English keywords
          and translations convert them, and date it 2026-09-24. Story 5.5 edits
          the neighbouring inner-monologue bullet, so keep this edit to these two
          bullets.
  - [ ] 6.2 `_bmad-output/project-context.md`, "Scene file (plain-prose)
        conventions":
        - extend the Dialogue bullet with the emotion-translation rule;
        - add one bullet for conditionals (RU and EN forms, translated with the
          file; the linter checks both). The file has no conditionals bullet today.
  - [ ] 6.3 `docs/agent-writing-rules.md`:
        - §4.1: the Dialogue bullet already says to translate the emotion (keep it).
          Change the Conditionals bullet from "keep the markers" to "convert the
          keywords (если ↔ if, иначе ↔ else, конец условия ↔ end if), translate
          the condition and branch text".
        - §6.7: give both forms. Replace "The keywords stay in Russian in English
          files too" with "English files use `— if … — else — … — end if —`; the
          app checks both".
        - §10: the unpaired-conditional row covers either language.
        - Bump the "Last synced" date.

- [ ] **Task 7: Gates** (AC: all)
  - [ ] 7.1 `flutter analyze` clean and `flutter test` green, run from
        `apps/mobile` via PowerShell with
        `$env:PATH = "C:\programs\flutter\bin;" + $env:PATH`. Record before/after
        counts.
  - [ ] 7.2 `npm test` 4/4 at the repo root.
  - [ ] 7.3 Contract gate: `git status --porcelain lib/lore.js test/fixtures/
        scripts/ apps/mobile/lib/lore/lore_loader.dart
        apps/mobile/lib/lore/lore_model.dart` is **empty**.

## Dev Notes

### New conventions lines (exact text — AC4)

**`_kConventionsRuToEn`**:
- Replace line 1 (dialogue) with:
  ```
  - Dialogue lines are `Name (emotion): phrase.` — the emotion is optional. Keep this exact shape; translate the name, the emotion and the phrase.
  ```
- Replace line 6 (conditionals) with:
  ```
  - Em-dash conditional markers delimit authoring conditionals, not prose to render: Russian `— если <condition> — … — иначе — … — конец условия —` is English `— if <condition> — … — else — … — end if —`. Keep the em-dash marker shape; replace the keywords with the English ones (если → if, иначе → else, конец условия → end if) and translate the condition and branch text.
  ```

**`_kConventionsEnToRu`**:
- Line 1: the same dialogue line as above.
- Replace line 6 with:
  ```
  - Em-dash conditional markers delimit authoring conditionals, not prose to render: English `— if <condition> — … — else — … — end if —` is Russian `— если <condition> — … — иначе — … — конец условия —`. Keep the em-dash marker shape; replace the keywords with the Russian ones (if → если, else → иначе, end if → конец условия) and translate the condition and branch text.
  ```

The other six lines of each constant stay byte-identical. Mind the `\$` escape in
the placeholders line if you retype it; better to edit only the two lines.

### Current state of the code this story touches (read before editing)

- **`lore/convention_matcher.dart`**:
  - `_condOpen = RegExp(r'—\s*если[^—\n\[\]]{1,300}—', caseSensitive: false)` and
    `_condClose = RegExp(r'—\s*конец\s+условия\s*—', caseSensitive: false)`, with a
    long rationale comment above them. Read it: it records Story 3.1's review
    lessons, namely the file-level gate against literary false positives, the
    bracket exclusion that keeps wikilinks tokenized, the 300-char ReDoS bound,
    and the `\b`-after-Cyrillic trap.
  - `_matchConditionalMarkers(text)`: gate on `_condClose.hasMatch`, collect both
    pattern matches, sort, dedupe shared delimiters, pair with a LIFO stack, and
    emit unpaired tokens.
  - `matchConventions` merges these tokens over the per-line tokens (dropping
    overlaps).
- **`lore/convention_lint.dart`**: `_messageFor` has an exhaustive switch; the
  `unpairedConditional` case returns the Russian-only message.
- **`ai/translate_action.dart`**:
  - The two conventions constants (8 lines each) have a doc comment claiming
    byte-for-byte identity with Story 4.3/4.4.
  - `runTranslate` picks `promptConfig.conventions ?? <direction default>` and
    builds the preview sections [instructions, file, glossary, conventions,
    server]; the system prompt is the concatenation (AD-11).
- **`ai/grammar_action.dart`**: `_kGrammarInstructions` (overridable) plus
  `_kResponseFormatContract` (fixed, always appended).
- **Tests**:
  - `convention_matcher_test.dart` "unpaired conditional markers (Story 3.1,
    FR18)" group: ~14 Russian tests, plus an old placeholder test ("em-dash
    conditional marker") explaining the gate.
  - `convention_lint_test.dart`: three conditional tests.
  - `translate_action_test.dart`: the byte-for-byte pin (the section-3 text) and a
    per-direction difference test (`use the English form` / `use the Russian form`
    / `lang:` swaps).
  - `grammar_action_test.dart`: the `contains('Inner monologue')` test.

### What must be preserved

- Every Russian matcher behavior and test.
- The false-positive gate. A file with no closer produces zero conditional
  findings, in either language.
- The non-overlap guarantee of `matchConventions`.
- Linear-time patterns.
- AD-11 preview fidelity (the preview is still built from the same section texts
  that are sent).
- The `ai-prompts.md` override precedence.
- Grammar's fixed response-format contract.

### Architecture guardrails

- **AD-7**: extend the one shared matcher (alternatives in existing patterns).
  Never a second recognizer in the linter or the prompts.
- **AD-8**: total and linear. A lookahead plus a two-way alternation adds no
  backtracking risk; keep the `{1,300}` bound.
- **AD-9**: `lore/` stays pure Dart.
- **AD-11**: prompt text changes only; nothing new leaves the device. The preview
  still shows exactly what is sent.
- **Contract gate**: the loader, model, fixtures and JS reference are untouched.

### English false-positive surface (accepted, documented)

In an English file that *uses* the convention (it has an `— end if —` somewhere), a
literary aside such as `She would come — if he asked — and stay.` reads as an
opener and is flagged as unpaired. This is the same accepted tradeoff Story 3.1
made for Russian `— если бы …` asides: precision over recall, gated to files that
evidence the convention. Keep the gate, and document the English case in the
comment block.

### Testing standards

The matcher, linter and prompt text are business logic, so test them thoroughly
(Task 5). Tests assert tokens, findings and sent/previewed section text. No widget
presence tests.

### Previous story intelligence

- **3.1**: its review found that both new matcher patterns were imprecise on real
  prose, so it redesigned them (the gate, digit/slash exclusions) rather than
  patching edges. Probe the English variants the same way: literary asides,
  prefixes (`iffy`), case, multi-line, brackets.
- **4.5**: forked the conventions constants per direction on purpose ("might
  extract to a config file later"). Edit both, keep them mirror images, and keep
  the shared-override scheme.
- **4.6**: grammar's markup list exists to prevent false "errors" on intentional
  syntax; its review already added the missing inner-monologue line once. This
  story is the same class of fix for English conditionals.
- **5.6** (created alongside this one): unrelated code path (promotion). Both
  stories touch `docs/agent-writing-rules.md` (5.6: §2.2/§2.5/§3; 5.7:
  §4.1/§6.7/§10) and possibly ARCHITECTURE.md/project-context.md in different
  places.

### Git intelligence

- HEAD `9c8facc`: added `docs/agent-writing-rules.md` and fixed project-context's
  monologue line (now plain `Thought:`).
- **Parallel Story 5.5** (branch
  `story/5-5-stop-flagging-emphasized-labels-as-malformed-dialogue`):
  - edits `convention_matcher.dart` (a new `italicMonologue` kind, the
    `_malformedDialogue` lookahead, enum/`errorKinds`/`_priority`),
    `convention_lint.dart` (a new case right after `unpairedConditional`),
    `convention_styles.dart`, the matcher/lint tests (a new group before
    "unpaired conditional markers"), and ARCHITECTURE.md §3.3's inner-monologue
    bullet;
  - it won't touch project-context.md's monologue line (already fixed on main).
  - Whichever story lands second syncs with main and resolves the small adjacent
    conflicts.
- Branch: `story/5-7-translate-emotions-and-conditional-keywords` off `main`,
  commit with a `Co-Authored-By` trailer, `git merge --ff-only`, never push
  ([[git-story-workflow]]).

### Library / version policy

No new dependencies. No web research needed: regex, prompt text, docs.

### Project Structure Notes

- Modified files:
  - `apps/mobile/lib/lore/convention_matcher.dart`,
    `apps/mobile/lib/lore/convention_lint.dart`
  - `apps/mobile/lib/ai/translate_action.dart`,
    `apps/mobile/lib/ai/grammar_action.dart`
  - tests: `convention_matcher_test.dart`, `convention_lint_test.dart`,
    `translate_action_test.dart`, `grammar_action_test.dart`
  - docs: `ARCHITECTURE.md`, `_bmad-output/project-context.md`,
    `docs/agent-writing-rules.md`
  - this story file and `sprint-status.yaml`
- No new files. No `storage/` or `app/` changes.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 5.7]
- [Source: _bmad-output/implementation-artifacts/3-1-lint-a-file-for-convention-errors.md — conditional-marker design, review redesigns, `\b` lesson]
- [Source: _bmad-output/implementation-artifacts/4-5-retranslate-an-already-paired-file.md — per-direction constants, the byte-for-byte AC5 pin this story supersedes]
- [Source: _bmad-output/implementation-artifacts/4-6-grammar-style-findings.md — `_kGrammarInstructions` purpose; response-format split]
- [Source: apps/mobile/lib/lore/convention_matcher.dart — `_condOpen`, `_condClose`, `_matchConditionalMarkers`]
- [Source: apps/mobile/lib/lore/convention_lint.dart — `_messageFor`]
- [Source: apps/mobile/lib/ai/translate_action.dart — `_kConventionsRuToEn`, `_kConventionsEnToRu`]
- [Source: apps/mobile/lib/ai/grammar_action.dart — `_kGrammarInstructions`]
- [Source: ARCHITECTURE.md §3.3; _bmad-output/project-context.md — scene conventions; docs/agent-writing-rules.md §4.1/§6.7/§10]
- [Source: ARCHITECTURE-SPINE.md — AD-7, AD-8, AD-9, AD-11]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List

## Change Log

- 2026-09-24: Story created from KseiPo's 2026-09-24 decisions (translate conditional keywords with `if / else / end if`; translate dialogue emotions). Ultimate context engine analysis completed; comprehensive developer guide created.
