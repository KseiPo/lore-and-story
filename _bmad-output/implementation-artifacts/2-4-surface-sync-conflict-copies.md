---
baseline_commit: 844284b
---

# Story 2.4: Surface sync conflict copies

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want conflict copies shown clearly,
so that I notice and resolve sync collisions instead of editing the wrong file.

## Acceptance Criteria

1. **AC1 (FR17 — visible badged, tappable list):** Given `*.sync-conflict-*.md` files found by the walk (`LoreModel.conflicts`), when the ready surface renders, then the existing conflict **banner is tappable** and opens a **Sync conflict copies** screen listing each conflict copy as a row with a distinct **"conflict" badge**, its filename, and its location; tapping a row opens that copy in the editor so the author can inspect it.
2. **AC2 (FR17 — never parsed, never hidden):** Given a conflict copy, when the model is built, then it is **never** parsed as a normal entity/sub-entry and **never** hidden — it appears only in `LoreModel.conflicts`, never in `entries`/categories. *(Already guaranteed by the Story 2.1b loader; this story renders that data and adds a test that proves it, but must not re-implement or re-filter it.)*
3. **AC3 (resolution stays external — AD-5):** Given the conflicts screen, when I view a conflict copy, then the app **does not** merge, delete, or auto-resolve it — the app only surfaces it (resolution is done with the external syncer/desktop). Opening a copy in the editor to read/compare it is allowed; the app performs no conflict-resolution action.
4. **AC4 (rescan reflects reality — AD-10/FR3):** Given I return from the conflicts screen (and from any editor opened through it), when the ready surface rebuilds, then the conflict count/banner reflects the current disk state via the existing `_refresh` rescan — no cached/stale count.
5. **AC5 (total; hygiene):** The conflicts UI **never throws** on any conflict list (including odd names or an empty relDir); no loader/model change (fixtures 4/4, `npm test` 4/4); `flutter analyze` clean; `flutter test` green with new conflicts-UI tests; the existing conflict-banner tests still pass.

## Tasks / Subtasks

- [x] **Task 1 — `ConflictsPage` (AC: 1, 3, 5)**
  - [x] Add `apps/mobile/lib/app/conflicts_page.dart` — a `StatelessWidget` taking `RepoStorage storage`, `List<ConflictCopy> conflicts`, and `String loreDir`.
  - [x] AppBar title "Sync conflict copies". Body: a `ListView` of the conflicts. Each row: a **conflict badge** (e.g. a red `Chip`/label "CONFLICT" or a filled warning icon in `errorContainer` colors, matching the banner), the copy's **`name`** as the primary line, and its **location** as the subtitle (`relDir`, showing `root` when `relDir == '.'`). Tappable → `EditorPage(storage, path: _repoPath(conflict.id))`.
  - [x] `_repoPath(id)` = `loreDir.isEmpty ? id : '$loreDir/$id'` — the **same** loreDir→repo-path join used by `CategoryEntitiesPage`/`EntityDetailPage` (model ids are loreDir-relative; the editor is repo-relative). Empty `loreDir` passes the id through.
  - [x] **Do NOT** filter, re-detect, or parse conflicts here — render `conflicts` exactly as given (the loader already detected and separated them, Story 2.1b). The app performs **no** resolution action (AD-5): no delete/merge/rename controls; opening a copy in the editor is inspection only.
  - [x] Never throw: an empty list renders an empty state (defensive — the page is only pushed when conflicts exist), a `relDir` of `.` renders as `root`, and unusual names render as-is.
- [x] **Task 2 — Make the home banner tappable → the conflicts screen (AC: 1, 4)**
  - [x] In `apps/mobile/lib/app/home_page.dart`'s `_ReadyView`, wrap the existing `conflict-banner` `Container` so it is **tappable** (e.g. `InkWell`/`Material` around it) and add a trailing affordance (a `chevron_right` in `onErrorContainer` color) signaling it opens a list. **Preserve** `Key('conflict-banner')` and the count text `"$n sync-conflict $copy/copies — …"` up to the `—` (the existing `widget_test.dart` asserts `Key('conflict-banner')` and `textContaining('1 sync-conflict copy —')`). You may change the suffix after the `—` (e.g. `"— tap to view"`).
  - [x] Add an `onOpenConflicts` callback to `_ReadyView` (mirroring `onOpenCategory`) and wire it in `HomePage`: `_openConflicts()` pushes `ConflictsPage(storage: widget.storageFactory(root), conflicts: _lore.conflicts, loreDir: _loreDir)`, then `if (mounted) await _refresh();` on return (so an edit/inspection reflects a fresh rescan — AC4). Build the storage from `_rootPath` exactly like `_openCategory` does; bail if `_rootPath == null`.
  - [x] Keep the banner only shown when `_lore.conflicts.isNotEmpty` (unchanged). Do not touch the entity-count line, Categories list, Refresh, Change folder, or the `_refresh` machinery.
