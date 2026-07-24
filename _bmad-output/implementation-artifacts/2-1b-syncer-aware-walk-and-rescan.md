---
baseline_commit: 0f62c8a
---

# Story 2.1b: Syncer-aware walk and rescan

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want the walk to coexist with my syncer and refresh when I come back,
so that browsing reflects the current repo without stale or junk entries.

## Acceptance Criteria

1. **AC1 (FR16 — filter syncer metadata + media):** Given `media/` folders and syncer metadata (`.stfolder`, `.stignore`, `.stversions`), when the walk runs, then they are skipped — nothing inside them appears in the model.
2. **AC2 (FR17 detection — surface, never parse):** Given a `*.sync-conflict-*.md` file (at any level — a card, a sub-entry, a category), when the walk runs, then it is **detected as a conflict item** and returned separately, **never parsed as a normal entity or sub-entry** and **never silently hidden**. (The badge UI is Story 2.4; this story produces the data.)
3. **AC3 (FR3 — rescan on resume + manual refresh):** Given I resume the app or tap a refresh control, when it reloads, then it **re-scans the repo** from disk (a full walk, no live watcher, no cached model — AD-10), and the surfaced conflict-copy count reflects the current disk state.
4. **AC4 (conformance preserved):** Given the shared golden fixtures, when the loader runs, then all four cases still deep-equal `expected.json` — the syncer-aware behavior is additive and Dart-only, and must not change the model shape the fixtures pin.
5. **AC5 (seam + hygiene):** The walk uses only the `RepoStorage` port (no `dart:io` in `lore/`); `flutter analyze` clean; `flutter test` passes including new syncer/conflict tests; `npm test` still 4/4 (the JS reference and shared fixtures are untouched).

## Tasks / Subtasks

- [x] **Task 1 — Detection helpers in the `lore/` slice (AC: 1, 2)**
  - [x] Add `bool isSyncerMetadata(String name)` — true for the hardcoded set `{'.stfolder', '.stignore', '.stversions'}` (FR16, "hardcoded list for MVP"). Applies to directories and files by name.
  - [x] Add `bool isConflictCopy(String name)` — true when `name.endsWith('.md') && name.contains('.sync-conflict-')` (matches Syncthing's `<base>.sync-conflict-<date>-<time>-<id>.md`). Export it (Story 2.4's badge UI will reuse it).
  - [x] Keep both **pure** (no `dart:io`, no Flutter). Unit-test them directly.
- [x] **Task 2 — `LoreModel` result + wire the walk to skip metadata and collect conflicts (AC: 1, 2, 4)**
  - [x] Introduce `LoreModel { List<LoreEntry> entries; List<ConflictCopy> conflicts; }` and `ConflictCopy { String id; String name; String relDir; }` (all loreDir-relative, forward-slash — same identity contract as `LoreEntry`). Add to `lore_model.dart`, export via the barrel.
  - [x] Change `loadLore(RepoStorage, String loreDir)` to return `Future<LoreModel>` (was `Future<List<LoreEntry>>`). One walk, both outputs.
  - [x] In `_walkCategory`: skip a subdirectory when `isSyncerMetadata(name)` (in addition to the existing `media` skip) — do **not** descend, do **not** treat as a category. **This is the critical one:** `.stversions/` holds dated `.md` copies of real files that would otherwise be parsed as bogus entities.
  - [x] In `_walkCategory` and `_buildNode`: when a `.md` file `isConflictCopy(name)`, add it to `conflicts` (loreDir-relative id/relDir) and **skip it** — it is neither an entity, a card candidate, nor a sub-entry, and it must not enter `byBase`.
  - [x] In `_buildNode`: skip `isSyncerMetadata` subdirs too (an unlikely but possible `.stversions` nested inside an entity).
  - [x] Preserve everything from 2.1a exactly (card-exclusion guard, ordering sort, AD-8 read guards, `media` skip). AC4 is non-negotiable.
- [x] **Task 3 — Update the 2.1a callers for the new return type (AC: 4, 5)**
  - [x] `test/lore/lore_model_fixtures_test.dart`: the fixture path becomes `normalize((await loadLore(...)).entries)`; the integration tests use `(await load()).entries`. No behavior change — just `.entries`.
  - [x] Confirm `normalize.dart` is untouched (it takes `List<LoreEntry>`; `conflicts` is Dart-only and not normalized).
