---
baseline_commit: 7b0956c02588c80c312922c0b35d3b115f70bd4e
---

# Story 2.15: Unify scene link formats and expand toolbar tokens

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Decision (2026-08-05, resolves epics.md's open design question — supersedes the first draft of this story)

KseiPo chose to **unify** the scene-navigation link formats, resolving the design question epics.md raised — after a design discussion that landed on a specific, low-risk mechanism: **pure syntactic disambiguation, no namespace/passage lookup needed.**

**The rule:** a `[[...]]` bracket pair with **no separator** is a lore-entity wikilink (unchanged). A bracket pair **with a separator** is a scene-navigation link — and which separator, and which side of it, determines the kind:

- **Lore reference** (unchanged): `[[Title]]`
- **Passage link** (replaces `**Choice text** _(→ Passage Name)_`): `[[Choice text->Passage Name]]` or `[[Choice text|Passage Name]]` — choice/label text before the separator, target passage name after.
- **Return link** (replaces `**Label** _(↩ back)_` / `**Label** _(↩ wake up)_`): `[[back<-Label]]` / `[[wake up<-Label]]` — the **backlink type** (matches a configured `returnMacros` widget — see ARCHITECTURE.md §3.3, e.g. `<<linkBack>>`/`<<wakeupLink>>`) comes *before* the reverse arrow, the display label comes *after*. Arrow **direction is semantic**, not stylistic: `->`/`|` always mean "forward to a named passage," `<-` always means "return, no target — the left side names the return type."
- A "bold-only, no target" choice (`**Choice**` alone) stays plain bold prose — it was never a link and isn't part of this system.

**Why this avoids the namespace/scene↔passage-bridge problem:** disambiguation is purely about *shape* (does the bracket content contain a separator, and which one) — never about looking up whether a target string resolves to a real passage or entity. That lookup — and the scene↔passage bridge it would need — doesn't exist in any planned story yet (confirmed: not in epics.md). This story doesn't wait for it.

**This is a full replacement, not dual support.** Going forward `convention_matcher` only recognizes the bracket forms as scene-navigation links. The old prose forms (`_(→ Passage Name)_`, `_(↩ back)_`) are **not** specially recognized after this story ships — they'd just read as generic bold + generic italic, no distinct highlight. KseiPo has already started hand-writing the new bracket format in the newest scene files (currently shown as flagged errors, since today's matcher treats `[[a->b]]` as *invalid* markup) and will migrate older files using the regexes below — **no migration tooling/script/test is part of this story**, this is a one-time manual find-and-replace KseiPo runs.

### Migration regexes (deliver these to KseiPo; not implementation work)

Two passes, order-independent (disjoint syntax — → vs ↩):

**Passage links:**
```
Find:    \*\*([^*\n]+)\*\*\s*_\(→\s*([^)\n]+?)\s*\)_
Replace: [[$1->$2]]
```

**Return links** (note the group swap — old form is `**Label** _(↩ type)_`, new form is `[[type<-Label]]`):
```
Find:    \*\*([^*\n]+)\*\*\s*_\(↩\s*([^)\n]+?)\s*\)_
Replace: [[$2<-$1]]
```

A "bold-only, no target" choice matches neither pattern and is correctly left untouched.

## Story

As the author,
I want the toolbar to offer quick-insert for scene passage/return links in the new unified bracket format, plus a full dialogue-speaker line and an external link,
so that I can author the full convention set — including navigation — from the phone, with one link syntax to remember instead of three.

## Acceptance Criteria

1. **Given** a `[[...]]` bracket pair, **When** it contains no separator, **Then** it is recognized as a lore-entity `wikilink` (unchanged behavior).

2. **Given** a `[[...]]` bracket pair, **When** it contains `->`, `|`, or `<-`, **Then** it is recognized as a new **`sceneLink`** convention (a valid convention, not an error) — replacing today's behavior where this shape is flagged as suspect markup (`scenePassageLink`, currently in `errorKinds`).