- [x] **Task 3 — Tests (AC: 1–5)**
  - [x] **`ConflictsPage` widget tests** (`test/app/`, `FakeRepoStorage` + a hand-built `List<ConflictCopy>` or one produced by `loadLore` over a repo containing a conflict copy): each conflict renders with a badge + name + location; tapping a row opens `EditorPage` with the copy's content; `relDir == '.'` shows as `root`; an empty list does not throw.
  - [x] **Home routing test** (extend `test/app/browse_test.dart` or `widget_test.dart`): with a conflict present, tapping the `conflict-banner` pushes the conflicts screen and the conflict's filename is listed. Then tapping it opens the editor with the copy's raw content.
  - [x] **AC2 guard test:** with a conflict copy beside a real entity, the conflict's filename does **not** appear as a category/entity in the browse (it's in `conflicts`, not `entries`) — a regression guard that conflicts never leak into the entity lists.
  - [x] Existing conflict-banner tests (`widget_test.dart`: "surfaces sync-conflict copies…", "Refresh re-scans…", "resume re-scans…") must still pass (banner + count preserved). Re-run fixtures (4/4) and `npm test` (4/4). `flutter analyze` clean.

### Review Findings

Cross-model review (Opus 4.8 implementation, 3 Sonnet layers). The Acceptance Auditor independently re-ran the gates (analyze clean, 143/143, `npm test` 4/4, `lore/`+contract git-clean) and **confirmed all 5 ACs implemented**, no regressions. Findings below are gaps around the edges.

**Patch:**

- [x] [Review][Patch] **Opening a conflict copy in the editor drops the one signal that it IS a conflict copy.** The editor AppBar renders `Text(widget.path, overflow: TextOverflow.ellipsis)` — ellipsis clips from the *end*, exactly where the `.sync-conflict-<date>-<time>-<id>.md` marker lives, so a long conflict path shows no conflict indication once you're in the editor. This undercuts the user story ("so that I notice … instead of editing the wrong file"). Add a conflict banner in `EditorPage` when the open file `isConflictCopy` (reuse the exported detector, mirroring the existing lossy-UTF-8 banner). [apps/mobile/lib/app/editor_page.dart:199] (blind)
- [x] [Review][Patch] **Conflict filename/location can overflow the row** — `Text(c.name)`/`Text(location)` have no `overflow`/`maxLines`, and conflict names are inherently long with no spaces to wrap on → RenderFlex overflow. Add `overflow: TextOverflow.ellipsis`. [apps/mobile/lib/app/conflicts_page.dart:73-74] (edge)
- [x] [Review][Patch] **AC4 (rescan-on-return) is untested** — the code is correct (`_openConflicts` → `_refresh`) but no test mutates storage between opening the conflicts screen and popping back to prove the count updates. Add one. [apps/mobile/test/app/] (auditor)
- [x] [Review][Patch] **The non-empty-`loreDir` branch of `ConflictsPage._repoPath` is untested** — every conflict test uses `loreDir: ''`. The formula is currently correct, but nothing pins the join for a `lore-story.json`-configured subfolder. Add a test. [apps/mobile/test/app/conflicts_page_test.dart] (blind+auditor)

**Deferred:**

- [x] [Review][Defer] **Rapid double-tap stacks duplicate routes** — on the banner (two `ConflictsPage`) and a conflict row (two `EditorPage` of the same file, with a last-write-wins race). Pre-existing app-wide pattern deferred repo-wide since 2.1b/2.2/2.3; this is a higher-stakes surface for it, but the trigger (fast double-tap + two manual edits+saves) is narrow. [apps/mobile/lib/app/home_page.dart banner; apps/mobile/lib/app/conflicts_page.dart _open] (edge+blind)

## Dev Notes

### What this story is — UI over data that already exists

