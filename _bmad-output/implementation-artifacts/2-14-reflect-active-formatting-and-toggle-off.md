---
baseline_commit: 883304e32f04b5ab7083599d50c2e1077f967950
---

# Story 2.14: Reflect active formatting in the toolbar and toggle it off

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want the toolbar buttons to show when the cursor/selection is already inside a given formatting, and tapping an active button to remove that formatting,
so that formatting is a true toggle, not a one-way insert.

## Acceptance Criteria

1. **Given** the caret sits inside a formatted span (or a selection is entirely within one), **When** the toolbar renders, **Then** the corresponding button shows an **active** state (bold button active inside `**…**`, H2 active on an `##` line, etc.).

2. **Given** an active formatting button, **When** I tap it, **Then** that formatting is **removed** from the caret's span / the selection (unwrap `**…**`, strip the `## ` prefix, remove the `[[ ]]`), toggling cleanly — while inactive buttons still insert as today.

3. **Given** the highlighter, **When** active-state and toggle-off are built, **Then** they consume the **same `convention_matcher` tokens** (no re-implemented recognition) and the buffer stays raw markdown.

## Scope — which buttons this story touches

`EditorToolbar` has 12 buttons today (`editor_toolbar.dart`). Only **8** map onto a wrap/prefix `ConventionKind` and get active+toggle behavior:

| Button | Op today | ConventionKind | In scope |
|---|---|---|---|
| H1 / H2 / H3 | `prefixLines(v, '# '\|'## '\|'### ')` | `heading` | ✅ |
| Bullet list | `prefixLines(v, '- ')` | `listMarker` | ✅ |
| Numbered list | `prefixLines(v, '1. ')` | `listMarker` | ✅ |
| Bold | `wrapSelection(v, '**', '**')` | `bold` | ✅ |
| Italic | `wrapSelection(v, '_', '_')` | `italic` | ✅ |
| Wikilink `[[` | `wrapSelection(v, '[[', ']]')` | `wikilink` | ✅ |
| `[`, `]`, `—`, `(emotion):` | `insertAtCursor(v, …)` | *(none)* | ❌ — stay plain inserts, no active state, unchanged |

**Do not add active/toggle to the 4 insert-only buttons** — the AC's examples (bold, H2) and Note ("unwrap `**…**`, strip the `## ` prefix, remove the `[[ ]]`") only cover wrap/prefix ops; a plain character insert has no natural "remove" op tied to a token.

## Tasks / Subtasks

- [x] Task 1: Add `unwrap`/`unprefix` pure ops to `editor_toolbar.dart` (AC: 2, 3)
  - [x] 1.1 `unwrap(v, start, end, beforeLen, afterLen)` implemented as a general offset-shift over the removed leading/trailing regions — round-trips `wrapSelection`'s exact caret placement (verified by test, not just reasoned about).
  - [x] 1.2 `unprefixLine(v, lineStart, prefixLen)` implemented; round-trips `prefixLines`' exact caret placement.
  - [x] 1.3 Both reuse `_sel(v)`; clamp all inputs (`start`/`end`/`lineStart`/`prefixLen`) to the text length — never throws.
  - [x] 1.4 8 unit tests added: round-trip wrap/prefix→unwrap/unprefix, wikilink (different before/after lengths), numbered-marker of arbitrary length, out-of-range inputs for both ops.
