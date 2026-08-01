---
baseline_commit: 62c0fe4e0a6fe90e45b255d00f034688adc2c6f3
---

# Story 2.13: Preview the entity card on the detail screen

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to read my entity card's content rendered on the detail screen,
so that I can see what the card says at a glance without opening the editor.

## Acceptance Criteria

1. **Given** an entity's detail screen, **When** it renders, **Then** the entity card's markdown is shown **rendered read-only** at the top (headings, emphasis, lists, `[[wikilinks]]` as text, etc.) in place of the plain "Card" row.

2. **Given** the rendered card, **When** I tap it (or an explicit edit affordance), **Then** the card opens in the editor — the detail screen stays a read-only preview; editing remains the editor's job.

3. **Given** the card preview, **When** it is built, **Then** it uses the **same** markdown renderer introduced in Story 2.7 (`MarkdownPreview`) — not a second implementation.

4. **Given** a card with malformed or unexpected markup, **When** the preview renders, **Then** it never crashes — it degrades to plain/best-effort text (AD-8 / NFR7), consistent with the rest of the app.

**Scope note:** Only the **card** is previewed; sub-entries/sections remain tappable rows (pre-rendering every leaf would be heavy and defeats the outline — this is a deliberate v0.1 boundary, not an oversight).

## Tasks / Subtasks

- [x] Task 1: Replace the card's `ListTile` row with a rendered preview (AC: 1, 2, 3)
  - [x] 1.1 In `apps/mobile/lib/app/entity_detail_page.dart`, in `_rows()`, replace the first row (the `ListTile` keyed `entity-card`, subtitle `'Card'`) with a tappable widget that wraps `MarkdownPreview(text: entry.text)` — **`entry.text`** is the card's raw markdown ("Raw card text, exactly as decoded" — `lore_model.dart:84`).
  - [x] 1.2 Preserve the `Key('entity-card')` on the new wrapper's outermost widget — 5 existing tests key off it (see Task 3).
  - [x] 1.3 Wrap the preview in a tap target (e.g. `InkWell`) whose `onTap` calls the existing `_open(entry.id)` — same navigation path the old `ListTile.onTap` used. No new navigation logic.
  - [x] 1.4 Import `MarkdownPreview` from `markdown_preview.dart`.
- [x] Task 2: Verify layout — reused widget inside the outer `ListView` (AC: 1)
  - [x] 2.1 Confirmed via a new widget test (long 40-paragraph card + a sub-entry row below it, then `tester.drag` on the outer `ListView`): no exception, the sub-entry becomes visible after the drag — the outer `ListView` is the single effective scroll surface, `MarkdownPreview`'s internal `SingleChildScrollView` shrink-wraps as predicted.
  - [x] 2.2 Not needed — 2.1 showed no problem, so the `scrollable: false` fallback param was not added (no speculative API surface).
- [x] Task 3: Update existing tests broken by the `ListTile` → rendered-preview change (AC: 1, 2, 3, 4)
  - [x] 3.1 Replaced the `find.widgetWithText(ListTile, 'Selena')` assertion with `find.byKey(const Key('entity-card'))` plus a `find.descendant` check that "Selena" renders once within the card.
  - [x] 3.2 Verified: all 5 other `entity-card`-keyed tests passed unchanged (ran the file in isolation before touching tests — only line 211 failed, confirming the key-preservation strategy worked).
  - [x] 3.3 Full suite run — no other assertion depended on the old `ListTile`/`'Card'` structure.