Story 2.1b already made the walk **detect** conflict copies and return them in `LoreModel.conflicts`, **never** parsing them as entities and **never** hiding them (the 2.1b loader routes `*.sync-conflict-<date>-<time>-<id>.md` to `conflicts` at both walk levels). It also added the home **count banner** as the "visible signal," with a comment that literally says *"The badged, tappable list is Story 2.4."* **This is that story.** AC2 is therefore already satisfied by the model — your job is to render `conflicts` as a badged, tappable list and make the banner open it. **Do not** add any detection/filtering/parsing of conflict copies in the UI; that lives in the loader and is pinned by tests.

### The data you render (`apps/mobile/lib/lore/lore_model.dart`)

- **`LoreModel.conflicts : List<ConflictCopy>`** — already sorted by `id` (deterministic, Story 2.1b) and handed out as a `List.unmodifiable` view.
- **`ConflictCopy`**: `id` (loreDir-relative path — the editor target, after the loreDir join), `name` (the filename, e.g. `selena.sync-conflict-20240612-093000-K3F9AAA.md`), `relDir` (loreDir-relative directory; **`.` at the lore root**). Show `name` prominently and `relDir` as the location (render `.` as `root`).

### Files being MODIFIED / ADDED (read before editing)

- **`apps/mobile/lib/app/conflicts_page.dart`** (NEW) — the badged list; taps open the copy in `EditorPage`.
- **`apps/mobile/lib/app/home_page.dart`** (MODIFY) — the `_ReadyView` conflict banner (lines ~388–415 today) is a non-tappable `Container` with `Key('conflict-banner')`, an `errorContainer` background, a warning icon, and the count text `"$n sync-conflict $copy/copies — resolve on the desktop"`. **Change:** make it tappable (→ `onOpenConflicts`) with a trailing chevron; keep the Key and the count-through-`—` text. **Add** `_openConflicts()` in `_HomePageState` (push `ConflictsPage`, then `await _refresh()`), and the `onOpenConflicts` field on `_ReadyView`. **Preserve** everything else: the epoch guard / single-flight `_refresh`, the vanished-root re-pick, config resolution, resume rescan, Categories, entity count, Refresh, Change folder, "Open a file".
- **`apps/mobile/lib/app/editor_page.dart`** (reference, unchanged) — `EditorPage(storage, path)` opens any repo-relative file; it already guards lossy-UTF-8 and dirty/save-on-pop. A conflict copy is just a file to it.

### Design decisions (baked into the ACs)

- **A dedicated "Sync conflict copies" screen**, reached by tapping the banner — this is the clean, minimal way to satisfy FR17's "visible badged items" and matches 2.1b's stated intent ("the full badged, tappable list is Story 2.4"). It avoids the complexity of injecting conflict rows into the category/entity lists by `relDir`.
- **Out of scope (note, don't build):** showing a conflict inline *next to the entity it conflicts with* (joining `conflicts` to `entries` by `relDir`) — a plausible future enhancement, but not required by FR17 and not part of this story. Keep the conflicts on their own screen.
- **Tapping opens the copy in the editor for inspection only.** Per AD-5 the app never resolves conflicts (no delete/merge). Editing a copy's text in the editor is possible (it's a real file) but is not a resolution flow; the banner/screen wording keeps "resolve on the desktop" clear. Do **not** add delete/merge/resolve buttons.

### Architecture guardrails