- [x] Task 2: Active-state derivation — a pure function over tokens + selection (AC: 1, 3)
  - [x] 2.1 `isFormattingActive(tokens, sel, kind)` — collapsed caret: `token.start <= c <= token.end` (inclusive both ends); non-collapsed: entire selection within one token. Used for bold/italic/wikilink, whose token span **is** the formatted region.
  - [x] 2.2 Tokens computed via `matchConventions(controller.text)` directly — no coupling to `ConventionHighlightingController`.
  - [x] 2.3 **Correction found during implementation:** `listMarker` tokens only span the marker itself (e.g. `'- '`, 2 chars) per `_matchLine`, NOT the whole line the way `heading` tokens do — so a naive `isFormattingActive`-style span-inclusion check would only activate the bullet/numbered buttons while the caret sits within the first 2-4 characters of the line, not anywhere in the list item's content (wrong UX, caret drifts out of "active" while still typing the item). Implemented `_lineHasLeadingToken` instead: active requires the selection to sit within one **line**, and that line to have a token of the target kind starting at its very beginning — then `isHeadingActive`/`isBulletActive`/`isNumberedActive` layer the literal-prefix/regex disambiguation on top of that line-level check. Heading's `startsWith` checks turned out to need no length-ordering (a `'## '` line never accidentally matches `startsWith('# ')` — the second character differs), simplifying the original plan.
  - [x] 2.4 10 unit tests added covering all of the above, including the corrected line-based bullet/numbered behavior with an arbitrary-digit numbered marker.
- [x] Task 3: Make `EditorToolbar` reactive to selection changes (AC: 1)
  - [x] 3.1 Converted `EditorToolbar` to `StatefulWidget`; `_EditorToolbarState` adds `widget.controller.addListener(_onChanged)` in `initState`, removes it in `dispose`, `_onChanged` calls local `setState(() {})`. `FileEditor` untouched.
  - [x] 3.2 `build()` reads `widget.controller.value` fresh and recomputes `matchConventions`/all 8 active flags on every rebuild — triggered by the toolbar's own listener on every keystroke and caret move.
- [x] Task 4: Wire active styling + toggle onPressed for the 8 in-scope buttons (AC: 1, 2)
  - [x] 4.1 `_IconBtn`/`_TextBtn` gained a named `active` param (default `false`, so the 4 untouched insert-only buttons need no change beyond the constructor call becoming named-arg); active applies `primaryContainer`/`onPrimaryContainer` via `styleFrom`.
  - [x] 4.2 Wired via 4 small `_toggleXxx` methods on the State class (`_toggleHeading`, `_toggleBullet`, `_toggleNumbered`, `_toggleWrap`) branching active→unwrap/unprefixLine vs. inactive→wrapSelection/prefixLines. **Correction found during implementation:** the originally-planned "derived actual prefix length" only matters for bullet/numbered (leading whitespace and digit-run width genuinely vary — `bulletPrefixLength`/`numberedPrefixLength` read the real match); heading's length turned out to be deterministic per level (`headingPrefixLength(level) = level + 1`) once the active-check itself moved to exact-`#`-count regex matching (Task 2.3's correction) — no separate inspection needed there.
  - [x] 4.3 Confirmed by construction — no code needed; `unprefixLine`/`unwrap` are only ever invoked from an already-computed active token/line, which the active-state gate already constrains to one line/token.
- [x] Task 5: Widget-level tests (AC: 1, 2)
  - [x] 5.1 4 tests added in `editor_page_test.dart` under a new `'active state and toggle-off (Story 2.14)'` group: Bold active-inside/toggle-off, H2 active-on-heading-line/strips-prefix, Bullet active-on-list-line/removes-marker. Set the caret via `controller.selection = ...` (grabbed from the pumped `TextField`), asserted active style via `style?.backgroundColor?.resolve({})` being non-null/null.
  - [x] 5.2 Regression test: Bold with the caret outside any bold span is inactive (`backgroundColor` resolves null) and tapping still inserts `word****` exactly as the pre-existing Story 2.5 test expects.
- [x] Task 6: Hygiene gates (AC: 1–3)
  - [x] 6.1 `flutter analyze` — clean.
  - [x] 6.2 `flutter test` — full suite green, no regressions; the pre-existing 2.5 toolbar/editor tests pass unchanged.
  - [x] 6.3 Confirmed — no `convention_matcher.dart` or `lore/` changes; this story only touched `app/editor_toolbar.dart` and its tests.

### Review Findings

