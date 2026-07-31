---
baseline_commit: 16eee06adf40efe57394b7536be592086d239b44
---

# Story 2.12: Retire the raw file picker in favor of full browse

Status: done

## Story

As the author,
I want a single, consistent way to reach my files — the lore browse,
so that the app isn't cluttered with a second, weaker navigation path that lists raw filenames instead of titles, RU/EN tabs, and conflict badges.

## Acceptance Criteria

1. **Given** the browse reaches every editable lore file (card, sub-entry, scene, language variant) via categories → entities → the detail tree, **When** the home surface renders, **Then** the "Open a file" button is gone and browsing is the single navigation path in.

2. **Given** the raw picker is no longer user-reachable, **When** it is retired, **Then** `LoreFilePickerPage` and the home handlers that drove it (`_openFile`/`_openFileFrom`) are removed cleanly with no dead or half-wired code.

3. **Given** everything previously reachable through "Open a file", **When** I browse after the change, **Then** each editable lore file remains reachable — no regression in access (verify cards, sub-entries, scenes, and RU/EN variants).

## Tasks / Subtasks

- [x] Task 1: Remove picker surface from home page (AC: 1, 2)
  - [x] 1.1 Delete the `import 'lore_file_picker_page.dart'` line from `home_page.dart`
  - [x] 1.2 Delete the `_openFile()` method (~lines 185–200)
  - [x] 1.3 Delete the `_openFileFrom()` method (~lines 241–256)
  - [x] 1.4 Remove `onOpenFile` from `_ReadyView` — field declaration, constructor parameter, and the `FilledButton.icon('Open a file')` widget (~lines 454, 465, 560–564)
  - [x] 1.5 Remove the `onOpenFile: _openFile` wiring in `_HomePageState.build` (~line 397)
  - [x] 1.6 Verify build succeeds with no dead-code warnings

- [x] Task 2: Delete the picker source file (AC: 2)
  - [x] 2.1 Delete `apps/mobile/lib/app/lore_file_picker_page.dart`

- [x] Task 3: Update tests (AC: 1, 2, 3)
  - [x] 3.1 Delete `apps/mobile/test/app/lore_file_picker_page_test.dart`
  - [x] 3.2 In `apps/mobile/test/widget_test.dart`: remove the AC5 full-loop test (lines 39–67) and update the file-level comment (lines 9–11) to drop picker references
  - [x] 3.3 In `apps/mobile/test/app/browse_test.dart`: remove the `expect(find.text('Open a file'), findsOneWidget)` assertion (~line 462) from the empty-state test
  - [x] 3.4 Run the full test suite — all tests must pass

- [x] Task 4: Resolve deferred-work entries made moot (AC: 2)
  - [x] 4.1 In `_bmad-output/implementation-artifacts/deferred-work.md`, mark as resolved (with date and reason "moot — picker retired in Story 2.12") the following entries:
    - `_openEntry` doesn't `exists`-check a folder that vanished (1-4 review, line 32)
    - trailing slash breaks `_atStart` (1-4 review, line 33)
    - file named exactly `loreDir` passes `exists` check (1-4 review, line 34)
    - `loreDir` pointing at a FILE makes picker root at file path (loreDir=root review, line 60)
  - [x] 4.2 Verify no other deferred entries reference the picker or `_openFile`/`_openFileFrom`

### Review Findings

- [x] [Review][Patch] epics.md Story 2.12 still frames full-removal-vs-escape-hatch as an open decision after the story committed to full removal [_bmad-output/planning-artifacts/epics.md:388] — applied: added a Decision note recording full removal
- [x] [Review][Dismiss] No widget assertion pins down that "Open a file" is absent from the populated ready view [apps/mobile/test/app/browse_test.dart] — declined per testing philosophy: UI component presence/absence is not itself a reason for a test; see project-context.md testing emphasis
- [x] [Review][Patch] Story Dev Notes cite AD-3/AD-8/AD-10 but never trace back to AD-12, the ADR epics.md tags this story against [_bmad-output/implementation-artifacts/2-12-retire-the-raw-file-picker.md] — applied: added AD-12 to Architecture constraints

## Dev Notes

### Decision: full removal, no escape hatch

The epics file mentions the picker MAY be "kept only as an explicitly-justified, clearly-labeled advanced/escape-hatch entry point." Decision: **full removal**. The browse tree (categories → entities → detail tree with sub-entries/scenes/RU+EN variants) reaches every editable file. There is no file type or path the browse cannot reach that the raw picker could. Keeping it "just in case" adds maintenance burden and a confusing second nav path. If a raw-file mode is ever needed, it should be a fresh feature with proper UX, not a rehabilitated scaffold.

### Removal surface — exhaustive list

**Files to DELETE:**
- `apps/mobile/lib/app/lore_file_picker_page.dart` (152 lines) — the picker widget
- `apps/mobile/test/app/lore_file_picker_page_test.dart` (218 lines) — its tests

