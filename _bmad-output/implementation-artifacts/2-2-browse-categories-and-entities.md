---
baseline_commit: 83cf10f
---

# Story 2.2: Browse categories and entities

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to browse my categories and the entities inside them,
so that I can navigate to any card.

## Acceptance Criteria

1. **AC1 (FR4 — Categories screen):** Given the scanned lore model, when I reach the ready surface, then I see a **Categories** list built from the model's top-level `loreDir` folders (one row per top-level category, e.g. `characters`, `locations`), each showing how many entities it holds — **not** the raw `listDir` of the repo root that the Story 2.1b ready view showed.
2. **AC2 (FR5 — Entities list, one node type):** Given a category, when I open it, then I see its entities, with a **simple file** (`frank.md`) and an **entity folder** (`selena/`) presented as the **same kind of item** — same row shape, same tap affordance, no visual "file vs folder" distinction.
3. **AC3 (navigate to any card):** Given an entity in the list, when I tap it, then its **card** (`LoreEntry.id`, the `.md` the model resolved) opens in the existing `EditorPage`, and returning from the editor rescans (the Story 2.1b `_refresh` path is preserved). *(This closes "navigate to any card." Story 2.3 later inserts the entity-detail tree between the entities list and the editor.)*
4. **AC4 (reachability — nothing stranded):** Given the full model, when I browse Categories → Entities, then **every** `LoreEntry` in `lore.entries` is reachable: entities in nested sub-categories (`characters/secondary/frank.md`) appear under their **top-level** category (`characters`), and cards sitting directly in `loreDir` (model `category == 'general'`) appear under a visible top-level group — no entity is silently absent. Conflict copies (`lore.conflicts`) are **not** shown here (that is Story 2.4) and must never leak into the entities list.
5. **AC5 (grouping is pure + total; UI never crashes):** The category-grouping logic is a **pure function in the `lore/` slice** (no Flutter, no `dart:io` — AD-9), unit-tested directly; the browse UI only renders the model and **never throws** on any model, including an empty model (friendly empty state) — AD-8/NFR7.
6. **AC6 (no contract drift; hygiene):** Given the shared golden fixtures, when the suite runs, then all 4 cases still deep-equal `expected.json` — this story changes **no** loader/model shape (it is read-only over the existing model). `flutter analyze` clean; `flutter test` green (with new browse widget tests + grouping unit tests); `npm test` still 4/4; `lib/lore.js`, `test/fixtures/**`, and `normalize.js` untouched.

## Tasks / Subtasks

- [x] **Task 1 — Pure category-grouping helper in `lore/` (AC: 1, 4, 5)**
  - [x] Add a pure function that groups `List<LoreEntry>` into ordered top-level categories. Recommended shape: a small value type `LoreCategory { String key; String label; List<LoreEntry> entries; }` and `List<LoreCategory> categoriesOf(List<LoreEntry> entries)`. Put it in a new pure file under `apps/mobile/lib/lore/` (e.g. `lore_browse.dart`) and export it from the `lore/` barrel (`lore.dart`).
  - [x] **Top-level key** = `entry.category.split('/').first` (so `characters/secondary` → `characters`). This flattens nested sub-categories into their top-level parent — **required for AC4** (every entity stays reachable; deep sub-category navigation is out of scope for 2.2). The synthetic `general` category (a card directly in `loreDir`) becomes its own top-level group — do **not** drop it.
  - [x] **Ordering (deterministic, display-facing):** sort categories by `key` case-insensitively; within a category sort entries by `title` case-insensitively, tie-broken by `id` (so two same-titled cards have a stable order). Do **not** rely on walk order for display — the walk order is an internal detail, not a UI contract.
  - [x] Keep it pure: takes a `List<LoreEntry>`, returns the grouping. No I/O, no Flutter import. This is the AD-9 boundary — grouping is model logic, not widget logic.