- [x] [Review][Patch] Missing `didUpdateWidget` on `_EditorToolbarState` — the controller listener is only wired in `initState`/`dispose`; if `widget.controller` identity ever changed without a remount, the toolbar would silently keep listening to the stale controller [apps/mobile/lib/app/editor_toolbar.dart] — applied: added `didUpdateWidget` re-subscribing the listener when the controller identity changes
- [x] [Review][Patch] `build()` reimplements a weaker, unclamped selection normalization instead of reusing the file's own `_sel(v)` helper [apps/mobile/lib/app/editor_toolbar.dart] — applied: `build()` now calls `_sel(value)` directly
- [x] [Review][Patch] `isFormattingActive`'s inclusive-both-ends collapsed-caret rule silently redefines `ConventionToken`'s documented half-open `[start, end)` convention — the choice is asserted, not justified, in the code comment [apps/mobile/lib/app/editor_toolbar.dart] — applied: expanded the doc comment to explain why the boundary is deliberately widened
- [x] [Review][Patch] No test exercises italic toggle-off on a star-delimited span (`*text*`) — only underscore round-trips are covered; the strip is correct by coincidence of both delimiters being 1 char, not verified [apps/mobile/test/app/editor_toolbar_test.dart] — applied: added a test detecting + unwrapping a `*italic*` span
- [x] [Review][Patch] No test verifies a multi-line selection against a heading/bullet button correctly stays inactive (the `_lineHasLeadingToken` multi-line fallback path) [apps/mobile/test/app/editor_toolbar_test.dart] — applied: added one test each for heading and bullet
- [x] [Review][Defer] Switching heading level (e.g. tap H2 while H1 is active) or list-marker variant (bullet↔numbered) stacks a second prefix instead of replacing the first, e.g. `## # Title` [apps/mobile/lib/app/editor_toolbar.dart] — deferred, pre-existing `prefixLines` stacking behavior since Story 2.5 (tapping any heading button on an existing heading line already stacked before this story existed); AC2 only requires single-kind toggle-off, not cross-variant switching
- [x] [Review][Defer] Tapping Wikilink while the caret sits inside a `[[a->b]]` (scenePassageLink) or unterminated `[[` (malformedMarkup) span inserts a nested `[[]]` instead of a no-op/fix, since those kinds aren't `ConventionKind.wikilink` [apps/mobile/lib/app/editor_toolbar.dart] — deferred, pre-existing insert-only behavior for these error kinds (identical to pre-2.14 unconditional insert); out of AC2's stated wikilink scope
- [x] [Review][Defer] `matchConventions` runs unmemoized on every toolbar rebuild (every keystroke and every caret move), duplicating work `ConventionHighlightingController` already memoizes on the same controller/text [apps/mobile/lib/app/editor_toolbar.dart] — deferred, same class of tradeoff already accepted for `MarkdownPreview` in Story 2.7 ("not a measured problem... revisit if sluggish"); realistic files are small (project-context.md)
- [x] [Review][Defer] `_headingPrefixByLevel`/`_bulletLinePrefix`/`_numberedLinePrefix` duplicate patterns that live privately in `convention_matcher.dart` — if the matcher is ever extended with a new marker form (e.g. `+` bullets), these local regexes would silently fail to recognize it as active [apps/mobile/lib/app/editor_toolbar.dart] — deferred, fixing cleanly requires exposing matcher internals, out of this story's explicit no-`convention_matcher.dart`-changes scope

## Dev Notes

### What changes, precisely

**File to MODIFY — `apps/mobile/lib/app/editor_toolbar.dart`:**
- Add `unwrap`/`unprefixLine` pure ops beside the existing `insertAtCursor`/`wrapSelection`/`prefixLines` (same file, same total/pure-function style, reusing the private `_sel` clamp helper).
- Add a pure active-state helper consuming `matchConventions` tokens + `TextSelection` (Task 2).
- Convert `EditorToolbar` from `StatelessWidget` to `StatefulWidget` with its own `controller` listener (Task 3) — **this is the one non-obvious architectural change**; without it, active-state would silently fail to refresh live.
- Extend `_IconBtn`/`_TextBtn` with an `active` parameter and distinct styling.
- Rewire the 8 in-scope buttons' `onPressed` to branch active→toggle-off vs. inactive→insert (unchanged for the other 4).