- **AD-5 — the external syncer owns propagation.** Surface conflict copies; never merge/delete/resolve them in-app. This story is display + inspection only. [ARCHITECTURE-SPINE.md#AD-5]
- **AD-10 / FR3 — model rebuilt on rescan.** The conflicts list is a snapshot of `_lore.conflicts`; returning to home rescans (`_refresh`) and the banner/count reflect current disk state. Don't cache a separate conflicts list; read it from the model. [#AD-10]
- **AD-8 / NFR7 — total.** Render whatever `conflicts` contains without throwing; handle `.`/empty relDir and odd names as data. [#AD-8]
- **AD-3 / AD-9 — seam & purity.** The page uses only `RepoStorage` (via the passed `storage`) and the pure `ConflictCopy` model; no `dart:io`, no re-detection logic. [#AD-3, #AD-9]
- **AD-2 — contract untouched.** No loader/model change; conflicts are Dart-only (not in the fixtures/`normalize`). Fixtures 4/4, `npm test` 4/4 (AC5). [#AD-2]

### Previous story intelligence

- **2.1b (done):** `loadLore` returns `LoreModel { entries, conflicts }`. Conflict detection (`isConflictCopy`, anchored to the real Syncthing shape) and the `conflicts` sort-by-id + `List.unmodifiable` are all in the loader. The home banner (`Key('conflict-banner')`) and its widget tests were added here. The 2.1b review **deferred** several conflict scope items to 2.4/later — but note most are loader-scope (conflicts inside `media/`/`.stversions`, conflicts outside `loreDir`, non-`.md` conflicts); **this story is the UI only** and should not expand loader scope. Do not chase those deferrals here.
- **2.2 / 2.3 (done):** established the `_repoPath` loreDir→repo join and the "push a page, `_refresh` on return" pattern in `CategoryEntitiesPage`/`EntityDetailPage`/`home_page`. Reuse the exact same join and the same rescan-on-return wiring for the banner tap. The requirement change (committed `5ee1c50`) means `loreDir` is usually `''`, so `_repoPath` must handle the empty case (it does).
- **Toolchain:** Flutter `C:\programs\flutter\bin` (3.44.7 / Dart 3.12.2); `flutter analyze` + `flutter test`; `npm test` for the JS reference cross-check.

### Git intelligence

`844284b` (Story 2.3 — entity detail tree) is the baseline. The conflict model + banner were committed in `83cf10f` (2.1b); the `_repoPath`/rescan-on-return pattern in `5ee1c50`/`844284b` (2.2/2.3). No conflict-UI work exists yet beyond the banner.

### Library / version policy

No new dependencies. Existing Flutter Material widgets (`ListView`/`ListTile`/`Chip`/`InkWell`/`Navigator`).

### Testing standards

- **`ConflictsPage` → widget tests** in `test/app/` (`FakeRepoStorage` + conflicts from `loadLore` over a seeded repo, or a hand-built `List<ConflictCopy>`): badge + name + location render; tap → editor with the copy's content; `.` → `root`; empty list no-throw.
- **Home routing → extend `browse_test.dart`/`widget_test.dart`:** tap the banner → conflicts screen lists the copy → tap → editor.
- **AC2 regression guard:** a conflict copy beside a real entity never appears as a category/entity.
- **Contract gate:** fixtures 4/4, `npm test` 4/4, `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/` empty. This story touches none of them — verify, don't assume.

### Project Structure Notes

- New UI: `apps/mobile/lib/app/conflicts_page.dart`; modified `apps/mobile/lib/app/home_page.dart`. Pure model in `lore/` unchanged. Consistent with the `app/` (UI) + `lore/` (pure) split.
- Tests: `apps/mobile/test/app/conflicts_page_test.dart` (new) + additions to `browse_test.dart`/`widget_test.dart`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.4] — user story + ACs (FR17)
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR17] — surface `*.sync-conflict-*.md` as visible badged items; never parse or hide
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-5] (syncer owns propagation — surface, never resolve), #AD-10 (rescan), #AD-8 (total), #AD-2 (fixtures)
- [Source: apps/mobile/lib/lore/lore_model.dart] — `LoreModel.conflicts`, `ConflictCopy{id,name,relDir}`
- [Source: apps/mobile/lib/lore/lore_loader.dart] — where conflicts are detected/collected (read-only context; do not modify)
- [Source: apps/mobile/lib/app/home_page.dart] — the `conflict-banner` to make tappable; the `_openCategory`/`_refresh` pattern to mirror
- [Source: apps/mobile/lib/app/editor_page.dart] — `EditorPage(storage, path)`, the tap target
- [Source: _bmad-output/implementation-artifacts/2-1b-syncer-aware-walk-and-rescan.md] — the conflict model, the banner, and the "badged list is Story 2.4" note
- [Source: _bmad-output/project-context.md] — FR17 surfacing rule; conflict copies are NOT already hidden by the browse filter (normal-named `.md`)

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- `flutter analyze` → **No issues found** (after renaming two local test helpers that had leading underscores).
- `flutter test` → **143 passing** (138 → +5): 3 `ConflictsPage` widget tests + 2 home tests (banner→list routing, AC2 no-leak guard).
- **Contract gate (AC5)** → `npm test` 4/4, fixtures pass (part of `flutter test`), and `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/` is **empty** — no loader/model/contract change (this story renders `LoreModel.conflicts`, which 2.1b already produced).
- Existing conflict-banner tests (`surfaces sync-conflict copies…`, `Refresh re-scans…`, `resume re-scans…`) still green — the banner `Key` and count-through-`—` text were preserved.

### Completion Notes List

- **UI over data that already existed.** The 2.1b loader already detects conflict copies and routes them to `LoreModel.conflicts`, never parsing them as entities and never hiding them — so **AC2 was already satisfied by the model**. This story adds the presentation only; the UI does **no** detection/filtering (verified: no conflict logic in the new page, `lore/` git-clean).
- **`ConflictsPage`** (new): a badged, tappable list — each row a red "CONFLICT" badge + the copy's filename + its location (`relDir`, with `.` shown as `root`), plus a top explainer that resolution happens on the desktop. Tapping a row opens the copy in the editor for **inspection** (AD-5 — the app never merges/deletes/resolves; there are no resolution controls).
- **Home banner made tappable** → pushes `ConflictsPage`, then rescans on return (`_refresh`, AC4/AD-10) so the count reflects current disk state. Kept `Key('conflict-banner')` and the `"$n sync-conflict copy/copies —"` text (existing tests assert them); changed the suffix to `— tap to view` and added a chevron affordance.
- **id↔path join reused:** conflict `id`s are loreDir-relative; `ConflictsPage._repoPath` joins `loreDir` before handing to the editor — the same pattern as `CategoryEntitiesPage`/`EntityDetailPage`, correct for the common empty-`loreDir` case.
- **Scope held:** conflicts live on their own screen; not injected inline into the category/entity lists by `relDir` (noted out of scope). No loader-scope deferrals from 2.1b were pulled in (those are loader concerns, not UI).
- **Never-throws (AC5):** empty list → friendly state (defensive; the page is only pushed when conflicts exist), `.` relDir → `root`, odd names render as-is. Covered by a no-throw test.
- No new dependencies.

### File List

**Added:**
- `apps/mobile/lib/app/conflicts_page.dart` (badged, tappable conflicts list; taps open the copy in the editor for inspection)
- `apps/mobile/test/app/conflicts_page_test.dart` (3 tests: badge/name/location, tap→editor, empty no-throw)

**Modified:**
- `apps/mobile/lib/app/home_page.dart` (make the `conflict-banner` tappable → `_openConflicts` pushes `ConflictsPage` then rescans; `onOpenConflicts` on `_ReadyView`; chevron + "tap to view" affordance)
- `apps/mobile/test/app/browse_test.dart` (banner→conflicts-list→editor routing test; AC2 conflict-never-an-entity guard)

**Deliberately NOT modified (verified git-clean):** `lib/lore.js`, `test/fixtures/lore-model/**`, `scripts/**`, `apps/mobile/lib/lore/**` (conflict detection/model are Story 2.1b's; rendered, not changed — AC5).

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-24 | Addressed code review (Opus 4.8 impl, 3 Sonnet layers): 4 patch findings fixed. **Editor conflict banner:** opening a conflict copy now shows an in-editor banner ("This is a Syncthing conflict copy…") via the exported `isConflictCopy` — the AppBar path ellipsis would otherwise clip the `.sync-conflict-…` marker, dropping the one signal that you're in a conflict copy (directly serves the user story). **Overflow:** the conflict row's name/location ellipsize instead of overflowing (conflict names are long, unbroken). **Coverage:** added an AC4 rescan-on-return test (resolve a conflict externally while the screen is open → banner gone on return) and a non-empty-`loreDir` join test. Tests 143 → 145; `flutter analyze` clean; fixtures 4/4; `npm test` 4/4; `lore/`+contract git-verified untouched. 1 finding deferred (double-tap route stacking — pre-existing repo-wide pattern); 3 dismissed (badge color cosmetic; redundant AC2 test; a real category named `root` colliding with the synthetic label — unreachable). |
| 2026-07-24 | Implemented Story 2.4: surface sync conflict copies. New `ConflictsPage` renders `LoreModel.conflicts` (produced by the 2.1b loader) as a badged, tappable list — "CONFLICT" badge + filename + location (`.`→`root`) — with a desktop-resolution explainer; tapping a row opens the copy in the editor for inspection (AD-5: surface only, no resolve/delete/merge). The home conflict banner is now tappable → that screen, rescanning on return (AC4). AC2 (never parsed/never hidden) was already guaranteed by the model; added a regression guard proving a conflict copy never appears as a category/entity. Pure UI: no loader/model change, fixtures 4/4, `npm test` 4/4, `lore/` git-clean. Tests 138 → 143 (+5); analyze clean. No new dependencies. |