- [x] **Task 2 — Categories surface (AC: 1)**
  - [x] In `app/home_page.dart`'s **ready** view, replace the raw "Top-level entries (`_topLevel` from `listDir('')`)" list with a **Categories** list built from `categoriesOf(_lore.entries)`. Each row: the category label + its entity count (e.g. "characters · 12"), tappable, with a chevron.
  - [x] Keep the surrounding ready-view chrome intact: the repo-root / lore-folder header, the **conflict banner** (`lore.conflicts` — FR17, Story 2.1b), the **Refresh** button (manual half of FR3), and **Change folder**. Keep the lore entity-count line or fold it into the Categories header — your call, but the conflict banner and both buttons must remain.
  - [x] **Empty model:** when `_lore.entries` is empty, show a friendly empty state ("No lore entities found in `<loreDir>`.") instead of a blank list — do not regress into a hollow surface.
  - [x] `_topLevel` (the raw root `listDir`) is no longer the primary browse source. You may keep it **only** if "Open a file" still needs it; otherwise remove the now-dead `_topLevel` state and its `_openEntry(RepoEntry)` path. See Task 4 for the "Open a file" decision.
- [x] **Task 3 — Entities screen + tap-to-card (AC: 2, 3, 4)**
  - [x] Add a new page under `app/` (e.g. `CategoryEntitiesPage`) that takes the chosen `LoreCategory` (or its entries) + the `RepoStorage` and lists its entities. Push it via `Navigator` when a category row is tapped (same navigation idiom as `LoreFilePickerPage` / `RootPickerPage`).
  - [x] **One node type (FR5):** render a simple entity and an entity folder with the **same** row (title as the primary line). Do **not** branch the row's look on `entry.tree != null`. Optional chevron is fine but must be identical for both — 2.2 opens the card for both; the folder-vs-tree distinction is Story 2.3's concern, not this story's.
  - [x] **Disambiguate duplicate titles:** two entities can share a `# heading` title. Show a secondary line (the entity's `id` or `relDir`/slug) so same-titled entities are distinguishable and individually reachable — otherwise the user can't tell which "Frank" they're tapping.
  - [x] **Tap → editor:** on tap, push the existing `EditorPage(storage: storage, path: entry.id)`. On return, trigger the home rescan (AC3). The cleanest wiring: have the entities page pop back, and let the home `_refresh` fire on return (it already rescans on resume; if the push is from a pushed page, add an `await ... then _refresh()` in the tap handler that owns the `EditorPage` push, mirroring the existing `_openEntry` file branch).
  - [x] **Reachability check (AC4):** confirm every entity — including a `general` root card and a `characters/secondary/*` nested one — is present under some category and opens its card.
- [x] **Task 4 — Preserve Epic 1 capabilities; decide "Open a file" (AC: 3, 6)**
  - [x] Preserve the home `_refresh` machinery **exactly**: the epoch guard, single-flight coalescing (`_refreshing`/`_refreshQueued`), the `error` stage + Retry, the vanished-root re-pick, config re-resolution, and rescan-on-resume. Story 2.1b's review hardened all of this — do not regress it.
  - [x] "Open a file" (the raw `LoreFilePickerPage`) reaches files **outside** `loreDir` (e.g. `story/` scenes, config) that the lore model doesn't include. **Recommended:** keep it as a secondary action so that capability isn't lost, but demote it below the Categories browse. If you remove it, remove `_topLevel`/`_openEntry`/`_openFile`/`_openFileFrom` cleanly and note the dropped capability. Either is acceptable; do not leave half-wired dead code.
- [x] **Task 5 — Tests (AC: 1–6)**
  - [x] **Grouping unit tests** (`test/lore/`, pure — no widget pump): `categoriesOf` groups a flat entry list into top-level categories; nested `characters/secondary` folds under `characters`; a `general` root card gets its own group; ordering is deterministic and case-insensitive; two same-titled entries both survive with a stable order; empty input → empty list.
  - [x] **Browse widget tests** (`test/app/`, `FakeRepoStorage` with `dirEntries` seeding a small lore tree — same pattern as `widget_test.dart` and `lore_file_picker_page_test.dart`): the ready surface lists categories with counts; tapping a category shows its entities; a simple file and an entity folder both appear as items and open the editor at `entry.id`; a conflict copy present in the model shows in the banner but **not** in any entities list; the empty-model empty state renders.
  - [x] **Contract gate:** re-run the 4 fixture cases (AC6) and `npm test` — both stay green; `git status --porcelain lib/lore.js test/fixtures/ scripts/` is empty. This story touches none of them, but verify, don't assume.
  - [x] `flutter analyze` clean; `flutter test` green.

### Review Findings

Cross-model review (Opus 4.8 implementation, 3 Sonnet layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor). Auditor independently re-ran the gates: `flutter analyze` clean, `flutter test` 121/121 (fixtures 4/4), `npm test` 4/4, contract git-clean — AC1/AC2/AC5/AC6 confirmed satisfied. Findings below are the gaps the ACs/tests did not cover.

**Patch:**

- [x] [Review][Patch] **Entities list shows a stale snapshot after an in-place edit** — `CategoryEntitiesPage` is a `StatelessWidget` holding the `LoreCategory` snapshot from tap-time; the rescan only fires when the page is popped back to Home (`_openCategory`), not on return from the editor pushed *inside* it. Edit a title, pop back to the still-open entities list, and the row shows the old title until you exit to Home. Contradicts AC3's "returning from the editor rescans" and the Dev Notes' explicit "extend it to the entity-tap path." [apps/mobile/lib/app/category_entities_page.dart:_openEntity; apps/mobile/lib/app/home_page.dart:_openCategory] (blind+auditor)
- [x] [Review][Patch] **Category-key sort has no tie-break, contradicting the file's own determinism promise** — `keys.sort((a,b) => a.toLowerCase().compareTo(b.toLowerCase()))` returns 0 for two distinct keys differing only by case; Dart's `List.sort` is not stable, so their order is undefined, while the sibling `byTitleThenId` explicitly tie-breaks entries. Add a raw-string tie-break. [apps/mobile/lib/lore/lore_browse.dart:61-62] (blind)
- [x] [Review][Patch] **Dead `isEmpty` branch in the category key; blank first segment unguarded** — `e.category.isEmpty ? 'general' : e.category.split('/').first`: the loader never emits an empty category, so the branch is dead and deviates from the stated formula; meanwhile a blank *first segment* (a hypothetical leading-slash category) would yield a blank, unlabeled category. Split first, then fall back to `general` on an empty segment — one guard that is both live and defensive. [apps/mobile/lib/lore/lore_browse.dart:52] (auditor+edge)
- [x] [Review][Patch] **AC4 "opens its card" unverified for the `general` and nested-subcategory cases** — Task 3 asked to confirm those entities not only appear but open their card; the tests only assert presence (`find.text('general')`, `find.text('Deep One')`), never tapping through to the editor. Only the flat `characters/frank.md` case asserts the editor opens. Add the tap-through assertions. [apps/mobile/test/app/browse_test.dart] (auditor)

**Deferred:**

- [x] [Review][Defer] **A real top-level folder literally named `general` merges with the synthetic root-card bucket** — both a loose card at `loreDir` root and a real `general/` folder resolve to `category == 'general'` (loader semantic from Story 2.1a), so `categoriesOf` merges them into one indistinguishable row. No stranding, no crash; an unusual config. Inherited from the loader's `category` scheme, not introduced by this diff. Revisit if the root-card bucket needs a reserved/rendered-distinct name. [apps/mobile/lib/lore/lore_browse.dart:52 + apps/mobile/lib/lore/lore_loader.dart:238,243,250] (blind+edge)
- [x] [Review][Defer] **Rapid double-tap stacks duplicate routes** — a fast double-tap on a category row pushes two `CategoryEntitiesPage` routes; on an entity row, two `EditorPage` instances open on the same file. No navigation single-flight guard, unlike the app's `_refresh` coalescing. Pre-existing app-wide pattern (Story 2.1b's `_openEntry` had the same); low impact. [apps/mobile/lib/app/home_page.dart:_openCategory; apps/mobile/lib/app/category_entities_page.dart:_openEntity] (edge)