**No changes to:** `convention_matcher.dart` (AC3 — same tokens, no re-implemented recognition), `convention_highlighting_controller.dart`, `convention_styles.dart`, `file_editor.dart`, `editor_page.dart` (the toolbar stays a drop-in `EditorToolbar(controller: _controller)` — its external API/constructor is unchanged, only its internals become stateful).

### Architecture constraints

- **AD-7** (shared matcher, no re-implementation): the matcher owns *finding* spans; this story's line-prefix checks (Task 2.3) are presentation-layer disambiguation among toolbar buttons, reading an already-located token's own text — not new recognition logic. Keep it that way; do not add new `ConventionKind`s for heading levels or list-marker variants (the matcher has no reason to know about UI button granularity).
- **AD-8/NFR7** (total/never-crash): `unwrap`/`unprefixLine` must be as total as the existing three ops — clamp, never throw, mirror the `_sel` pattern. A stale/out-of-range selection reaching an active-derived toggle should be defensively impossible in practice (toggle only fires from an already-computed active token), but the ops themselves must still be safe if called with odd input directly (unit-testable in isolation).
- Pure-function-then-widget layering (established by Story 2.5): keep `unwrap`/`unprefixLine`/the active-state helper as widget-independent pure functions over `TextEditingValue`/tokens, unit-tested without pumping a widget — exactly like the existing three ops. Only the `active` styling and the `onPressed` branching touch the widget layer.

### Previous story intelligence

- **From Story 2.5** (introduced the toolbar + matcher, read in full for this story): the three existing ops (`insertAtCursor`, `wrapSelection`, `prefixLines`) are pure, total functions over `TextEditingValue`; `EditorToolbar` applies them via a single `_apply` helper that does `controller.value = op(controller.value)`. Follow this exact pattern for the two new ops — don't introduce a different mutation style.
- **From this session's Story 2.13 review**: empirically verifying a claim (with a throwaway test) beats trusting a plausible-sounding theory — applied here by working out the heading-token-covers-whole-line detail and the toggle-scope-is-naturally-single-line argument from the actual `_matchLine` source rather than assuming.
- **Testing philosophy** ([[testing-emphasis]], reinforced in the 2.12/2.13 reviews): the pure ops (Task 1, 2) are exactly the kind of business-logic/correctness surface that warrants thorough unit tests — this story's core value. The widget-level tests (Task 5) should stay minimal: prove the wiring works end to end for one case per op type, not exhaustively re-test every button (that's what the pure-function unit tests are for).

### Project Structure Notes

