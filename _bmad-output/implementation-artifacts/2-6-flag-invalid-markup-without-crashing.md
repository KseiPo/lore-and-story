---
baseline_commit: 13c6418
---

# Story 2.6: Flag invalid markup without crashing

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want invalid or suspect markup highlighted distinctly,
so that I can spot and fix mistakes fast — and a malformed file never crashes the editor.

## Acceptance Criteria

1. **AC1 (FR9a — distinct error style):** Given file text containing **suspect/invalid markup** — leaked twee macros (`<<…>>`, including `<<=$var>>`/`<<linkBack>>`), leaked **HTML tags** (`<b>`, `</i>`, `<br/>`, `<div …>`), and **scene passage-link syntax** inside double brackets (`[[label->passage]]`, `[[passage<-label]]`) — when it renders in the editor, then those spans get a **distinct error style** (visibly different from the valid-convention styles of Story 2.5) **while the underlying buffer stays raw markdown** (the suspect characters are *styled, never hidden or removed* — the author still sees and can fix them).
2. **AC2 (AD-7 — extend the one matcher, don't fork it):** Given the highlighter, when error recognition is added, then it is added to the **pure `lore/` `convention_matcher`** by **extending `ConventionKind` with error kinds** and matching them there (never in the controller or the editor widget); a **single shared source of truth** identifies which kinds are errors (`errorKinds` set / `isError(kind)` in the matcher) so the controller's error-styling **and** the Story 3.1 linter reference the same set; and overlap **precedence resolves an error over the valid kind it shadows** — `[[a->b]]` is a **passage-link error, not a `wikilink`**, and a macro/tag interior is never partially styled as bold/italic/placeholder.
3. **AC3 (AD-8 / NFR7 — total: never throw, never hang, never drop a char):** Given any input, including deliberately malformed/pathological markup, when `matchConventions` and `buildTextSpan` run, then they **never throw** (the matcher returns whatever it collected; `buildTextSpan` degrades to a plain span), the new regexes are **linear / ReDoS-free** (a large adversarial buffer completes in well under a frame), the **flattened span text equals the buffer exactly** (highlighting adds/removes/reorders nothing), and a file full of suspect markup **still opens, edits, and saves**.
4. **AC4 (no regression / no false positives):** Given the valid conventions from Story 2.5 (`[[Title]]` wikilinks, `**bold**`, `_italic_`, headings, list markers, `Name (emotion):`, `[placeholder]`, em-dash), when the file renders, then they classify **exactly as before** (a plain `[[Title]]` stays a `wikilink`, never an error), and the new error detection produces **no false positives on normal prose** — `5 < 10`, `<3`, `>:(`, a balanced empty `[[]]` (the toolbar's fresh insert), and ordinary em-dash conditionals are **not** flagged.
5. **AC5 (hygiene; gates):** `flutter analyze` clean; `flutter test` green with new matcher/controller/editor tests (baseline is Story 2.5's 180-test suite — add on top); fixtures 4/4 and `npm test` 4/4 with **no loader/model/contract change** (`convention_matcher` is additive and outside the golden fixtures); Story 2.5's valid-convention highlighting, the toolbar, and the editor's save/dirty/pop/lossy/conflict-banner behavior are all preserved.

## Tasks / Subtasks

- [x] **Task 1 — Extend the pure matcher with error kinds (AC: 1, 2, 3, 4)**
  - [x] In `apps/mobile/lib/lore/convention_matcher.dart`, add error values to `enum ConventionKind`: `leakedTwee`, `leakedHtml`, `scenePassageLink`, `malformedMarkup`. Keep the doc comment's "consumers must tolerate kinds beyond this set" promise real — the controller switch will force a compile error until every new kind is styled (Task 2), which is the intended safety net.
  - [x] Add a **single source of truth** for which kinds are errors, so the controller and the Story 3.1 linter don't each hardcode the set: e.g. `const Set<ConventionKind> errorKinds = { ConventionKind.leakedTwee, ConventionKind.leakedHtml, ConventionKind.scenePassageLink, ConventionKind.malformedMarkup };` plus `bool isError(ConventionKind k) => errorKinds.contains(k);`. Export via the `lore/` barrel (already re-exports the matcher).
  - [x] Add **linear (ReDoS-free) inline regexes** — negated character classes only, no nested quantifiers:
    - `leakedTwee`: `<<[^>\n]*>>` — the whole `<<…>>` macro run (matches `<<if $x>>`, `<<=$var>>`, `<<linkBack>>`).
    - `leakedHtml`: `</?[A-Za-z][^>\n]*>` — an HTML tag. The required letter after `<`/`</` means `5 < 10`, `<3`, and `>:(` do **not** match (AC4).
    - `scenePassageLink`: `\[\[[^\[\]\n]*(?:->|<-)[^\[\]\n]*\]\]` — a `[[…]]` whose interior contains a Twine passage arrow. (Consider `|` as an optional Twine form; the epic's concrete case is the `->`/`<-` arrows. A plain `[[Title]]` has no arrow and stays a `wikilink`.)
    - `malformedMarkup` (**conservative**): an **unterminated `[[`** — a `[[` with no closing `]]` later on the same line. Flag a **short marker span** (the `[[` opener, ~2 chars), **not** the rest of the line, so valid tokens after it survive. A balanced empty `[[]]` is *terminated* → **not** flagged (this is exactly what the toolbar's `[[` button inserts). Do **not** build a general markdown validator or flag unclosed `**`/`_` (noisy mid-typing; the Story 3.1 linter refines this later). When in doubt, don't flag — a false error is worse than a missed one for highlighting.
  - [x] In `_matchLine`, add the error candidates to the same `cands` list as the valid inline kinds (via `_collect` for the regex kinds; a small hand-scan for the unterminated-`[[` marker), then let the existing `_resolveOverlaps` handle precedence.
  - [x] Update `_priority` so **error kinds outrank the valid kinds they shadow**: `scenePassageLink` must beat `wikilink` **and** `placeholder`; `leakedTwee`/`leakedHtml` must beat every inline valid kind (so a macro/tag interior is never partially styled). Recommended order (lower = higher precedence): `heading`, `listMarker`, `leakedTwee`, `leakedHtml`, `scenePassageLink`, `malformedMarkup`, `dialogueSpeaker`, `wikilink`, `bold`, `italic`, `placeholder`, `emDash`. Keep `leakedTwee` above `leakedHtml` (a `<<…>>` is never two HTML tags).
  - [x] **Totality unchanged (AC3):** the outer `try/catch` in `matchConventions` already makes it total — keep it; do not let any new helper throw out of the loop. Confirm the new regexes are compiled once as top-level `final` fields (like the existing ones), not per call.
  - [x] **Heading lines:** `_matchLine` still early-returns a whole-line `heading` token (headings subsume inline, per Story 2.5) — error kinds are not scanned inside a heading. Leaked twee in a `# heading` is a rare, accepted v0.1 gap; note it, don't complicate the heading path.
- [x] **Task 2 — Style the error kinds in the controller (AC: 1, 3)**
  - [x] In `apps/mobile/lib/app/convention_highlighting_controller.dart`, add `switch` cases in `_styleFor` for the four new kinds, all mapping to **one distinct error style** clearly different from the valid styles: use `Theme.of(context).colorScheme.error` for color plus a **wavy underline** (`decoration: TextDecoration.underline`, `decorationStyle: TextDecorationStyle.wavy`, `decorationColor: scheme.error`) — a spellcheck-squiggle read. The character stays fully visible (raw-buffer rule); do not set a background that hides it or change the text itself.
  - [x] The controller still holds **no matching logic** — it only maps `ConventionKind → TextStyle`. It may reference `errorKinds`/`isError` from the matcher for a shared style branch, but must not re-detect anything (AD-7).
  - [x] The existing `buildTextSpan` structure (memo, defensive per-token range checks, `try/catch → plain span`, `spans.isEmpty → plain span`) is **unchanged** and already satisfies AC3 for the render path — verify the new kinds flow through it untouched (the flattened-text-equals-buffer invariant must still hold).
- [x] **Task 3 — Tests (AC: 1–5)**
  - [x] **Matcher unit tests** (`apps/mobile/test/lore/convention_matcher_test.dart`, pure):
    - Each error kind matches with correct ranges: `<<if $x>>`/`<<=$var>>`/`<<linkBack>>` → one `leakedTwee` over the full `<<…>>`; `<b>`/`</i>`/`<br/>`/`<div class="x">` → `leakedHtml`; `[[label->passage]]` and `[[passage<-label]]` → `scenePassageLink` (**not** `wikilink`, inner **not** `placeholder`); an unterminated `[[` (e.g. `see [[Selena`) → `malformedMarkup`.
    - **Precedence:** `<<x>>` is `leakedTwee` not `leakedHtml`; `[[a->b]]` is `scenePassageLink` not `wikilink`.
    - **No regression / no false positives (AC4):** plain `[[Title]]` stays `wikilink`; `[[]]` (balanced empty) is **not** flagged; `5 < 10`, `<3`, `>:(` produce **no** `leakedHtml`; em-dash conditional still `emDash`.
    - **Cyrillic first-class:** `[[Селена->станция]]` → `scenePassageLink`; `<<если>>` → `leakedTwee`.
    - **CRLF-safe** (a trailing `\r` doesn't shift/break error tokens); sorted, non-overlapping with valid kinds.
    - **Total & linear (AC3):** pathological input (`'<' * 50000`, `'[' * 50000`, `'<<' * 20000`, `'<<<>>>'`, `'[[[[' `) returns **without throwing** and **fast** (assert wall-time well under a frame, e.g. `< 50ms`) — the never-crash guarantee includes never-hang (ReDoS).
  - [x] **Controller tests** (`apps/mobile/test/app/convention_highlighting_controller_test.dart`): a buffer with leaked twee / HTML / `[[a->b]]` yields a span whose error slice carries the error style (assert `color == scheme.error` and/or the wavy decoration) **and** whose flattened text equals the input exactly (no char dropped); a malformed/pathological buffer returns a plain span and never throws.
  - [x] **Editor widget test** (`apps/mobile/test/app/editor_page_test.dart`): open a file containing `<<if $x>>` and `[[a->b]]` — it renders without throwing, is editable, and **saves** (AC3: a suspect file still opens/edits/saves). Keep it a small addition to the existing group; do not disturb the toolbar / conflict-banner / dirty-save tests.
  - [x] Re-run the contract gate: `flutter analyze` clean; `flutter test` green; fixtures 4/4; `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` **empty**.

### Review Findings

Cross-model review (Opus 4.8 implementation, 3 Sonnet layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor). The Acceptance Auditor independently reproduced every gate (analyze clean, 196/196, `npm test` 4/4, contract git-clean) and confirmed all 5 ACs met with non-vacuous tests. One High (a correctness miss that also exposed a latent O(n²)) plus doc/test hardening are patched; broader malformed-detection cases are deferred to the Story 3.1 linter as the story already scoped.

**Patch:**

- [x] [Review][Patch] **`leakedTwee`'s body class `[^>]` misses idiomatic `<<…>>` macros with an internal `>` — and hides a latent O(n²).** `<<if $hp >= 100>>` and `<<link "Next" -> "Scene2">>` (comparison + link macros, the two most common leaked-twee shapes) don't match `<<[^>\n]*>>`; worse, `_leakedHtml` then grabs a truncated `<if $hp >` substring and mislabels it, leaving the rest unflagged. Separately, on `'>>' + '<<' × 20000` the `contains('>>')` guard passes but no `>>` follows the `<<` run, so `[^>]*` scans-and-backtracks per start — **525ms measured, O(n²)** (an AC3 "never hang" gap the current adversarial test misses because its `'<<'×20000` case has no `>>` and is guarded out). Fix: narrow the full-macro body to `<<[^<>\n]*>>` (linear — 0ms on the same input) and add a `<<|>>` delimiter fallback (kind `leakedTwee`) so any leaked macro — including those with internal `<`/`>` — is still flagged (MOBILE §6.1 names `<<`/`>>` themselves as the signals). Harden the ReDoS test with the `'>>' + '<<'×N` regression case and the reviewer macro shapes. [apps/mobile/lib/lore/convention_matcher.dart:94] (blind+edge)
- [x] [Review][Patch] **Dev Agent Record test-count bookkeeping.** The record says "11 matcher" new tests; the new matcher group has 12 (the suite total of 196 is correct). Trivial prose fix. [2-6-flag-invalid-markup-without-crashing.md Dev Agent Record] (auditor)

**Deferred:**

- [x] [Review][Defer] **Suspect markup on a heading line is not flagged.** `_matchLine` early-returns a whole-line `heading` token (Story 2.5's "headings are larger, subsume inline" design), so `# <<if $x>>` / `# <script>` are rendered as a plain heading — error kinds are never scanned there, and even if collected they'd be suppressed by the whole-line heading's top precedence. Surfacing them means reworking heading precedence (a 2.5-level design change); leaked markup inside a `# heading` is rare. Deferred; the Story 3.1 linter can refine. [apps/mobile/lib/lore/convention_matcher.dart:_matchLine] (blind)
- [x] [Review][Defer] **Broader malformed-bracket cases beyond an unterminated `[[`.** A stray dangling `]]` (`[[a]]b]]`) is unstyled, and nested brackets in a target (`[[Chapter[1]->Scene2]]`) fall back to the 2-char unterminated-`[[` marker rather than a passage-link error. The story deliberately scoped `malformedMarkup` to the unterminated-`[[` case and deferred dangling/unpaired/nested detection to the Story 3.1 linter (FR18), which consumes the same tokens. [apps/mobile/lib/lore/convention_matcher.dart] (blind+edge)
- [x] [Review][Defer] **An error token straddling a newline is not detected.** `<<if\n>>` / `<div\n>` produce no candidate on either line — the matcher is line-oriented for *every* kind (Story 2.5), and cross-line detection would need a pre-split scan. Multi-line leaked macros are rare and this is consistent with all other kinds. [apps/mobile/lib/lore/convention_matcher.dart] (edge)

**Dismissed (3):** zero-length candidate always kept in the `_resolveOverlaps` bitmap — unreachable, `_collect` filters `m.end > m.start` so no zero-length token is ever a candidate; `_styleFor` enumerates the four error kinds instead of branching on `isError()` — by design and story-permitted, the exhaustive `switch` is a *stronger* safety net (it compile-errors on a future unhandled kind, which `isError()` would not); leaked HTML with a literal `>` inside a quoted attribute (`<a href=">">`) truncates the styled span — still error-flagged, cosmetic span imprecision, effectively nonexistent in prose.

## Dev Notes

### What this story is — Story 2.5's matcher + highlighter, extended with *error* kinds

Story 2.5 built the AD-7 keystone: a **pure `lore/` `convention_matcher`** (`matchConventions(String) → List<ConventionToken>` over 8 *valid* `ConventionKind`s) consumed by a display-only highlighting `TextEditingController`. Story 2.5's own notes said it left a hook: *"Story 2.6 adds error kinds (leaked twee, invalid markup, scene passage-links) and Story 3.1's linter consumes the same tokens."* **This is that story.** It is deliberately small and surgical:

- **Extend the enum + matcher** (pure `lore/`) with error kinds and their (linear) detection.
- **Add error styling** (the controller's `_styleFor`).
- **No new files, no new production wiring** — `editor_page.dart` already uses `ConventionHighlightingController`, so error styles flow to the editor automatically. Only tests change beyond the two source files.

The story title carries the co-equal requirement: **"without crashing."** AC1 (flag it) and AC3 (never throw/hang/drop-a-char, file still opens/edits/saves) are equally the point — AD-8 / NFR7.

### What counts as "invalid / suspect markup" (the sources)

- **Leaked twee macros `<<…>>`** — scenes and lore are *plain markdown*: "No SugarCube macros, no HTML, no game logic — twee exists only in the final passages" (ARCHITECTURE.md §3.3). Project-context calls out `<<=$var>>` explicitly as the wrong form where `[placeholder]` belongs. So any `<<…>>` in an edited file is suspect.
- **Leaked HTML** — same rule ("no HTML"). An HTML tag (`<b>`, `</i>`, `<br/>`, `<div …>`) is suspect. Require a letter after `<`/`</` so it can't false-positive on prose `<`/`>` (AC4).
- **Scene passage-link syntax `[[label->passage]]`** — `[[Wikilinks]]` are reserved for **lore entity references** and are **never passage jumps** (ARCHITECTURE.md §3.3; project-context anti-pattern: "Treating `[[wikilinks]]` as passage jumps"). The *Twine* arrow form `[[label->passage]]` / `[[passage<-label]]` is therefore invalid **in this project's markdown** — flag it. The canonical scene player-choice form is instead `**Choice** _(→ Passage Name)_` (out of scope to *insert* here; that's Story 2.15's toolbar work).
- **Malformed markup (conservative)** — the epic AC lists "malformed markup" first, but keep it tight: an **unterminated `[[`** is the one mechanically-safe, low-noise case. The broad "malformed" surface (unpaired em-dash conditionals, dangling wikilinks, malformed dialogue) is **Story 3.1's linter** (FR18) — the same matcher, surfaced as a findings list. Don't pre-build the linter here.

### Precedence is the subtle part — an error must win over the valid kind it looks like

`[[a->b]]` matches **both** the `scenePassageLink` regex **and** the `wikilink` regex (and the inner `[b]` matches `placeholder`). `_resolveOverlaps` keeps the higher-precedence candidate and drops overlappers, so `scenePassageLink` **must** have a lower `_priority` number than `wikilink` and `placeholder`. Likewise `leakedTwee`/`leakedHtml` must outrank every inline valid kind so a macro/tag interior (which may contain `_`, `**`, `[…]`) is never partially styled. Follow the recommended `_priority` order in Task 1. The existing `_resolveOverlaps` machinery needs no change — only the priority table and the candidate set.

### The totality contract (AD-8 / NFR7) — and "never crash" includes "never hang"

Story 2.5's structure already delivers most of AC3 and **must be preserved**:

- `matchConventions` wraps its loop in `try/catch` and returns whatever it collected → **never throws**.
- `buildTextSpan` has defensive per-token range checks + `try/catch → TextSpan(text: source, style: style)` → **never throws, never drops a char**; the tested invariant is *the concatenation of all span texts equals the buffer exactly*.
- The editor's `_load`/`_save` are already catch-**all** (AD-8-at-call-site, hardened in Stories 1.4/2.4) so a malformed file opens into the editor and saves — this story adds **no new async**, so that path is untouched. Add a test that proves a suspect file opens/edits/saves; you don't need to change the load/save code.

The **new** risk this story introduces is **ReDoS**: a catastrophically-backtracking regex doesn't *throw*, it *hangs* — which still violates "never crash." Story 2.5's review explicitly verified the matcher was linear (<2ms at 70k chars). Keep that: use **negated character classes** (`<<[^>\n]*>>`, `</?[A-Za-z][^>\n]*>`, `\[\[[^\[\]\n]*…\]\]`) with no nested `*`/`+`. Add the adversarial-input timing test (Task 3).

### Files being MODIFIED (read before editing — both are short)

- **`apps/mobile/lib/lore/convention_matcher.dart`** (MODIFY, stays pure `lore/`) — current state: `ConventionKind` (8 valid kinds); top-level `final RegExp` fields (`_heading`, `_listMarker`, `_dialogue`, `_wikilink`, `_placeholder`, `_bold`, `_italicUnderscore`, `_italicStar`, `_emDash`); `matchConventions` (line-split loop, try/catch-total); `_matchLine` (heading early-return, else collect line-start + inline candidates → `_resolveOverlaps`); `_collect`; `_priority`; `_resolveOverlaps`. **Change:** add error kinds + `errorKinds`/`isError`, add the three inline error regexes + the unterminated-`[[` scan, extend `_priority`, add error candidates in `_matchLine`. Keep it pure (no Flutter/`dart:io`) and total.
- **`apps/mobile/lib/app/convention_highlighting_controller.dart`** (MODIFY) — current state: `ConventionHighlightingController extends TextEditingController`; by-text memo (`_cachedText`/`_cachedTokens`); `buildTextSpan` (defensive, total); `_styleFor` — an **exhaustive** `switch` over `ConventionKind` (no `default`), so adding enum values **won't compile** until you add cases (use this). **Change:** add the four error-kind cases mapping to the distinct error style. No logic beyond kind→style.
- **`apps/mobile/lib/lore/lore.dart`** — already exports `convention_matcher.dart`; `errorKinds`/`isError` ride along. Only touch it if a symbol needs exporting that isn't already.

**Do NOT modify** (verify git-clean at the end): `apps/mobile/lib/app/editor_page.dart` (production — no change needed; it already uses the controller), `apps/mobile/lib/app/editor_toolbar.dart`, `lib/lore.js`, `test/fixtures/lore-model/**`, `scripts/**`, `lore_loader.dart`, `lore_model.dart`.

### Architecture guardrails

- **AD-7 — one matcher, many consumers.** Error recognition lives **only** in `convention_matcher.dart`. The controller styles kinds; the Story 3.1 linter will list them — neither re-detects. The `errorKinds`/`isError` shared set is the AD-7 move that stops the controller and the linter from drifting on "what is an error." [ARCHITECTURE-SPINE.md#AD-7]
- **AD-8 / NFR7 — total.** Matcher and `buildTextSpan` never throw; new regexes are linear (never hang); unclassifiable input degrades to plain text; the span-text-equals-buffer invariant holds; a malformed file still opens/edits/saves. [#AD-8]
- **AD-9 — purity.** The matcher stays pure `lore/` (no Flutter, no `dart:io`); styling/`BuildContext` stay in the `app/` controller. Error *kinds* are pure data; error *styling* is UI. [#AD-9]
- **Raw-markup rule (MOBILE.md §5, PRD).** Error markup is **styled, never hidden or removed** — the suspect characters are exactly what the author needs to see to fix. Typing `<<x>>` shows `<<x>>` (in the error style). No WYSIWYG. [PRD editing-UX]
- **AD-2 — contract untouched.** No loader/model change; `convention_matcher` is not part of the golden fixtures. Fixtures 4/4, `npm test` 4/4 (AC5). [#AD-2]
- **NFR6 — responsive.** `buildTextSpan` runs per keystroke; keep the added regexes O(n) and compiled once. Cards/scenes are a few KB. [prd.md#NFR6]

### Previous story intelligence (Story 2.5 — done)

- The matcher is **line-oriented**: `matchConventions` splits on `\n` and calls `_matchLine` with a running `base` offset; tokens carry offsets into the *original* string (CRLF-safe). Add error candidates the same way — line-relative, then shifted by `base`.
- `_resolveOverlaps` sorts by `_priority` then position/length and drops overlappers — **this is where your error precedence takes effect.** Get `_priority` right and overlap handling is free.
- Story 2.5's review found and fixed: toolbar focus-steal, `prefixLines` boundary bugs, un-clamped selection `RangeError`, a line-start-wikilink-in-dialogue drop, a heading `\r` bleed, and added a `buildTextSpan` memo. Those live in `editor_toolbar.dart` / the controller — **don't regress them**; this story doesn't touch the toolbar and only *adds* switch cases to the controller.
- Cross-model review has caught a real bug every story on this project ([[cross-model-code-review]]) — expect the reviewer to probe precedence (does an error truly beat the wikilink?), ReDoS on the new regexes, and a false-positive on innocent `<`/`>`/`[[]]`. Cover those in tests up front.
- Toolchain: Flutter at `C:\programs\flutter\bin` (3.44.7 / Dart 3.12.2), **not on PATH** — run via PowerShell with a PATH prefix. `flutter analyze` + `flutter test`; `npm test` for the JS reference cross-check. Dart `RegExp` here uses plain negated classes (no `unicode:`/`\p{}` needed for the error kinds — Cyrillic falls out of `[^>\n]`/`[^\[\]\n]` naturally).

### Git intelligence

Baseline `13c6418` (HEAD) includes Story 2.5's merged editor/matcher work (commit `d20504b`) plus docs-only backlog stories 2.14/2.15 (`13c6418`). `lore/` currently holds `lore_loader`/`lore_model`/`lore_browse`/`project_config`/`convention_matcher` (all pure). No error-kind code exists yet. Branch per story, ff-merge to main, never push, model `Co-Authored-By` trailer ([[git-story-workflow]]).

### Library / version policy

**No new dependencies.** Hand-rolled linear regexes extend the existing matcher; the error style is a `TextStyle` with a wavy underline decoration (Flutter built-in). Do **not** add a markdown/syntax/lint package — the whole point is *this project's* conventions and error signals, which a generic package can't recognize. [Story 2.5 policy]

### Testing standards

- **Matcher → pure unit tests** in `test/lore/` (no widget): kind + range per error convention, precedence (error beats the valid kind it shadows), no-regression on valid kinds, no false positives (`<`/`>`/`[[]]`), Cyrillic, CRLF==LF, and **total + linear** on adversarial input (timing assertion for ReDoS).
- **Controller → widget/unit tests** in `test/app/`: error slice carries the error style; flattened text == buffer; no-throw on pathological input.
- **Editor → widget test** in `test/app/`: a suspect file opens, edits, and saves (AC3 at the real call site).
- **Contract gate:** fixtures 4/4, `npm test` 4/4, `git status --porcelain lib/lore.js test/fixtures/ scripts/ …loader.dart …model.dart` empty. `convention_matcher` is Dart-only, outside the fixtures.

### Project Structure Notes

- Modified pure logic: `apps/mobile/lib/lore/convention_matcher.dart` (error kinds + detection + `errorKinds`/`isError`).
- Modified UI: `apps/mobile/lib/app/convention_highlighting_controller.dart` (`_styleFor` error cases).
- Tests: additions to `apps/mobile/test/lore/convention_matcher_test.dart`, `apps/mobile/test/app/convention_highlighting_controller_test.dart`, `apps/mobile/test/app/editor_page_test.dart`.
- No new files; no `editor_page.dart` production change (variance from a naive "new widget" expectation — the controller is already wired, so error styling is automatic). This is the deliberate, minimal blast radius.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.6] — user story + ACs (FR9a error style; AD-8/NFR7 never-crash)
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR9a] (render invalid/suspect markup — malformed, leaked twee `<<…>>`/HTML, scene `[[label->passage]]` — in a distinct error style), #NFR7 (malformed input never crashes: loader/highlighter/editor degrade, never throw; malformed files still open/edit/save)
- [Source: MOBILE.md §5.2] (custom `TextEditingController.buildTextSpan`; highlight *this project's* conventions; same matcher reused as the §6.1 linter), §6.1 (convention linting: "twee markup leaking in (`<<`, `>>`, HTML), `<<=$var>>` where `[placeholder]` belongs …" — the FR9a signals, surfaced later as findings)
- [Source: ARCHITECTURE.md §3.3] (scenes are plain markdown — "No SugarCube macros, no HTML, no game logic"; `[[Wikilinks]]` are lore entity references, **never passage jumps**; canonical choice form `**Choice** _(→ Passage)_`)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-7] (one convention matcher, many consumers — binds highlighter FR9/FR9a + linter FR18), #AD-8 (parsing/highlighting are total, never throw), #AD-9 (per-slice purity)
- [Source: apps/mobile/lib/lore/convention_matcher.dart] — the matcher being extended (enum, regexes, `_matchLine`, `_priority`, `_resolveOverlaps`); Story 2.5 left the "2.6 adds error kinds" hook here
- [Source: apps/mobile/lib/app/convention_highlighting_controller.dart] — the highlighter whose `_styleFor` gains the error cases; the total `buildTextSpan` + span-text-equals-buffer invariant to preserve
- [Source: _bmad-output/implementation-artifacts/2-5-edit-with-helper-toolbar-and-convention-highlighting.md] — prior story: the matcher/controller design, the totality contract, the no-ReDoS finding, and the precedence/overlap machinery this story reuses
- [Source: _bmad-output/project-context.md] — twee-leak anti-patterns (`<<=$var>>` vs `[placeholder]`; `[[wikilinks]]` are not passage jumps; no HTML in scenes); non-ASCII (Cyrillic) first-class; UTF-8 always

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- Baseline before work: `flutter test` **180 passing**, `flutter analyze` clean.
- `flutter analyze` → **No issues found.**
- `flutter test` → **196 passing** (180 → +16: 12 matcher, 3 controller, 1 editor). Post-review the matcher group gained one more (delimiter-fallback) case.
- **Contract gate (AC5):** `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` **empty** — the matcher change is additive and outside the golden fixtures.
- **Two quadratics caught by the ReDoS-guard test during dev (RED→fixed), not shipped:** (1) `_leakedTwee`'s `<<[^>\n]*>>` backtracks O(n²) on a long run of `<<` with no closing `>>`; fixed by gating each error regex on a cheap `line.contains('>>' | '>' | ']]')` for its closer (correctness-preserving — the pattern can't match without it). (2) `_resolveOverlaps`' `kept.any(...)` was O(n²) once the unterminated-`[[` regex fires on a long all-`[` line; rewritten to a `covered` bitmap sweep (~O(total token length)). After both fixes the adversarial input (`'<'*50000`, `'['*50000`, `'<<'*20000`, `'<<<>>>'*10000`) completes in <1s.

### Completion Notes List

- **Error kinds live in the one pure matcher (AD-7).** Extended `ConventionKind` with `leakedTwee`, `leakedHtml`, `scenePassageLink`, `malformedMarkup`, plus a single-source-of-truth `errorKinds` set + `isError(kind)` so the controller's error styling and the future Story 3.1 linter agree on "what is an error" without either hardcoding the set. No detection logic leaked into the controller or editor.
- **Linear error regexes.** `<<[^>\n]*>>` (leaked twee), `</?[A-Za-z][^>\n]*>` (leaked HTML — the required letter after `<`/`</` keeps `5 < 10`, `<3`, `>:(` from matching), `\[\[[^\[\]\n]*(?:->|<-)[^\[\]\n]*\]\]` (Twine passage-link), and `\[\[(?![^\[\]\n]*\]\])` (unterminated `[[`, a 2-char marker; a balanced `[[]]` is terminated → never flagged, which is exactly what the toolbar inserts). All negated-class, no nested quantifiers; each gated on its closing delimiter.
- **Precedence flags the error over the convention it mimics.** `_priority` puts the error kinds above the valid kinds they shadow: `[[a->b]]` resolves to `scenePassageLink` (not `wikilink`, inner not `placeholder`); a `<<…>>` / `<tag>` interior is never partially styled as bold/italic/placeholder. A plain `[[Title]]` stays a `wikilink` — no false error.
- **One distinct error style, markup never hidden.** The controller's `_styleFor` maps all four error kinds to `colorScheme.error` + a **wavy underline** (spellcheck squiggle). The buffer stays raw markdown; the suspect characters are styled, never removed or hidden — the author sees exactly what to fix. The exhaustive `switch` (no `default`) meant the code would not compile until every new kind was styled — the intended safety net.
- **Total: never throw, never hang, never drop a char (AD-8 / NFR7).** The matcher's outer `try/catch` and the controller's defensive `buildTextSpan` (range checks + `try/catch → plain span`) are unchanged and still hold the span-text-equals-buffer invariant. "Never crash" was treated to include "never hang": the ReDoS-guard test drove out two quadratics (see Debug Log). A file full of leaked twee / HTML / passage-links opens, edits, and saves (editor widget test).
- **No new files, no `editor_page.dart` production change.** The editor already uses `ConventionHighlightingController`, so error styling flows through automatically — the minimal blast radius the story planned. No new dependencies. No loader/model/contract change.
- **Accepted v0.1 gaps (documented, not defects):** leaked twee inside a `# heading` is not separately flagged (headings subsume inline, per Story 2.5 — unchanged early-return); the `|` Twine link form is not flagged (only the `->`/`<-` arrows the epic names); broad "malformed" detection (unpaired conditionals, dangling wikilinks) is deliberately left to the Story 3.1 linter, which consumes these same tokens.

### File List

**Modified:**
- `apps/mobile/lib/lore/convention_matcher.dart` (error kinds in `ConventionKind`; `errorKinds`/`isError`; four linear error regexes + closer guards in `_matchLine`; `_priority` extended so errors outrank shadowed valid kinds; `_resolveOverlaps` rewritten to a covered-bitmap sweep)
- `apps/mobile/lib/app/convention_highlighting_controller.dart` (`_styleFor` error-kind cases → distinct wavy error style)
- `apps/mobile/test/lore/convention_matcher_test.dart` (invalid/suspect-markup group: kinds, precedence, no-false-positives, Cyrillic, CRLF, ReDoS/linearity guard, `errorKinds`/`isError`)
- `apps/mobile/test/app/convention_highlighting_controller_test.dart` (error slice carries the wavy error decoration; valid wikilink does not; suspect-heavy buffer renders plainly, no throw)
- `apps/mobile/test/app/editor_page_test.dart` (a file full of suspect markup opens, edits, and saves)

**Deliberately NOT modified (verified git-clean):** `apps/mobile/lib/app/editor_page.dart`, `apps/mobile/lib/app/editor_toolbar.dart`, `apps/mobile/lib/lore/lore.dart` (matcher already exported; `errorKinds`/`isError` ride along), `lib/lore.js`, `test/fixtures/lore-model/**`, `scripts/**`, `lore_loader.dart`, `lore_model.dart`.

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-26 | Addressed code review (Opus 4.8 impl, 3 Sonnet layers). **High (correctness + latent hang):** `_leakedTwee`'s `<<[^>\n]*>>` missed the two most idiomatic leaked shapes — comparison (`<<if $hp >= 100>>`) and link (`<<link "a" -> "b">>`) macros — mislabeling them as truncated HTML, and hid a latent O(n²) (525ms measured on `'>>' + '<<'×20000`, where the `contains('>>')` guard passes but nothing closes the `<<` run). Narrowed the clean-macro body to `<<[^<>\n]*>>` (opener-bounded → linear, 0ms) and added a `<<`/`>>` delimiter fallback (kind `leakedTwee`, per MOBILE §6.1) so any leaked macro is flagged even with an interior `<`/`>`; a clean `<<x>>` still highlights as one span via precedence. Hardened the ReDoS test with the `'>>' + '<<'×N` regression case and interior-`>` macro shapes. Fixed a Dev-record test-count nit (12 matcher, not 11). Tests 196 → 197; analyze clean; `npm test` 4/4; contract git-clean. 3 findings deferred (suspect markup in a heading; broader malformed brackets — stray `]]`/nested — → Story 3.1 linter; cross-line error tokens); 3 dismissed (unreachable zero-length bitmap candidate; `isError()`-vs-exhaustive-switch by design; leaked-HTML quoted-`>` cosmetic). |
| 2026-07-26 | Implemented Story 2.6: flag invalid/suspect markup (FR9a) without crashing (AD-8/NFR7). Extended the pure `lore/convention_matcher` with four error kinds (`leakedTwee` `<<…>>`, `leakedHtml` `<tag>`, `scenePassageLink` `[[a->b]]`, `malformedMarkup` unterminated `[[`) + a shared `errorKinds`/`isError` (one source of truth for the controller styling and the Story 3.1 linter — AD-7). `_priority` extended so an error outranks the valid kind it mimics (`[[a->b]]` is a passage-link error, not a wikilink). Controller `_styleFor` styles all four with one distinct wavy error decoration over the raw buffer (markup styled, never hidden). Totality preserved; the ReDoS-guard test drove out two quadratics before ship (leaked-twee regex backtracking → closer guards; `_resolveOverlaps` `kept.any` → covered-bitmap sweep). No new files, no `editor_page.dart` production change, no new deps, no loader/model/contract change. Tests 180 → 196 (+16); `flutter analyze` clean; `npm test` 4/4; contract git-clean. |