## Dev Notes

### What this story is (and is not)

The model is **already built** — Story 2.1a/2.1b give you `LoreModel { entries, conflicts }` from `loadLore`. This story is **pure browse UI over that model**, plus one **pure grouping helper**. You are *not* parsing anything, *not* touching the loader, *not* changing the model shape. If you find yourself editing `lore_loader.dart` or `lore_model.dart`'s field shapes, stop — that is out of scope and will break the fixture contract (AC6).

Two-level browse: **Categories** (top-level `loreDir` folders) → **Entities** (the cards in that category) → tap opens the **card** in the editor. That's the whole thread. The entity-detail tree (card + sections + quests) is **Story 2.3** and explicitly not here.

### The model already gives you everything — read these fields

From `apps/mobile/lib/lore/lore_model.dart`:

- **`LoreModel.entries : List<LoreEntry>`** — the flat list of every entity (simple cards *and* entity-folder cards). This is your browse source. It is a `List.unmodifiable` view (Story 2.1b review) — read-only, as intended.
- **`LoreModel.conflicts : List<ConflictCopy>`** — conflict copies, already surfaced in the ready view's banner. **Do not** put these in the entities list; Story 2.4 owns their badged display.
- **`LoreEntry.id`** — loreDir-relative path of the card `.md` (e.g. `characters/selena/selena.md`). **This is the path you hand to `EditorPage`.**
- **`LoreEntry.title`** — the card's first `# heading`, falling back to the slug. The row's primary line.
- **`LoreEntry.category`** — the folder path under `loreDir`: `characters`, `characters/secondary`, or the synthetic **`general`** for a card sitting directly in `loreDir`. **This is what you group by.** Top-level key = `category.split('/').first`.
- **`LoreEntry.relDir`** — loreDir-relative directory holding the card; `.` at the lore root. Useful as the disambiguating secondary line.
- **`LoreEntry.tree`** — non-null for an entity folder, null for a simple entity. **In 2.2 you deliberately ignore this for the row's appearance** (FR5: one node type). It exists for Story 2.3.