- No new files.
- No new dependencies.
- No architecture changes — this is a pure-function + widget-composition story within `editor_toolbar.dart`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.14, lines 416–432]
- [Source: apps/mobile/lib/app/editor_toolbar.dart — full file, current ops and button wiring]
- [Source: apps/mobile/lib/lore/convention_matcher.dart — full file, `ConventionToken`, `ConventionKind`, `matchConventions`, `_matchLine`'s heading-covers-whole-line behavior]
- [Source: apps/mobile/lib/app/convention_highlighting_controller.dart — the by-text memoization pattern, for reference only (not reused directly per Task 2.2)]
- [Source: apps/mobile/lib/app/file_editor.dart — lines 132, 188-194 (`_onChanged`'s dirty-flip-only setState — the reason Task 3 is required), line 319 (`EditorToolbar(controller: _controller)` call site, unchanged)]
- [Source: apps/mobile/test/app/editor_toolbar_test.dart — full file, existing pure-op test conventions to mirror]
- [Source: apps/mobile/test/app/editor_page_test.dart — lines 365-394, existing widget-level toolbar interaction test pattern (`pumpEditor`, `find.byIcon`, `find.text`)]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5

### Debug Log References

Two design corrections surfaced during implementation, both caught before writing tests (not after a failure):
1. `listMarker` tokens span only the marker itself (`'- '`, 2 chars), not the whole line the way `heading` tokens do — a naive span-inclusion active-state check would only light up bullet/numbered buttons while the caret sat in the first few characters of the line. Fixed with a line-based check (`_lineHasLeadingToken`) before any test was written against the wrong behavior.
2. Heading active-state started as literal-string `startsWith` matching, which doesn't recognize a tab after the `#`s (the matcher's own pattern allows `[ \t]`). Switched to exact-`#`-count regex matching per level, which also made the toggle-off prefix length deterministic (`level + 1`) instead of needing inspection.
3. Bullet/numbered toggle-off prefix length genuinely does vary (leading whitespace, digit-run width) — `bulletPrefixLength`/`numberedPrefixLength` read the real regex match rather than assuming a fixed length; a fixed-length assumption would have corrupted lines like `42. item` → `2. item` instead of `item`.

### Completion Notes List

- Added `unwrap`/`unprefixLine` pure ops to `editor_toolbar.dart`, mirroring the existing `insertAtCursor`/`wrapSelection`/`prefixLines` total-function style; both round-trip their forward op's exact caret placement (verified by test)
- Added active-state derivation: `isFormattingActive`/`_activeToken` (span-inclusion, for bold/italic/wikilink) and `isHeadingActive`/`isBulletActive`/`isNumberedActive` (line-anchored, for H1–H3/bullet/numbered) — all pure functions over `matchConventions` tokens, no new recognition logic
- Converted `EditorToolbar` from `StatelessWidget` to `StatefulWidget` with its own `controller` listener, since `FileEditor`'s host rebuild only fires on the dirty-flag flip — the toolbar needed to be self-sufficient for live active-state updates
- Wired active styling (`primaryContainer`/`onPrimaryContainer`) and toggle branching for the 8 in-scope buttons; the other 4 (`[`, `]`, `—`, `(emotion):`) are unchanged plain inserts
- 23 new unit tests in `editor_toolbar_test.dart`, 4 new widget tests in `editor_page_test.dart`
- `flutter analyze` clean; `flutter test` 292/292 (269 pre-existing + 23 new), no regressions
- Confirmed no `lore/` model, loader, or `convention_matcher.dart` changes — pure UI-layer story
- ✅ Resolved review finding [Low]: missing `didUpdateWidget` — added, re-subscribes the controller listener if its identity ever changes
- ✅ Resolved review finding [Low]: `build()` reused `_sel(v)` instead of a weaker inline selection normalization
- ✅ Resolved review finding [Low]: expanded `isFormattingActive`'s doc comment to justify its deliberately-widened boundary vs. `ConventionToken`'s documented half-open convention
- ✅ Resolved review finding [Low]: added a star-delimited (`*italic*`) toggle-off test — previously only underscore was covered
- ✅ Resolved review finding [Low]: added multi-line-selection-stays-inactive tests for heading and bullet
- 4 items deferred to deferred-work.md: heading/list variant-switching stacks prefixes (pre-existing since Story 2.5), Wikilink nesting on scenePassageLink/malformed brackets (pre-existing), `matchConventions` unmemoized in the toolbar (matches Story 2.7's accepted MarkdownPreview tradeoff), duplicated line-prefix regexes vs. the matcher's private patterns (can't fix without touching convention_matcher.dart, out of scope)

### Change Log

- 2026-07-31: Toolbar active-state + toggle-off — reuses Story 2.5's matcher tokens unchanged, 292 tests pass (Story 2.14)
- 2026-07-31: Addressed code review findings — 5 patches applied (defensive controller handling, selection-normalization reuse, doc clarity, 3 new tests), 4 items deferred to deferred-work.md

### File List

- MODIFIED: apps/mobile/lib/app/editor_toolbar.dart
- MODIFIED: apps/mobile/test/app/editor_toolbar_test.dart
- MODIFIED: apps/mobile/test/app/editor_page_test.dart
- MODIFIED: _bmad-output/implementation-artifacts/deferred-work.md