- [x] Task 4: New tests for this story (AC: 1, 2, 3, 4)
  - [x] 4.1 Added: card with `**bold**` markdown asserts `find.byType(MarkdownPreview)` and a bold-styled span.
  - [x] 4.2 Covered by the existing (unchanged) "tapping the card opens it in the editor" test — `tester.tap` on the keyed `InkWell` is a real tap on the whole rendered preview area (the `InkWell` wraps it), so no separate test was needed.
  - [x] 4.3 Added: malformed markup (`# [[unclosed **bold ` + backtick-backtick-backtick + `\n<<if $x >> ]]] [](`) in the card — asserts no exception and the card still renders.
  - [x] 4.4 Added (scaled down from full style-assertion — that's already covered by `markdown_preview_test.dart`, which is reused unchanged; re-asserting exact styles here would be redundant per [[testing-emphasis]]): a `[[wikilink]]` in the card renders as its own text span, proving the renderer is wired end-to-end.
- [x] Task 5: Hygiene gates (AC: 1–4)
  - [x] 5.1 `flutter analyze` — clean, no issues.
  - [x] 5.2 `flutter test` — 264/264 passed (260 pre-existing + 4 new), no regressions.
  - [x] 5.3 No `lore/` model, loader, or JS-core/fixture changes — confirmed only `app/` files touched.

### Review Findings

- [x] [Review][Patch] `InkWell.onTap` is silently swallowed when the card hits the AD-8 fallback path (`SelectableText`), breaking AC2 for malformed cards — the exact cards a user most needs to reach the editor for [apps/mobile/lib/app/entity_detail_page.dart:215] — applied: wrapped `MarkdownPreview` in `AbsorbPointer`; verified with a throwaway probe test before and after the fix, then added a permanent regression test (tapping a malformed card opens the editor)
- [x] [Review][Patch] Test helpers `_allSpans`/`_flatten`/`_spanWith` are a verbatim duplicate of helpers already in `markdown_preview_test.dart` [apps/mobile/test/app/entity_detail_page_test.dart:13-29] — applied: extracted to `test/app/markdown_span_test_helpers.dart`, both test files now import it
- [x] [Review][Defer] No `Semantics` label on the card's `InkWell` (screen-reader announces raw text + generic tap action, not "Card, tap to edit") [apps/mobile/lib/app/entity_detail_page.dart:215] — deferred, no established a11y-labeling pattern elsewhere in the app to hold this story to a higher bar
- [x] [Review][Defer] A blank/whitespace-only card collapses the tap target to ~32px (`SizedBox.shrink()` + 16px padding) [apps/mobile/lib/app/entity_detail_page.dart:218] — deferred, rare edge case (create-entity always seeds `# Title`), minor UX papercut not data-loss
- [x] [Review][Defer] `MarkdownPreview` re-parses on every rebuild with no memoization, now exercised by a new caller (long cards) [apps/mobile/lib/app/markdown_preview.dart] — deferred, this is Story 2.7's own already-accepted, already-deferred tradeoff (see deferred-work.md), not new

## Dev Notes

### What changes, precisely

**File to MODIFY — `apps/mobile/lib/app/entity_detail_page.dart`:**
- `_rows()` (line ~209–219): the first row currently built is:
  ```dart
  ListTile(
    key: const Key('entity-card'),
    leading: const Icon(Icons.badge_outlined),
    title: Text(entry.title),
    subtitle: const Text('Card'),
    onTap: () => _open(entry.id),
  ),
  ```
  Replace with a tappable wrapper around `MarkdownPreview(text: entry.text)`, keeping the same key and the same `onTap: () => _open(entry.id)` call. The AppBar title (`Text(entry?.title ?? widget.entry.title)`, line 189) is unchanged — redundancy with the rendered `# Title` heading inside the card is expected and fine (matches how other apps show both).

**File to REUSE UNCHANGED — `apps/mobile/lib/app/markdown_preview.dart`:**
- `MarkdownPreview({required String text})` — this is exactly the widget Story 2.7 built for this purpose. Its own doc comment (line 12) already names this story: "the detail-card preview (Story 2.13)". Story 2.7's AC5 explicitly required the widget be droppable-in unchanged for this story — honor that; do not fork or reimplement rendering logic (AC3 is a hard constraint).
- It already has AD-8 total behavior (try/catch around parse+build, falls back to `SelectableText(text)` on any failure) — AC4 is satisfied by reuse, not new code. Task 4.3's test exists to *verify* this holds through the detail-page integration, not to add new crash-guarding logic.
- It already applies convention styling (wikilinks, dialogue speaker, placeholders, em-dash, Story 2.6 error kinds) via the shared `convention_matcher`/`convention_styles.dart` — nothing extra needed for AC1's "including `[[wikilinks]]` as text."

**No changes needed to:** `lore_model.dart` (`LoreEntry.text` already holds the raw card markdown — "Raw card text, exactly as decoded"), the loader, or any JS-core contract.

### Architecture constraints

- **AD-7** (shared matcher, no re-implementation): already satisfied by reusing `MarkdownPreview`, which itself reuses `convention_matcher`/`convention_styles.dart`. Do not add a second markdown-to-widget path.
- **AD-8/NFR7** (never-crash, total): the whole point of AC4 — reuse `MarkdownPreview`'s existing try/catch, verify it holds end-to-end from the detail page.
- **AD-10** (full-walk rebuild, no in-memory patching): unaffected — `entry.text` comes from the same `LoreEntry` snapshot the rest of the page already uses; no new fetch/patch path.
- This story's own Story 2.3 precedent: the detail page's outer `ListView(children: ...)` (not `.builder`) was already a deliberate, reviewed tradeoff (small entity trees) — this story does not need to revisit that decision, only be aware of it when reasoning about the nested-scrollable question in Task 2.

### Previous story intelligence

- **From Story 2.7** (the renderer this story consumes): `MarkdownPreview` was purpose-built with this exact reuse in mind (see AC5 of that story and the widget's own doc comment). Its test file `test/app/markdown_preview_test.dart` is the reference for how to assert rendered structure (bold runs, convention styling, AD-8 malformed-input behavior) — mirror that style for Task 4 rather than inventing a new assertion pattern.
- **From Story 2.3** (the page this story modifies): the detail page snapshot/rescan semantics (`_rescan()`, re-walk-and-refind-by-id on return from the editor) are untouched by this story — the card preview is just a different rendering of the same `entry.text` that was already being displayed as a plain `ListTile` title.
- **From Story 2.12's code review** (this session): a UI component's mere presence/absence is not itself a reason to write a test. This story is different in kind — it's testing that markdown *content* renders correctly and that malformed input degrades safely (AD-8), which are real correctness/data-safety concerns, not layout/presence assertions. Keep Task 4's tests focused on rendering correctness and crash-safety, not on pixel-level layout assertions.

### Testing requirements summary

- Update 1 existing assertion that hard-depends on the card being a `ListTile` (Task 3.1); verify (not necessarily modify) the other 4 tests that key off `entity-card`.
- Add rendering-correctness and AD-8 crash-safety tests for the card specifically (Task 4) — consistent with [[testing-emphasis]]'s "business logic and data-safety guards warrant tests" standard, not exhaustive UI coverage.
- No new widget-presence/absence tests beyond what's needed to prove the ACs.

### Project Structure Notes

- No new files.
- No new dependencies (the `markdown` package is already a dependency from Story 2.7).
- No architecture changes — this is a UI composition story: swap one row's rendering, reuse an existing widget.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.13, lines 396–414]
- [Source: apps/mobile/lib/app/entity_detail_page.dart — full file, esp. `_rows()` lines 209–219, `build()` lines 185–207]
- [Source: apps/mobile/lib/app/markdown_preview.dart — full file, esp. doc comment lines 9–24 naming this story]
- [Source: apps/mobile/lib/lore/lore_model.dart — `LoreEntry.text`, line 84]
- [Source: apps/mobile/lib/app/file_editor.dart — line 303, existing `MarkdownPreview` usage pattern (single scrollable context, for contrast with this story's nested-`ListView` context)]
- [Source: apps/mobile/test/app/entity_detail_page_test.dart — full file, esp. lines 178–314 (all `entity-card`-keyed tests) and line 211 (the assertion that must change)]
- [Source: _bmad-output/implementation-artifacts/2-7-preview-rendered-markdown.md — AC5, Task 4 test patterns]
- [Source: _bmad-output/project-context.md — testing emphasis section]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5

### Debug Log References

No issues encountered. The nested-scrollable layout question flagged in Dev Notes (Task 2) was verified empirically with a widget test rather than left as a theoretical risk — confirmed no exception and no trapped scroll gesture, so the speculative fallback API (Task 2.2) was correctly skipped.

### Completion Notes List

- Replaced `entity_detail_page.dart`'s card `ListTile` with an `InkWell`-wrapped `MarkdownPreview(text: entry.text)`, preserving `Key('entity-card')` and the existing `_open(entry.id)` tap handler
- Verified the nested-`SingleChildScrollView`-inside-`ListView` layout is safe via a widget test with a 40-paragraph card + drag gesture — no exception, no trapped scroll
- Fixed the one existing test assertion (`entity_detail_page_test.dart:211`) that depended on the old `ListTile` structure; confirmed the other 5 `entity-card`-keyed tests pass unchanged
- Added 4 new tests: markdown rendering via the shared widget, long-card scroll safety, malformed-markup crash safety (AD-8), and wikilink rendering
- `flutter analyze` clean; `flutter test` 264/264 (260 pre-existing + 4 new)
- No `lore/` model, loader, or JS-core changes
- ✅ Resolved review finding [High]: `InkWell.onTap` swallowed by the AD-8 fallback's `SelectableText` on a malformed card — wrapped `MarkdownPreview` in `AbsorbPointer`; verified with a throwaway probe test (confirmed the bug, then confirmed the fix) before committing to the change, plus a permanent regression test
- ✅ Resolved review finding [Low]: duplicated span-assertion test helpers — extracted to `test/app/markdown_span_test_helpers.dart`, shared by both `markdown_preview_test.dart` and `entity_detail_page_test.dart`

### Change Log

- 2026-07-31: Card preview on the entity detail screen — reuses Story 2.7's `MarkdownPreview` unchanged, 264 tests pass (Story 2.13)
- 2026-07-31: Addressed code review findings — 2 patches applied (gesture-swallow fix + test-helper dedup), 3 items deferred to deferred-work.md

### File List

- MODIFIED: apps/mobile/lib/app/entity_detail_page.dart
- MODIFIED: apps/mobile/test/app/entity_detail_page_test.dart
- MODIFIED: apps/mobile/test/app/markdown_preview_test.dart
- NEW: apps/mobile/test/app/markdown_span_test_helpers.dart
- MODIFIED: _bmad-output/implementation-artifacts/deferred-work.md