There is no "list categories" API to write against the loader — categories are *derived* from `entries[].category`. That derivation is Task 1's pure helper.

### Critical decisions already made for you (do not re-litigate)

- **Group by top-level segment; flatten nested sub-categories.** FR4 says "top-level folders." An entity in `characters/secondary/` appears under **`characters`**, not under a separate `secondary`. Rationale: AC4 reachability with the minimal surface — deep sub-category navigation would be scope creep for a 2-AC story. (If repos ever go deep, hierarchical category nav is a clean later addition; for now nothing may be stranded.)
- **`general` is a real, visible group.** Cards directly in `loreDir` carry `category == 'general'` (the loader's `category.isEmpty ? 'general'` fallback). They must show as a top-level group — dropping them would strand cards (AC4).
- **Simple entity and entity folder look identical.** FR5 is explicit. Do not add a folder icon / file icon split. Both tap to their card.
- **Tap opens the card, not a tree.** Story 2.3 inserts the detail tree. In 2.2, both node types open `entry.id` in `EditorPage`. This keeps 2.2 self-contained and demonstrable.
- **Grouping is pure and lives in `lore/`.** Not a private method on a widget. AD-9: model logic is pure and unit-testable; the widget only renders. This is also the single biggest thing that keeps the cross-model reviewer from finding "business logic buried in a widget."

### Files being MODIFIED / ADDED (read before editing)

- **`apps/mobile/lib/app/home_page.dart`** (MODIFY) — the ready view currently shows a header, the conflict banner, a raw `listDir('')` "Top-level entries" list, "Open a file", "Refresh", "Change folder". **Change:** replace the raw top-level list with a model-driven **Categories** list (`categoriesOf(_lore.entries)`); tapping a category pushes the entities page. **Preserve exactly:** `_refresh`'s epoch guard + single-flight coalescing + `error` stage + Retry, the vanished-root re-pick, config re-resolution, resume rescan, the conflict banner, Refresh, Change folder. These were all hardened by the 2.1b review — regressing them re-opens fixed findings.
- **`apps/mobile/lib/lore/lore_browse.dart`** (NEW, pure) — `LoreCategory` + `categoriesOf`. No Flutter, no `dart:io`.
- **`apps/mobile/lib/lore/lore.dart`** (MODIFY) — export the new browse helper from the barrel.
- **`apps/mobile/lib/app/category_entities_page.dart`** (NEW) — the entities list for one category; taps push `EditorPage`.
- **`apps/mobile/test/lore/…`** (NEW) — `categoriesOf` unit tests.
- **`apps/mobile/test/app/…`** (NEW/MODIFY) — browse widget tests; `test/widget_test.dart` currently asserts the old raw "Top-level entries" surface — **update those assertions** to the new Categories surface rather than leaving them asserting a removed widget.

> **Slice-layout note (known variance):** the ARCHITECTURE-SPINE says the `lore/` slice "owns … browse/editor/preview UI," but the established code puts all pages under `app/` (`home_page`, `editor_page`, `lore_file_picker_page`, `root_picker_page`) with only pure model/matcher logic in `lore/`. **Follow the existing `app/` convention for the new pages** — consistency with the shipped codebase wins, and the AD-9 purity boundary (pure logic in `lore/`, I/O/UI outside) is still honored. Put the pure `categoriesOf` in `lore/`; put the widgets in `app/`.

### Architecture guardrails

- **AD-8 / NFR7 — total, never throws.** The model is already total; your UI just renders it. Handle the empty model as a state, not an error. No parsing in the UI means nothing new to throw — keep it that way.
- **AD-9 — purity per slice.** `categoriesOf` and `LoreCategory` are pure Dart in `lore/`. Widgets in `app/` depend inward on them. No `dart:io`/Flutter in the helper.
- **AD-10 — model rebuilt, never patched.** You render `_lore` (rebuilt each `_refresh`); the browse UI never mutates the model. Returning from the editor triggers a rescan (already wired for the file path — extend it to the entity-tap path).
- **AD-3 — storage only via `RepoStorage`.** The pages already receive a `RepoStorage` (via `storageFactory(root)`); pass it through to `EditorPage`. No new storage access is needed for browsing — you browse the in-memory model, not the disk.
- **AD-2 / AD-6 — contract untouched.** No loader/model change. RU/EN pairing is already merged in the model; you don't handle it here (that's the editor's Story 2.8). Fixtures stay 4/4 (AC6).
- **NFR6 — instant.** Grouping a few-hundred-entry list is O(n); do it once per build from the already-loaded model. Don't re-walk the disk to build categories.

### Previous story intelligence

- **2.1b (done):** `loadLore` → `LoreModel { entries, conflicts }`; `home_page._refresh` is epoch-guarded, single-flight-coalesced, has an `error` stage + Retry, rescans on resume and on return-from-editor, and shows the conflict banner + Refresh. The ready view was left deliberately thin ("no category/entity browsing — that is Story 2.2"). **You are filling exactly that gap.** The 2.1b review's recurring theme: *nothing stranded, deterministic ordering, never strand the UI on a spinner* — carry it into the browse surface (AC4 reachability, deterministic display order).
- **1.4 (done):** `EditorPage(storage, path)` opens a file at a repo-relative path; `LoreFilePickerPage` is the raw drill-down picker (kept for non-lore files). `browse_filter.isHiddenBrowseEntry` hides dot-files + `media` for the **raw** picker — you don't need it here because you browse the **model**, which already excluded those during the walk.
- **AD-8 at the call site** (repo memory): the 1.3/1.4/2.1b reviews all caught "never-throw asserted in the domain but not enforced at the UI call site." Your call sites are pure renders of an in-memory model, so the risk is low — but keep the empty/absent cases as explicit states, not implicit blanks.

### Git intelligence

`83cf10f` (2.1b — syncer-aware walk + rescan + conflict banner) is the baseline. This story sits directly on it, consuming the `LoreModel` it produces. No commits since touch the browse surface.

### Library / version policy

**No new dependencies.** Pure Dart grouping + existing Flutter Material widgets (`ListView`, `ListTile`, `Navigator`, `MaterialPageRoute`) — the same toolkit the current pages use. Do not add a state-management or routing package for a two-screen browse.

### Toolchain / how to run

Flutter is at `C:\programs\flutter\bin` (Flutter 3.44.7 / Dart 3.12.2 per 2.1b), not necessarily on `PATH`. From `apps/mobile/`:

```bash
$env:PATH = "C:\programs\flutter\bin;$env:PATH"; flutter analyze
```
```bash
$env:PATH = "C:\programs\flutter\bin;$env:PATH"; flutter test
```

And from the repo root, the JS reference conformance cross-check (must stay 4/4):

```bash
npm test
```

### Testing standards

- **Pure grouping → plain unit tests** in `test/lore/` (no `WidgetTester`): construct `LoreEntry`s in-line, assert `categoriesOf` output (grouping, nesting fold, `general` bucket, ordering, duplicate-title stability, empty input).
- **Browse UI → widget tests** in `test/app/` using `FakeRepoStorage` seeded via `dirEntries` (mirror `test/widget_test.dart` and `test/app/lore_file_picker_page_test.dart`): pump the app to the ready surface, assert the Categories list + counts, tap a category, assert the entities list (a simple file and a folder both present as items), tap an entity, assert `EditorPage` opened at `entry.id`. Seed a conflict copy and assert it appears in the banner but not the entities list. Assert the empty-model empty state.
- **Contract gate:** fixtures 4/4 (`flutter test` runs `lore_model_fixtures_test.dart`), `npm test` 4/4, and a `git status --porcelain` check that `lib/lore.js`/`test/fixtures/**`/`scripts/**` are untouched. Non-negotiable (AC6).
- Do **not** write a shared golden fixture for browsing — browsing is UI, not a model-contract concern.

### Project Structure Notes

- New pure logic: `apps/mobile/lib/lore/lore_browse.dart` (exported from `lore.dart`).
- New UI: `apps/mobile/lib/app/category_entities_page.dart`; modified `apps/mobile/lib/app/home_page.dart`.
- Tests: `apps/mobile/test/lore/lore_browse_test.dart` (unit); `apps/mobile/test/app/` widget test(s); update `apps/mobile/test/widget_test.dart` assertions that reference the removed raw top-level list.
- **Variance (documented above):** UI in `app/` rather than the spine's `lore/`-owns-UI wording; purity boundary preserved (pure grouping in `lore/`). No other deviations.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.2] — user story + ACs (FR4, FR5)
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR4] (Categories screen — top-level `loreDir` folders), #FR5 (simple file and entity folder as one node type)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-8] (total/never-throw), #AD-9 (per-slice purity), #AD-10 (model rebuilt, never patched), #AD-2 (fixtures are the contract), #AD-12 (feature-sliced packaging)
- [Source: apps/mobile/lib/lore/lore_model.dart] — `LoreModel`, `LoreEntry` fields (id/title/category/relDir/tree) you render
- [Source: apps/mobile/lib/lore/lore_loader.dart] — how `category` is derived (`general` fallback; nested `a/b` path) — read-only context, do not modify
- [Source: apps/mobile/lib/app/home_page.dart] — the ready view being restructured; `_refresh` machinery to preserve
- [Source: apps/mobile/lib/app/lore_file_picker_page.dart] — the raw picker (kept for non-lore files); navigation idiom to mirror
- [Source: apps/mobile/lib/app/editor_page.dart] — `EditorPage(storage, path)`, the tap target
- [Source: apps/mobile/test/fakes.dart] — `FakeRepoStorage` (`dirEntries`/`fileContents`) for widget tests
- [Source: _bmad-output/implementation-artifacts/2-1b-syncer-aware-walk-and-rescan.md] — prior story: model shape, rescan/error hardening, conflict banner
- [Source: _bmad-output/project-context.md] — terminology (entity/entry, category=folder path), forward-slash IDs, thin-shells rule

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- `flutter analyze` → **No issues found.**
- `flutter test` → **121 passing** (113 → +8 net): 7 grouping unit tests + 6 new browse widget tests, minus 5 retired raw-surface widget tests.
- **Fixture conformance gate** (`lore_model_fixtures_test.dart`, part of `flutter test`) → all 4 golden cases still deep-equal `expected.json`. This story changed no loader/model shape.
- **AC6 gate** → `npm test` 4/4, and `git status --porcelain lib/lore.js test/fixtures/ scripts/` returns **empty** — the shared JS reference + fixtures are provably untouched.
- **One real bug caught by tests during dev:** the first "tap entity → editor" run failed because `LoreEntry.id` is **loreDir-relative** (`characters/frank.md`) while `EditorPage`/`RepoStorage` are **repo-relative** (`lore/characters/frank.md`). Fixed by joining `loreDir` back on at the model→storage boundary (`CategoryEntitiesPage._repoPath`). This is exactly the id-space seam Story 2.3 will also cross.