3. **Given** the renamed/reclassified kind, **When** highlighting or the (future) linter consumes it, **Then** it shares the **same `convention_matcher`** token (extend/reclassify, don't fork — AD-7); no new parallel recognition path.

4. **Given** the toolbar, **When** it is extended, **Then** it offers quick-insert for: a full dialogue-speaker line, a passage link (`[[Choice->Passage Name]]`), a return link (`[[back<-Label]]`), and an external link (`[label](url)`) — via the Story 2.5 insert/wrap/prefix mechanisms, no active-state/toggle (out of this story's scope, per Story 2.14).

5. **Given** ARCHITECTURE.md §3.3 and project-context.md, **When** the format changes, **Then** both are updated to document the new bracket forms as canonical, replacing the old prose-form documentation (this is the contract-level doc update epics.md's original framing called for).

## Tasks / Subtasks

- [x] Task 1: Rename and reclassify `scenePassageLink` → `sceneLink` in the matcher (AC: 1, 2, 3)
  - [x] 1.1 Enum value renamed, removed from `errorKinds`.
  - [x] 1.2 Regex widened to accept `|` alongside `->`/`<-`; relocated from the "Error patterns" section to the "Inline patterns" section (it's no longer an error).
  - [x] 1.3 `_matchLine`'s gated collection updated; gate logic unchanged.
  - [x] 1.4 `_priority()` case renamed, same numeric slot (3); comment reframed to explain it must outrank `wikilink` as a more-specific match, not because it's an error.
  - [x] 1.5 All 4 stale tests rewritten (not just renamed) — the old `'scene passage-link syntax is an error...'` test removed (superseded by the new `sceneLink` group below), `isError`/`errorKinds` assertions flipped, Cyrillic/CRLF tests split so `sceneLink` isn't framed as error markup.
  - [x] 1.6 6 new tests added in a dedicated `sceneLink` group: `->`/`<-`/`|` all recognized; not an error; no-separator regression guard (still `wikilink`); Cyrillic; CRLF-safety; empty label/target doesn't crash.
- [x] Task 2: Style the reclassified kind (AC: 3)
  - [x] 2.1 `sceneLink` moved out of the shared error-style case into its own: `color: scheme.primary, decoration: TextDecoration.underline` — solid underline, distinct from wikilink (tertiary+w600) and the wavy error style.
  - [x] 2.2 `previewConventionKinds`' membership carried over via the rename, confirmed.
  - [x] 2.3 Added a style-distinctness test (vs. wikilink and vs. an error kind) and a `previewConventionKinds` membership test.
- [x] Task 3: Add the 4 toolbar buttons (AC: 4)
  - [x] 3.1 4 new `_IconBtn`s added right after the `[[` wikilink button: Dialogue line (`Icons.chat_bubble_outline`, `prefixLines(v, 'Name (emotion): ')`), Passage link (`Icons.call_made`, `insertAtCursor(v, '[[Choice->Passage Name]]')`), Return link (`Icons.undo`, `insertAtCursor(v, '[[back<-Label]]')`), External link (`Icons.link`, `insertAtCursor(v, '[label](url)')`) — grouped between two `VerticalDivider`s alongside wikilink.
  - [x] 3.2 No active/toggle wiring — all 4 use the plain `_apply` pattern, consistent with `[`, `]`, `—`, `(emotion):`.
- [x] Task 4: Update the contract-level docs (AC: 5)
  - [x] 4.1 ARCHITECTURE.md §3.3 updated: passage-link and return-link bullets replaced with the bracket forms (dated 2026-08-05, `<<linkBack>>`/`<<wakeupLink>>`/`returnMacros` explanation kept unchanged); the `[[Wikilinks]]` note updated to state the separator-based disambiguation instead of an absolute "never passage jumps" claim.
  - [x] 4.2 project-context.md updated in 3 places (more than originally scoped, found during implementation): the "Canonical player-choice / link form" + "Return links" bullets, the "Wikilinks (explicit edges)" bullet in Lore card conventions, and the "Anti-patterns" bullet that said `[[wikilinks]]` are "never passage jumps" — all three stated the old absolute rule and would have been left contradicting the new behavior if not caught.
- [x] Task 5: Tests (AC: 4)
  - [x] 5.1 4 widget tests added — one per new button, asserting the exact inserted buffer text.
  - [x] 5.2 Round-trip test: a Passage-link insert produces a buffer where `matchConventions` finds `ConventionKind.sceneLink`.
  - [x] 5.3 Round-trip test: a Dialogue-line insert produces a buffer where `matchConventions` finds `ConventionKind.dialogueSpeaker`.
- [x] Task 6: Hygiene gates (AC: 1–5)
  - [x] 6.1 `flutter analyze` clean.
  - [x] 6.2 `flutter test` green — 309/309. **Caught during this task, not before:** two test files outside the 3 files my initial `scenePassageLink`-name grep found — `convention_highlighting_controller_test.dart` and `markdown_preview_test.dart` — asserted the *behavior* (`[[a->b]]` gets the wavy error style) without referencing the enum by name, so the compile-error safety net didn't catch them. Both fixed: the highlighting-controller test's 3-suspect-markup case swapped `[[a->passage]]` for an unterminated `[[Selena` example (still 3 genuine error kinds), and gained a new explicit "scene link is NOT an error" test; the markdown-preview test was rewritten from "is flagged as an error" to "is styled distinctly, not as an error."
  - [x] 6.3 Confirmed via `git status --porcelain` on the JS-core/fixture/loader/model paths — empty, no changes.
  - [x] 6.4 Migration regexes delivered to KseiPo in the completion summary (see below).

### Review Findings

- [x] [Review][Patch] `_matchLine`'s new comment claims sceneLink "must be collected... before the generic wikilink pattern" for precedence — factually wrong, `_resolveOverlaps` sorts strictly by `_priority()`, collection order has no effect [apps/mobile/lib/lore/convention_matcher.dart] — applied: rewrote the comment to correctly attribute precedence to `_priority()`
- [x] [Review][Patch] External link's `[label](url)` template: the `[label]` segment matches `_placeholder` and renders with variable-placeholder styling (italic, tertiary) in the raw editor — misleading for a hyperlink, and untested [apps/mobile/lib/lore/convention_matcher.dart, apps/mobile/test/lore/convention_matcher_test.dart] — applied: added a negative lookahead `(?!\()` to `_placeholder` so `[label](url)`'s bracket isn't matched, plus a regression test
- [x] [Review][Patch] Dialogue line uses `prefixLines` unconditionally — selecting multiple lines and tapping the button duplicates the literal `Name (emotion): ` template onto every touched line [apps/mobile/lib/app/editor_toolbar.dart] — applied: new `_insertDialogueLine()` collapses the selection to its start before calling `prefixLines`, so only one line is ever prefixed; regression test added
- [x] [Review][Patch] `Icons.undo` for "Return link" carries a near-universal "revert my last edit" connotation [apps/mobile/lib/app/editor_toolbar.dart] — applied: swapped to `Icons.keyboard_return`
- [x] [Review][Patch] "matching a configured `returnMacros` entry" reads as a validated guarantee when it's actually just an authoring convention [ARCHITECTURE.md, _bmad-output/project-context.md] — applied: reworded to "by convention, naming a configured `returnMacros` entry — not validated by the matcher" in both files
- [x] [Review][Defer] Before this story, `[[Continue->Passge Name]]` (a typo'd target) was flagged as suspect markup; now it's a valid, unflagged `sceneLink` — real loss of an incidental error signal [apps/mobile/lib/lore/convention_matcher.dart] — deferred, this is the explicit, already-discussed tradeoff of choosing pure syntactic disambiguation over a semantic namespace lookup (which needs the not-yet-built scene↔passage bridge); revisit if/when Story 3.1's linter or the bridge exists
- [x] [Review][Dismiss] insertAtCursor overwrites an existing selection for the 3 new template buttons — matches the pre-existing, already-documented behavior of `insertAtCursor` shared by the 4 untouched insert-only buttons, not a new regression
- [x] [Review][Dismiss] Combined/repeated separators (`[[a->b|c]]`) produce one loosely-defined sceneLink token — degenerate but total (no crash), consistent with this story's own established AD-8 threshold (see the `[[->]]` empty-label/target test)
- [x] [Review][Dismiss] No in-repo migration tooling/script ships with this story — matches KseiPo's explicit direction this session ("no migration tooling/script/test... I will run it myself")
- [x] [Review][Dismiss] sprint-status.yaml flips to `review` in the same diff that does the work — matches the established dev-story workflow pattern used consistently all session
- [x] [Review][Dismiss] Field-order ambiguity between the two link templates (which side is label vs. target/type) with "no in-app cue" — the inserted placeholder words themselves ("Choice"/"Passage Name" vs. "back"/"Label") already disambiguate; no separate tooltip/hint needed
- [x] [Review][Dismiss] Speculative style-collision risk between `sceneLink` and other `scheme.primary`-colored kinds in a hypothetical low-contrast theme — unverified, no demonstrated reachability

**Process note:** the Blind Hunter layer was given an incomplete diff for this review — `markdown_preview_test.dart`'s hunk was omitted when the prompt was assembled. Re-verified that file's change directly (and the Acceptance Auditor's independent full-suite run, 309/309, covered it) — the change is sound.

## Dev Notes

### What changes, precisely

**File to MODIFY — `apps/mobile/lib/lore/convention_matcher.dart`:**
- `ConventionKind.scenePassageLink` → `ConventionKind.sceneLink`, removed from `errorKinds`.
- `_scenePassageLink` regex → `_sceneLink`, widened to add `|` as a third separator alternative.
- `_matchLine`'s existing gated call site, renamed only.
- `_priority()`'s case renamed only — **no renumbering**, same slot (3), still ahead of `wikilink` (6).

**File to MODIFY — `apps/mobile/lib/app/convention_styles.dart`:**
- `sceneLink` gets its own `styleForConvention` case (moved out of the shared error-style group).
- `previewConventionKinds`'s existing membership carries over via the rename (no new set-membership edit).

**File to MODIFY — `apps/mobile/lib/app/editor_toolbar.dart`:**
- 4 new plain-insert buttons, no new pure-op types needed (Story 2.14 already added everything `unwrap`/`unprefixLine`-shaped this story could need, but none of these 4 buttons toggle, so they're not used here).

**Files to MODIFY — `ARCHITECTURE.md`, `_bmad-output/project-context.md`:**
- Doc-only changes reflecting the new canonical forms (Task 4).

**No changes to:** `convention_highlighting_controller.dart` (consumes `ConventionKind.values` generically), `file_editor.dart`, `entity_detail_page.dart`, `markdown_preview.dart` (consumes the kind-sets generically), `lore_model.dart`, `lore_loader.dart`, any JS-core file, any golden fixture, `_unterminatedWikilink`'s malformed-`[[` detection (orthogonal — still correctly flags a genuinely unclosed `[[` regardless of whether a separator would eventually appear).

### Architecture constraints

- **AD-7** (shared matcher, no re-implementation): this is a *reclassification* of an existing pattern, the cleanest possible form of "extend, don't fork." Resist the urge to add a brand-new separate pattern alongside the old one — the existing `_scenePassageLink` regex already has the right shape (only needs `|` added) and the right precedence slot (already ahead of `wikilink`).
- **AD-9** (pure Dart in `lore/`, no Flutter): unchanged, the widened regex stays plain Dart.
- **AD-8/NFR7** (total/never-crash): the regex is still linear (single alternation, negated character class, same shape as `_leakedTwee`/`_leakedHtml`) — no new backtracking risk from adding one more alternative.
- **Exhaustive-switch discipline**: `_priority()` and `styleForConvention()` are both exhaustive switches with no `default`. Renaming the enum value forces Dart's compiler to flag every call site that still says `scenePassageLink` — this makes the rename close to impossible to do incompletely (the build won't succeed until every switch case and reference is updated), which is exactly why Task 1.5's test-rewrite list can be trusted as complete once `flutter analyze`/`flutter test` are clean.

### Previous story intelligence

- **From Story 2.5/2.6**: every matcher pattern follows one shape (top-level `RegExp`, a `_matchLine` candidate, a `_priority()` slot). This story doesn't add a new shape — it repurposes an existing one, which is a smaller, lower-risk change than Story 2.15's first draft (which would have added a brand-new pattern for a different prose form). The full-replacement decision actually *simplified* the matcher work versus keeping both old and new forms recognized in parallel.
- **From this session's design discussion** (2026-08-05): the reason this story doesn't need the scene↔passage bridge is worth restating in code review if it comes up again — disambiguation here is 100% syntactic (presence/kind of separator), never a semantic lookup against a passage/entity namespace. Don't let a future story's code review flag "this doesn't validate the target passage exists" as a defect in *this* story — that validation is explicitly out of scope, tied to infrastructure (the bridge) that isn't built yet.
- **Testing philosophy** ([[testing-emphasis]]): Task 1 (the matcher reclassification) is real business logic — thorough unit tests, including the regression guard that a separator-less bracket pair still yields `wikilink`. Task 3 (toolbar buttons) is simple template inserts; Task 5's tests should stay to one assertion per button plus the two round-trip-through-the-matcher proofs (5.2/5.3), not exhaustive UI coverage.

### Project Structure Notes

- No new files, no new dependencies.
- This is the first story to **rename** an existing `ConventionKind` (2.6 only *added* error kinds; 2.13/2.14 only *consumed* existing kinds without touching the matcher). Treat the rename as the primary risk surface — grep for `scenePassageLink` after implementation to confirm zero remaining references anywhere in `apps/mobile/`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.15, lines 434–450 (original open question)]
- [Source: ARCHITECTURE.md — §3.3, lines 210–254, the full scene-file prose-convention contract including the current canonical forms and the `returnMacros`/`<<linkBack>>`/`<<wakeupLink>>` config explanation]
- [Source: apps/mobile/lib/lore/convention_matcher.dart — full file: `ConventionKind` enum, `errorKinds`, `_scenePassageLink`, `_matchLine`, `_priority()`]
- [Source: apps/mobile/lib/app/convention_styles.dart — full file: `styleForConvention`, `previewConventionKinds`]
- [Source: apps/mobile/lib/app/editor_toolbar.dart — full file: existing button row, `_apply`/`insertAtCursor`/`prefixLines`]
- [Source: apps/mobile/test/lore/convention_matcher_test.dart — lines 124–132, 146–149, 158–164, 182–185 (every existing `scenePassageLink` reference needing rewrite, not just rename)]
- [Source: apps/mobile/test/app/convention_styles_test.dart — existing test conventions to mirror]
- [Source: _bmad-output/project-context.md — "Lore & Prose Authoring Conventions" section, current canonical forms to update]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5

### Debug Log References

One gap in the story's own planning surfaced during Task 6: the "grep for `scenePassageLink`" verification strategy assumed a stale reference would always be a compile error (true for anything referencing the enum by *name*), but two tests asserted the *old error behavior* (`[[a->b]]` gets a wavy decoration) via string content, not the enum name — so they compiled fine and only failed at runtime. Found by running the full suite (not just the files identified during design), fixed both.

### Completion Notes List

- Renamed/reclassified `ConventionKind.scenePassageLink` → `sceneLink` in `convention_matcher.dart`: removed from `errorKinds`, regex widened to accept `|` alongside `->`/`<-`, relocated from the error-patterns section to the inline-patterns section, `_priority()` kept the same slot (3) with updated framing
- Gave `sceneLink` its own style in `convention_styles.dart` (primary + solid underline — distinct from wikilink and from the wavy error style); `previewConventionKinds` membership carried over via the rename
- Added 4 toolbar buttons: Dialogue line, Passage link, Return link, External link — all plain inserts, no active-state wiring
- Updated ARCHITECTURE.md §3.3 and project-context.md (3 places in the latter — found 2 more stale "wikilinks are never passage jumps" statements beyond the two originally scoped bullets)
- `flutter analyze` clean; `flutter test` 309/309 (269 pre-existing + 23 from Story 2.14 + 17 new) — including 2 test fixes in files outside the original grep scope (see Debug Log)
- Confirmed zero remaining `scenePassageLink` references anywhere in `apps/mobile/`; confirmed no `lore/` model, loader, or JS-core/fixture changes

### Migration regexes (delivered to KseiPo)

Two passes, order-independent:

**Passage links:**
```
Find:    \*\*([^*\n]+)\*\*\s*_\(→\s*([^)\n]+?)\s*\)_
Replace: [[$1->$2]]
```

**Return links** (group swap — old form is `**Label** _(↩ type)_`, new form is `[[type<-Label]]`):
```
Find:    \*\*([^*\n]+)\*\*\s*_\(↩\s*([^)\n]+?)\s*\)_
Replace: [[$2<-$1]]
```

### Change Log

- 2026-08-05: Unified scene-navigation link formats and expanded toolbar tokens — reclassifies an existing matcher pattern rather than adding a new one, updates ARCHITECTURE.md/project-context.md, 309 tests pass (Story 2.15)
- 2026-08-05: Addressed code review findings — 5 patches applied (comment accuracy, placeholder-misclassification fix for external links, multi-line dialogue-line fix, icon swap, doc wording), 1 item deferred to deferred-work.md. One process note: the Blind Hunter review layer was given an incomplete diff (missing `markdown_preview_test.dart`'s hunk); re-verified that file directly, no issue found.

### File List

- MODIFIED: apps/mobile/lib/lore/convention_matcher.dart
- MODIFIED: apps/mobile/lib/app/convention_styles.dart
- MODIFIED: apps/mobile/lib/app/editor_toolbar.dart
- MODIFIED: apps/mobile/test/lore/convention_matcher_test.dart
- MODIFIED: apps/mobile/test/app/convention_styles_test.dart
- MODIFIED: apps/mobile/test/app/editor_page_test.dart
- MODIFIED: apps/mobile/test/app/convention_highlighting_controller_test.dart
- MODIFIED: apps/mobile/test/app/markdown_preview_test.dart
- MODIFIED: ARCHITECTURE.md
- MODIFIED: _bmad-output/project-context.md
- MODIFIED: _bmad-output/implementation-artifacts/deferred-work.md