- [x] **Task 4 — Rescan on resume + manual refresh, and surface conflicts (AC: 2, 3)**
  - [x] In `home_page.dart`'s ready path (`_refresh`): run `loadLore(storage, _loreDir)` (rebuilt every refresh — AD-10, no caching), and store the entity count and the conflict list in state.
  - [x] Add a **Refresh** action to the ready view that re-runs `_refresh` (the resume path already re-scans, per Story 1.1's lifecycle observer — this adds the *manual* half of FR3).
  - [x] Surface the conflict count in the ready view — e.g. "⚠ N sync-conflict copies" when `N > 0` (a visible signal, per FR17 "surface"). The full badged, tappable list is Story 2.4; a count line is the honest scope here. Also show the loaded entity count as observable proof the walk ran.
  - [x] Keep it thin. Do **not** build category/entity browsing — that is Story 2.2. The raw top-level `listDir` display from Story 1.1 can stay or be replaced by the entity count; do not expand it into a browser.
- [x] **Task 5 — Tests (AC: 1, 2, 3, 4, 5)**
  - [x] Loader syncer/conflict integration tests (temp dir via `AllFilesRepoStorage`, like the 2.1a integration tests — **not** shared fixtures): a `.stversions/old~date.md` and `.stfolder/` are skipped (absent from `entries`); a top-level `frank.sync-conflict-20240101-120000-ABC.md` is in `conflicts`, not `entries`; a conflict copy of a **sub-entry** inside an entity folder is in `conflicts`, not in the entity's `children`/`items`; a normal entity beside them still loads.
  - [x] Helper unit tests: `isSyncerMetadata`, `isConflictCopy` (positive + negative: `frank.md` is not a conflict; `frank.sync-conflict-….md` is; `.stversions` is metadata; `media` is not).
  - [x] Re-run the fixture conformance suite — all 4 cases still pass (AC4).
  - [x] Widget test: the ready view shows the conflict-copy count when the model has one, and tapping Refresh re-invokes the scan (assert via a `FakeRepoStorage` whose listing includes a conflict copy).
  - [x] `flutter analyze` clean; `flutter test` green; `npm test` still 4/4.

### Review Findings

All 5 ACs were independently confirmed satisfied (fixtures 4/4, `npm test` 4/4, shared contract provably untouched, tests verified non-tautological). The findings below are gaps in paths the ACs and tests did not cover.

**Filtering / detection:**

- [x] [Review][Patch] **The loader's filter is a 3-name allowlist while the browse UI uses a `startsWith('.')` denylist — the walk descends into `.git`, `.github`, `.obsidian`, `.trash`, and any future `.st*` name.** `.github/**/*.md` would load as real lore entities. Reachable today: Story 1.4 explicitly supports pointing the repo root *at* the lore folder, making `loreDir` the repo root. Align the loader with the same all-dot rule KseiPo chose for browsing in 1.4 (which also covers `.lore-tmp-*`, whose skip the storage adapter already promises "the Epic 2 syncer-aware walk" would do). [apps/mobile/lib/lore/lore_loader.dart:73-80, 187, 288]
- [x] [Review][Patch] **`isConflictCopy` is a substring match — a legitimately-named file silently disappears from the model.** A note called `troubleshooting.sync-conflict-recovery.md` is routed to `conflicts`, vanishing from the tree with only a red banner as the signal. Tighten to the real Syncthing shape (`.sync-conflict-<8 digits>-<6 digits>-<id>.md`). [apps/mobile/lib/lore/lore_loader.dart:88-89]
- [x] [Review][Patch] **Both detectors are case-sensitive on a case-insensitive filesystem.** Android's `/storage/emulated/0` FUSE layer is case-preserving/insensitive, and Windows-authored repos sync down `.StVersions` or `FRANK.SYNC-CONFLICT-….MD`, neither of which matches. [apps/mobile/lib/lore/lore_loader.dart:80, 89]

**Model contract:**

- [x] [Review][Patch] **`ConflictCopy.relDir` is `''` at the lore root where `LoreEntry.relDir` is `'.'`** — breaking the "same identity contract as `LoreEntry`" the story explicitly promised. Story 2.4 will join conflicts to entries by `relDir`, and root-level conflicts will fail to match. The only test asserting `relDir` uses `characters`, the case that happens to work. [apps/mobile/lib/lore/lore_loader.dart:161]
- [x] [Review][Patch] **`conflicts` ordering is non-deterministic** — `_buildNode` records conflicts from the raw `listDir` order *before* its `files.sort`, unlike `entries`/`children[]` which were carefully sorted for determinism. Story 2.4's list will reorder itself between refreshes. Sort conflicts by `id`. [apps/mobile/lib/lore/lore_loader.dart:289]
- [x] [Review][Patch] **`LoreModel` hands out the loader's live growable lists** while `LoreModel.empty` hands out `const []` — so a caller mutating `entries` corrupts the model in one case and throws in the other. `List.unmodifiable` at the boundary. [apps/mobile/lib/lore/lore_model.dart:19-30; lore_loader.dart:153]

**Rescan / error handling:**

- [x] [Review][Patch] **`_refresh` has no error handling and its future is discarded at every call site — a throw strands the app on a spinner forever.** `_Stage` has no `error` member, and `_refresh` (a `Future<void> Function()`) is assigned to a `VoidCallback`, silently dropping the future and its error. This is the same class of gap the 1.3 and 1.4 reviews caught (`ProjectConfig` catch-all, editor load/save catch-all) — asserted at the loader level (AD-8) but never enforced at the call site. [apps/mobile/lib/app/home_page.dart:54, 67, 254]
- [x] [Review][Patch] **Returning from the editor does not rescan** — save a file, pop back, and the entity count and conflict banner still show the pre-edit walk until backgrounding or a manual Refresh. FR3's "reflects the current repo" is unmet on the most common in-app path. [apps/mobile/lib/app/home_page.dart:151-192]
- [x] [Review][Patch] **Refresh is undebounced: N taps start N concurrent full walks.** The epoch guard applies only the last result but cancels nothing, so all N complete their I/O — multiplying disk load exactly when the app is slow enough that the user is tapping repeatedly. [apps/mobile/lib/app/home_page.dart:254]

**Text / tests / docs:**

- [x] [Review][Patch] **"1 lore entities"** — the entity count is not pluralized while the conflict banner three lines below pluralizes correctly, and the widget test asserts the buggy string exactly, cementing it. [apps/mobile/lib/app/home_page.dart:328-331]
- [x] [Review][Patch] **Stale doc comment now contradicts the code** — `HomePage`'s header still says the resume re-check "is not the Epic 2 model rescan of AD-10". As of this story, `_refresh` *is* that rescan. [apps/mobile/lib/app/home_page.dart:15-18]
- [x] [Review][Patch] **Test gaps on the artifacts the domain actually produces** — no coverage for `.git`/`.github`, uppercase variants, a false-positive filename containing `.sync-conflict-`, `.syncthing.*.tmp`/`~syncthing~*.tmp`, or `.lore-tmp-*`. Also: the rescan test asserts with `textContaining('1 sync-conflict copy')`, which also matches "11 sync-conflict copies"; and the **resume** half of AC3 has no test (only manual Refresh). [apps/mobile/test/lore/lore_loader_test.dart; apps/mobile/test/widget_test.dart]

**Deferred:**

- [x] [Review][Defer] **Conflict copies inside skipped dirs (`media/`, `.stversions/`) are never surfaced** — the `continue` fires before any conflict check, so AC1's filter silently defeats AC2's "never hidden". Defensible under AD-5 for syncer-internal dirs (a conflict inside `.stversions` is meaningless noise), but the `media/` case is a real asset conflict the app is structurally unable to report. Unstated AC1/AC2 interaction; revisit with Story 2.4. [lore_loader.dart:187, 288]
- [x] [Review][Defer] **An entity whose only card is a conflict copy silently demotes to a category** — its `tree`/`children[]` vanish and its sub-entries are promoted to top-level entities. Requires the original card to be deleted (Syncthing normally keeps it), and the "right" behavior is a product question (what *is* an entity whose card is only conflicted?). [lore_loader.dart:196-216]
- [x] [Review][Defer] **A conflict copy is lost when its entity's card read fails** — `_makeEntry` reads the card before `_buildNode`, so an `RepoStorageException` skips the entry and the folder's conflicts are never recorded. The active-syncer race is exactly what FR17 exists for. [lore_loader.dart:246, 236-238]
- [x] [Review][Defer] **Every directory is listed twice per walk** — the card probe's `listDir` result is discarded, then `_walkCategory`/`_buildNode` lists the same directory again, doubling syscalls on every resume (AD-10 mandates a full rebuild). Real NFR6 cost; deferred because restructuring the walk right after conformance carries risk disproportionate to a few-hundred-file repo. [lore_loader.dart:196-199, 212, 283]
- [x] [Review][Defer] **Conflict copies outside `loreDir` are never surfaced** — a conflict in `story/` or the repo root is invisible and the banner reads a false all-clear. FR17 is repo-scoped; the loader is `loreDir`-scoped. Scope expansion — pair with 2.4. [lore_loader.dart:150-153]
- [x] [Review][Defer] **Conflict copies of non-`.md` files are dropped entirely** — notably `lore-story.json.sync-conflict-….json`: the project config is conflicted and the author is never told. Good catch; expanding beyond `*.sync-conflict-*.md` is a scope change from the FR. [lore_loader.dart:88-89]
- [x] [Review][Defer] **No progress feedback during a rescan** — the ready view stays interactive showing the previous counts, then swaps silently; a Refresh tap on a large repo gives no feedback. Story 2.2 restructures this surface anyway. [home_page.dart:71-123]
- [x] [Review][Defer] **A `loreDir` that is missing or is a file is indistinguishable from an empty repo** ("0 lore entities"). [lore_loader.dart:150-154]
- [x] [Review][Defer] **A directory whose name matches the conflict pattern is descended, not recorded.** Narrow. [lore_loader.dart:182-216]

## Dev Notes

### What this story is

The **syncer-aware layer** on top of the 2.1a loader: make the walk coexist with
Syncthing's on-disk artifacts, and make the model rebuildable on demand. Two
distinct jobs — *filter* the syncer's own metadata (junk that must never appear),
and *surface* conflict copies (real files the author must see and resolve, never
hidden and never parsed as content). Plus the rescan mechanism (AD-10).

### 🚫 This is Dart-only — do NOT touch `lib/lore.js` or the shared fixtures

Syncer-awareness is **"New on the Dart side (no JS equivalent)"** (addendum §E),
and AD-5 is a mobile rule. The desktop reference does not do this. Therefore:

- **Do not modify `lib/lore.js`, `test/fixtures/lore-model/**`, or `normalize.js`.**
  The fixtures contain no `.st*` dirs and no conflict copies, so adding this
  behavior **cannot change any golden** — AC4 must stay green with the fixtures
  exactly as they are. `npm test` must still pass 4/4.
- Test this behavior with **Dart-only integration tests** over temp dirs (the same
  pattern as 2.1a's `loadLore (beyond fixtures)` group), never by adding a shared
  fixture case (a shared case would require the JS reference to implement
  syncer-awareness, which it deliberately does not).
- `conflicts` is a Dart-only field: it is **not** part of `normalize` and not
  pinned by any golden. Keep it off the normalized projection.

### Files being MODIFIED (read before editing)

- **`apps/mobile/lib/lore/lore_loader.dart`** — the 2.1a walk. Current state:
  `loadLore` returns `List<LoreEntry>`; `_walkCategory` skips `media` and resolves
  the entity card from a directory listing (the AD-8 fix); `_buildNode` groups
  files by base, applies the `base != cardBase` flat-push guard, and sorts files
  for deterministic `children[]`. **Change:** return `LoreModel`; skip
  `isSyncerMetadata` dirs; route `isConflictCopy` files to `conflicts` instead of
  `byBase`/entities. **Preserve:** every 2.1a behavior the fixtures pin (AC4).
- **`apps/mobile/lib/lore/lore_model.dart`** — add `LoreModel` and `ConflictCopy`;
  keep the existing types byte-for-byte (the fixtures pin them).
- **`apps/mobile/lib/lore/lore.dart`** — export the new types + helpers.
- **`apps/mobile/lib/app/home_page.dart`** — `_refresh` currently: permission →
  root read → `exists('')` vanished-root check → `listDir('')` → `resolveProjectConfig`
  → set ready. **Add:** a `loadLore(storage, _loreDir)` call on the ready path,
  storing entity count + conflicts; a Refresh button; a conflict-count line.
  **Preserve:** the epoch guard, the vanished-root check, the config resolution,
  and the `_openFile`/`_openEntry` navigation from 1.4. Do not regress them.
- **`apps/mobile/test/lore/lore_model_fixtures_test.dart`** — update call sites for
  the `LoreModel` return (`.entries`). Fixtures themselves unchanged.

### Architecture guardrails

- **AD-5 — the external syncer owns propagation.** Filter `.stfolder`/`.stignore`/
  `.stversions`; surface `*.sync-conflict-*.md` as a badged item (badge is 2.4),
  never parse it as an entry. The app never merges or resolves conflicts — it just
  makes them visible. [ARCHITECTURE-SPINE.md#AD-5]
- **AD-10 — model rebuilt, never patched; no live watcher.** The rescan is a full
  `loadLore` walk on resume/refresh. Do not cache the model in a static/singleton;
  the loader is stateless and rebuilt each call (it already is). [#AD-10]
- **AD-8 — total walk.** A conflict copy or metadata dir is data to route, not a
  fault; the 2.1a read guards stay. [#AD-8]
- **AD-2 — fixtures are the contract, and this behavior is outside it.** Additive,
  Dart-only, fixtures untouched. [#AD-2]
- **AD-3 / AD-9 — seam.** `loadLore` still takes only `RepoStorage`; no `dart:io`
  in `lore/`. [#AD-3, #AD-9]
- **NFR6 — responsiveness.** A full rescan on every resume is by design (AD-10);
  keep the walk O(files) and don't add per-file overhead. Real repos are a few
  hundred files. [prd.md#NFR6]

### Detection specifics (get these exactly right)

- **Syncer metadata (FR16, hardcoded):** `.stfolder` (dir), `.stversions` (dir),
  `.stignore` (file). `.stignore` is not a `.md`, so it is never considered as
  content anyway — but include it in the name set for clarity/completeness. The
  load-bearing skips are the **directories** `.stfolder` and especially
  `.stversions` (which contains real `.md` version copies).
- **Conflict copies (FR17):** Syncthing names them
  `<base>.sync-conflict-<yyyymmdd>-<hhmmss>-<modid>.<ext>`, e.g.
  `selena.sync-conflict-20240612-093000-K3F9AAA.md`. Detect with
  `name.endsWith('.md') && name.contains('.sync-conflict-')` — matches the FR's
  `*.sync-conflict-*.md` glob without over-fitting the exact date format.
- **Do NOT hide conflict copies in the browse filter.** `app/browse_filter.dart`
  hides dot-files and `media/`; a conflict copy is a normal-named `.md` (no dot
  prefix), so it is *not* already hidden — and it must not be. FR17 wants it
  surfaced with a badge, which is why the loader routes it to `conflicts` rather
  than dropping it. (The 1.4 review explicitly deferred hiding conflict copies for
  this reason.)

### Previous story intelligence

- **2.1a (done):** `loadLore` walks via `RepoStorage` (`listDir`/`read`/`exists`),
  skips `media`, resolves cards from a directory listing (AD-8), and sorts files for
  deterministic `children[]`. The card-exclusion guard and the ordering are pinned
  by the goldens — do not disturb them. `loadLore` currently returns
  `List<LoreEntry>`; changing it to `LoreModel` is the one API change, and the only
  caller is the fixture test.
- **1.4 (done):** `home_page._refresh` is epoch-guarded and already re-scans on
  `AppLifecycleState.resumed`; the ready view has Open-a-file / Change-folder /
  tappable top-level entries. `app/browse_filter.dart` hides dot-files + `media` for
  *browsing UI* (not the model). The loader is not yet displayed — this story wires
  a minimal count/refresh; full browsing is 2.2.
- **Toolchain:** Flutter is now global at `C:\programs\flutter\bin` (Flutter 3.44.7,
  Dart 3.12.2). `flutter analyze` + `flutter test` for Dart; `npm test` for the JS
  reference conformance cross-check.

### Git intelligence

`0f62c8a` (2.1a — lore loader port + contract change) → `eef3327` (1.4) → … This
story builds directly on the 2.1a loader committed in `0f62c8a`.

### Library / version policy

No new dependencies. Pure Dart string/regex checks and the existing `RepoStorage`
port cover everything.

### Testing standards

- Syncer/conflict behavior → **temp-dir integration tests** (`AllFilesRepoStorage`),
  never shared fixtures. Cover: `.stversions` with a `.md` inside (skipped),
  `.stfolder` (skipped), a top-level conflict copy (in `conflicts`, not `entries`),
  a conflict copy of a sub-entry (in `conflicts`, not in the entity tree), and a
  normal entity beside them (still loads).
- Pure helper unit tests for `isSyncerMetadata` / `isConflictCopy` (positive +
  negative).
- Re-run the 4 fixture cases (AC4) and `npm test` (AC5) — both must stay green.
- Widget test for the refresh + conflict-count surface using `FakeRepoStorage`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 2 · Story 2.1b] — user story, ACs (FR16, FR17, FR3)
- [Source: prd.md#FR16] (filter `.stfolder`/`.stignore`/`.stversions`, hardcoded for MVP), #FR17 (surface `*.sync-conflict-*.md` as badged, never parse/hide), #FR3 (rescan on resume + manual refresh, no live watcher)
- [Source: ARCHITECTURE-SPINE.md#AD-5] (syncer owns propagation; exact filter list + conflict rule), #AD-10 (rebuild on resume/refresh, no watcher), #AD-8, #AD-3, #AD-9, #AD-2
- [Source: addendum.md §E] — **syncer-aware walk is "new on the Dart side (no JS equivalent)"** → Dart-only, fixtures untouched
- [Source: apps/mobile/lib/lore/lore_loader.dart] — the 2.1a walk being extended
- [Source: apps/mobile/lib/app/browse_filter.dart] — UI hides dot-files/`media`; conflict copies deliberately NOT hidden (1.4 review)
- [Source: _bmad-output/project-context.md] — forward-slash IDs, walk conventions

## Dev Agent Record

### Agent Model Used

claude-sonnet-5 (Claude Sonnet 5)

### Debug Log References

- `flutter analyze` → No issues found.
- `flutter test` → **103 passing** (92 → +11: 5 syncer/conflict loader integration tests, 4 helper unit tests, 2 widget tests).
- **AC4 gate (fixtures) re-run after every loader change** → all 4 golden cases still deep-equal `expected.json`.
- **AC5 gate** → `npm test` 4/4, and `git status --porcelain lib/lore.js test/fixtures/ scripts/update-goldens.js` returns **empty** — the shared contract is provably untouched.
- No implementation dead-ends; the change was additive and the fixtures caught nothing (as intended, since none contain `.st*` or conflict copies).
- **After code review (12 patches):** `flutter analyze` clean, `flutter test` → **113 passing** (103 → +10), fixtures still 4/4, `npm test` still 4/4, contract still provably untouched. A brief environment blocker (the `D:` drive momentarily read as 100% full, failing one write) was cleared with `flutter clean`.

### Completion Notes List

- **The two jobs are deliberately opposite, and both are implemented as such:** syncer metadata is *filtered out* (never enters the model), while conflict copies are *routed to `LoreModel.conflicts`* — surfaced, never parsed as content, never silently dropped. Conflating them would either hide a file the author must resolve, or let junk pollute the model.
- **`.stversions` is the load-bearing skip.** It holds dated `.md` copies of real files (`frank~20240101-120000.md`); without the skip those parse as bogus duplicate entities. There's a dedicated test for exactly that.
- **Conflict copies are caught at both walk levels** — `_walkCategory` (a category-level or top-level `.md`) and `_buildNode` (a card or sub-entry inside an entity folder), the latter *before* `byBase` so a conflict copy can never become an item, an overview card, or a `children[]` entry. Tested at both levels.
- **`loadLore` now returns `LoreModel { entries, conflicts }`** — one walk, both outputs. `entries` is unchanged in shape (the fixtures pin it); `conflicts` is Dart-only and deliberately excluded from `normalize`, so it cannot affect conformance.
- **Dart-only guardrail honoured.** Syncer-awareness has no JS equivalent (addendum §E), so `lib/lore.js`, the fixtures, and `normalize.js` were not touched — verified by an explicit `git status` check, not just by intent. All syncer behavior is covered by Dart-only temp-dir tests.
- **Rescan (FR3/AD-10)** is a full `loadLore` walk on every `_refresh` — no cached model, no watcher. The resume path already re-scanned (Story 1.1's lifecycle observer); this adds the manual Refresh button. The widget test proves a *genuine* rescan by mutating the repo listing between scans and asserting the conflict banner appears.
- **Scope held:** no category/entity browsing was built — that is Story 2.2. The ready view gained only an entity count, a conflict banner, and Refresh.
- No new dependencies.

### File List

**Modified:**
- `apps/mobile/lib/lore/lore_loader.dart` (`isSyncerMetadata`/`isConflictCopy`/`kSyncerMetadataNames`; `loadLore` → `LoreModel`; skip syncer dirs and route conflict copies in `_walkCategory` and `_buildNode`; `_recordConflict`)
- `apps/mobile/lib/lore/lore_model.dart` (`LoreModel`, `ConflictCopy`)
- `apps/mobile/lib/app/home_page.dart` (run `loadLore` on the ready path each refresh; `_lore` state; entity count + conflict banner + Refresh button in `_ReadyView`)
- `apps/mobile/test/lore/lore_model_fixtures_test.dart` (call sites use `.entries`; new `syncer-aware walk` group — 5 tests)
- `apps/mobile/test/lore/lore_loader_test.dart` (helper unit tests for both detectors)
- `apps/mobile/test/widget_test.dart` (conflict surfacing + genuine-rescan tests; +resume-rescan and error-state tests from review)
- `apps/mobile/test/fakes.dart` (review: `throwOnListDir` flag for the scan-failure/error-state test)

**Deliberately NOT modified (verified):** `lib/lore.js`, `test/fixtures/lore-model/**`, `scripts/update-goldens.js`, `apps/mobile/lib/lore/lore.dart` (the barrel already exports the loader and model, so the new types/helpers are exported automatically), `apps/mobile/test/lore/normalize.dart`.

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-20 | Addressed code review (Sonnet 5 impl, 3 parallel layers): 12 patch findings fixed. **Filter alignment:** the loader now skips *every* dot-prefixed dir + `media/` (was a 3-name allowlist that would descend into `.git`/`.github`/`.obsidian` — reachable when the repo root is the lore folder), matching the browse UI and covering `.lore-tmp-*`. **Tighter conflict detection:** `isConflictCopy` anchored to the real `.sync-conflict-<8>-<6>-<id>.md` shape (an authored `troubleshooting.sync-conflict-recovery.md` is no longer swallowed), and both detectors are now case-insensitive. **Model contract:** `ConflictCopy.relDir` uses `.` at the lore root (matching `LoreEntry`), conflicts are sorted by id (deterministic), and `LoreModel` hands out `List.unmodifiable` views. **Rescan/errors:** `_refresh` is now single-flight coalescing (no concurrent walks on rapid Refresh/resume) with a catch-all error stage + Retry (was: a throw stranded the UI on a spinner forever); returning from the editor rescans (FR3 on the common in-app path). **Text/tests:** entity count pluralized (`1 lore entity`); stale doc comment corrected; +10 tests covering `.git`/`.github`, uppercase variants, the substring false-positive, root-level `relDir`, deterministic ordering, the **resume** half of AC3, and the error state. Tests 103 → 113; fixtures 4/4; `npm test` 4/4; contract untouched (git-verified); analyze clean. 9 findings deferred. |
| 2026-07-20 | Implemented Story 2.1b: syncer-aware walk + rescan. `loadLore` now returns `LoreModel { entries, conflicts }` from a single walk. Syncer metadata (`.stfolder`/`.stversions`/`.stignore`) is filtered from the walk — `.stversions` especially, since its dated `.md` copies would otherwise load as bogus entities. `*.sync-conflict-*.md` files are detected at both walk levels and surfaced in `conflicts`, never parsed as entities/sub-entries and never hidden (FR17; the badge UI remains Story 2.4). The ready view runs a full walk on every refresh (AD-10 — no cache, no watcher), shows the entity count and a conflict banner, and gained a manual Refresh button (FR3). All Dart-only per addendum §E: `lib/lore.js` and the shared fixtures were not touched, verified by `git status`. Tests 92 → 103; fixtures still 4/4; `npm test` still 4/4; analyze clean. |