### Completion Notes List

- **Browsing is now driven by the parsed lore *model*, not a raw directory listing.** The home ready view's old `listDir('')` "Top-level entries" list is replaced by a **Categories** list built from `categoriesOf(_lore.entries)`; the raw `listDir('')` scan (and its `browse_filter` dependency) is gone from `home_page`. Syncer/`media`/dot-dirs can no longer even appear as categories because the walk already excluded them.
- **Grouping is a pure `lore/` function (`categoriesOf`), unit-tested in isolation** (AD-9). Top-level key = `category.split('/').first`, so nested sub-categories fold under their top-level parent and the synthetic `general` bucket (root cards) is its own group — **every entity stays reachable** (AC4). Display order is deterministic and case-insensitive (categories by key; entities by title, id tie-break).
- **FR5 taken literally:** in `CategoryEntitiesPage` a simple entity and an entity folder render as the **same** row (same icon, same tap); `LoreEntry.tree` is deliberately ignored for appearance — that distinction is Story 2.3's. Both open the entity's **card** (`entry.id`), closing "navigate to any card." A secondary line (`entry.id`) disambiguates same-titled cards.
- **model-id ↔ storage-path seam:** `entry.id` is loreDir-relative; `CategoryEntitiesPage._repoPath(loreDir, id)` joins `loreDir` back on before handing the path to `EditorPage`. Empty `loreDir` (repo root *is* the lore folder) passes the id through unchanged.
- **All of Story 2.1b's `_refresh` hardening preserved:** epoch guard, single-flight coalescing, `error` stage + Retry, vanished-root re-pick, config re-resolution, resume rescan, and the conflict banner + Refresh + Change folder. Returning from the entities page (and thus from any editor opened through it) rescans (FR3/AD-10). The entity-count line is kept.
- **Empty model is a friendly state, not a hollow list** (AD-8/NFR7): "No lore entities found in \"<loreDir>\"." with the Open-a-file / Refresh / Change-folder actions still available.
- **"Open a file" (raw picker) kept** as a secondary action — it still reaches files outside `loreDir` (e.g. `story/` scenes, config) that the lore model doesn't include; no Epic 1 capability was dropped.
- **No new dependencies.** Pure Dart + existing Flutter Material widgets.
- **Test surface updated honestly:** 5 widget tests that asserted the removed raw top-level list were retired (their still-relevant coverage — the picker drill-down — remains in `lore_file_picker_page_test.dart` and the two "Open a file" tests); the error-state test now takes its scan failure from the lore walk's `listDir` (seeded `dirEntries['lore']`) since the raw root `listDir('')` no longer runs.