**File to MODIFY — `apps/mobile/lib/app/home_page.dart`:**
- Line 9: `import 'lore_file_picker_page.dart';` — delete
- Lines 185–200: `_openFile()` method — delete
- Lines 241–256: `_openFileFrom()` method — delete
- Line 397: `onOpenFile: _openFile,` — delete
- Line 454: `final VoidCallback onOpenFile;` field in `_ReadyView` — delete
- Line 465: `required this.onOpenFile,` in constructor — delete
- Lines 560–564: `FilledButton.icon` "Open a file" button — delete

**Test files to MODIFY:**
- `apps/mobile/test/widget_test.dart`:
  - Lines 9–11: update file comment to remove picker mention
  - Lines 39–67: delete the AC5 full-loop test (`'full loop: Open a file -> pick from the picker -> the editor opens it (AC5)'`)
  - The `editor_test_helpers.dart` import (line 7) may become unused after removing the AC5 test — check
- `apps/mobile/test/app/browse_test.dart`:
  - Line 462: remove `expect(find.text('Open a file'), findsOneWidget);`

**File that STAYS — `apps/mobile/lib/app/browse_filter.dart`:**
- Still imported by `root_picker_page.dart` — NOT a picker-only dependency

### Architecture constraints

- **AD-12 / hygiene** (epics.md's tag for this story): removing a redundant, weaker navigation path once a richer one fully subsumes it — this story's entire rationale
- **AD-3** (RepoStorage port): no `dart:io` outside the adapter — this is a pure UI removal, no storage changes
- **AD-8/NFR7** (never-crash): the removed code included error paths; verify no orphaned catch blocks or error-handling references remain
- **AD-10** (full-walk rebuild): no model changes; the rescan-on-return pattern (`if (mounted) await _refresh()`) in `_openCategory` and `_openConflicts` is untouched

### Deferred-work entries resolved by this story

Four picker-specific deferred entries become moot when the picker is deleted:
1. `_openEntry` doesn't `exists`-check a folder that vanished (1-4 review) — the picker's `_openEntry` is gone
2. Trailing slash breaks `_atStart` (1-4 review) — `_atStart` is in the picker, gone
3. File named exactly `loreDir` passes `exists` check (1-4 review) — the `exists` check was in `_openFile`, gone
4. `loreDir` pointing at a FILE makes picker root at file path (loreDir=root review) — `_openFile`'s `exists` check was the vector, gone

### Testing strategy

This is a removal story — the test strategy is subtractive:
- Delete picker tests (they test deleted code)
- Remove assertions that verify the picker button exists
- Remove the full-loop test that exercised the picker → editor flow
- Run the full suite to confirm nothing depended on the removed code
- No new tests needed — the browse path is already covered by `browse_test.dart`, `create_entity_test.dart`, `create_sub_entry_test.dart`, and the widget orchestration tests

### Previous story learnings

- From Stories 2.10/2.11: `heroTag: null` on FABs, `_slugify` pattern, clobber guard pattern — none affected by this story
- The `FakeRepoStorage` in `test/fakes.dart` uses both `entries` (flat list, used by AC5 test) and `dirEntries` (map, used by browse tests) constructors — the AC5 test being removed is the only user of the `entries` path in `widget_test.dart`; `entries` itself is still used elsewhere

### Project Structure Notes

- No new files created
- No new dependencies
- No architecture changes — pure removal/cleanup
- `browse_filter.dart` survives (used by `root_picker_page.dart`)

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.12, lines 376–392]
- [Source: apps/mobile/lib/app/lore_file_picker_page.dart — entire file, 152 lines]
- [Source: apps/mobile/lib/app/home_page.dart — lines 9, 185–200, 241–256, 397, 454, 465, 560–564]
- [Source: apps/mobile/test/widget_test.dart — lines 9–11, 39–67]
- [Source: apps/mobile/test/app/browse_test.dart — line 462]
- [Source: _bmad-output/implementation-artifacts/deferred-work.md — lines 32–34, 60]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

No issues encountered. All edits clean, full test suite passed on first run (260/260).

### Completion Notes List

- Removed `LoreFilePickerPage` import, `_openFile()`, `_openFileFrom()`, `onOpenFile` field/constructor/wiring, and "Open a file" button from `home_page.dart`
- Deleted `lore_file_picker_page.dart` (152 lines) and its test file (218 lines)
- Removed AC5 full-loop picker test from `widget_test.dart`, updated file comment, removed unused `editor_test_helpers.dart` import
- Removed "Open a file" assertion from `browse_test.dart` empty-state test
- Marked 4 deferred-work entries as resolved (moot — picker retired)
- `browse_filter.dart` confirmed still needed by `root_picker_page.dart` — not removed

### Change Log

- 2026-07-31: Retired raw file picker — pure removal, 260 tests pass (Story 2.12)

### File List

- DELETED: apps/mobile/lib/app/lore_file_picker_page.dart
- DELETED: apps/mobile/test/app/lore_file_picker_page_test.dart
- MODIFIED: apps/mobile/lib/app/home_page.dart
- MODIFIED: apps/mobile/test/widget_test.dart
- MODIFIED: apps/mobile/test/app/browse_test.dart
- MODIFIED: _bmad-output/implementation-artifacts/deferred-work.md