### File List

**Added:**
- `apps/mobile/lib/lore/lore_browse.dart` (`LoreCategory`, pure `categoriesOf`)
- `apps/mobile/lib/app/category_entities_page.dart` (entities list for one category; model-id→repo-path join; tap → `EditorPage`)
- `apps/mobile/test/lore/lore_browse_test.dart` (7 grouping unit tests)
- `apps/mobile/test/app/browse_test.dart` (6 browse widget tests)

**Modified:**
- `apps/mobile/lib/lore/lore.dart` (export `lore_browse.dart` from the barrel)
- `apps/mobile/lib/app/home_page.dart` (drop raw `listDir('')`/`_topLevel`/`_openEntry`/`browse_filter` import; render `categoriesOf(_lore.entries)` in the ready view; `_openCategory` pushes `CategoryEntitiesPage` then rescans; empty-model state)
- `apps/mobile/test/widget_test.dart` (retire 5 raw-surface tests; point the error-state test's failure at the lore walk)

**Deliberately NOT modified (verified git-clean):** `lib/lore.js`, `test/fixtures/lore-model/**`, `scripts/**`, `apps/mobile/lib/lore/lore_loader.dart`, `apps/mobile/lib/lore/lore_model.dart` (no model/contract change — AC6).

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-24 | Addressed code review (Opus 4.8 impl, 3 Sonnet layers): 4 patch findings fixed. **Live entities list:** `CategoryEntitiesPage` is now stateful and re-walks the lore model on return from the editor, so an in-place title edit is reflected without backing out to Home (was: a stale tap-time snapshot until you exited the category — contradicting AC3). **Deterministic key sort:** category keys now tie-break by the raw string, so two case-only-distinct folders have a stable order (matching the file's stated guarantee). **Live+defensive key derivation:** the dead `isEmpty` branch is replaced by a split-first-then-fallback so a blank first segment (empty/leading-slash) resolves to `general`. **Test coverage:** the `general` and nested-subcategory reachability cases now tap through to confirm the card opens; added a live-update regression test and unit tests for the tie-break + blank-segment fallback. Tests 121 → 125; `flutter analyze` clean; fixtures 4/4; `npm test` 4/4; contract git-verified untouched. 2 findings deferred (a real `general/` folder colliding with the synthetic root-card bucket — inherited 2.1a loader semantic; rapid double-tap route stacking — pre-existing pattern). |
| 2026-07-24 | Implemented Story 2.2: browse categories and entities. The home ready view now renders a **Categories** list built from `categoriesOf(_lore.entries)` (a new pure `lore/` helper) instead of the raw root `listDir('')`; tapping a category opens a `CategoryEntitiesPage` listing its entities, and tapping an entity opens its card in the editor (FR4/FR5, "navigate to any card"). Grouping folds nested sub-categories under their top-level parent and keeps the `general` root-card bucket so every entity is reachable (AC4). Caught and fixed a model-id (loreDir-relative) ↔ storage-path (repo-relative) mismatch at the editor boundary. All of 2.1b's rescan/error hardening and the conflict banner preserved. Tests 113 → 121 (+7 grouping unit, +6 browse widget, −5 retired raw-surface); `flutter analyze` clean; fixtures 4/4; `npm test` 4/4; shared contract git-verified untouched. No new dependencies. |
