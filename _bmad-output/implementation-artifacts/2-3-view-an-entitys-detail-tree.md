---
baseline_commit: 5ee1c50
---

# Story 2.3: View an entity's detail tree

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to see an entity's card and its sections,
so that I can find the specific sub-entry or scene to edit.

## Acceptance Criteria

1. **AC1 (FR6 — detail tree for an entity folder):** Given an **entity folder** (`LoreEntry.tree != null`), when I open it from the entities list, then a detail screen shows the entity **card on top**, followed by its **folder-named sections** (e.g. Events, Quests) with their items, and **nested sections rendered nested** — section titles taken verbatim from the model (already prettified: `relationship-quest-1` → `relationship quest 1`, or the section's own card heading when it has one).
2. **AC2 (FR6 — media excluded, card not its own child):** Given an entity folder, when the detail renders, then `media/` does **not** appear as content and the entity's own card is **not** listed among its sub-entries. *(The model already guarantees both — Story 2.1a; the UI must render the tree faithfully, not re-derive or re-filter it.)*
3. **AC3 (navigate to any card/sub-entry/scene → editor):** Given the detail tree, when I tap the card, a sub-entry, a scene, or a section's overview card, then that file opens in the existing `EditorPage`; on return, the detail re-walks so a title edit is reflected without backing out (mirrors the Story 2.2 `CategoryEntitiesPage` rescan-on-return).
4. **AC4 (simple entity stays fast):** Given a **simple entity** (`LoreEntry.tree == null` — a flat `.md` card with no folder), when I tap it in the entities list, then it opens its card **directly in the editor** (no detail screen) — a simple card has no tree to navigate, so the Story 2.2 direct-to-editor behavior is preserved for it.
5. **AC5 (total/never-throws; hygiene):** The detail UI **never throws** on any entity/tree, including an entity folder whose tree has no sub-entries (card-only) — it degrades to just the card row (AD-8/NFR7). Grouping/tree logic stays in the pure `lore/` model (no tree-shape logic re-implemented in the widget — AD-9). `flutter analyze` clean; `flutter test` green (new detail widget tests); the shared golden fixtures still pass 4/4 and `npm test` 4/4 (this story renders the existing model; it changes **no** loader/model shape).

## Tasks / Subtasks

- [x] **Task 1 — `EntityDetailPage` widget (AC: 1, 2, 3, 5)**
  - [x] Add `apps/mobile/lib/app/entity_detail_page.dart` — a `StatefulWidget` taking `RepoStorage storage`, `LoreEntry entry`, and `String loreDir` (same trio + join rule as `CategoryEntitiesPage`).
  - [x] Render a scrollable outline:
    - **Card row at top:** the entity card — `entry.title` — tappable → opens `EditorPage` at `_repoPath(entry.id)`. Give it a clear affordance (e.g. a distinct leading icon / a "Card" label) so it reads as the entity's own card, not a sub-entry.
    - **Root-level items** (`entry.tree.items`): each `LoreItem` as a tappable row (`item.title`) → opens the item's **primary** language file (`(item.langs['orig'] ?? item.langs['ru'] ?? item.langs['en'])!.file`, joined via `_repoPath`). *(RU/EN tabs are Story 2.8; here, tapping opens the primary variant in the bare editor.)*
    - **Sections** (`entry.tree.children`, each a `LoreNode`): a **section header** showing `node.title`; then, if `node.overview != null`, a tappable "overview" row → `EditorPage(_repoPath(node.overview!.id))`; then `node.items` rows; then **recurse** into `node.children` as **nested** sections (indent by depth).
  - [x] **Do NOT** re-implement prettify, exclude `media/`, or drop the entity card from children — the model already did all three (see Dev Notes). Render `node.title`, `node.items`, `node.children` exactly as given. Adding UI-side filtering here would duplicate — and risk diverging from — the loader/fixture contract.
  - [x] The entity-root node (`entry.tree`) has an **empty title** (`''`) — do not render it as a section header; render its `items` directly under the card, and its `children` as the top-level sections.
  - [x] **Never throw:** a card-only entity folder (empty `items`/`children`) shows just the card row; a null `overview` renders nothing for that slot. No assumptions that any list is non-empty.
- [x] **Task 2 — Rescan-on-return in the detail page (AC: 3, 5)**
  - [x] Seed the shown tree from the `entry` snapshot; on return from any `EditorPage` push, `_rescan()`: `loadLore(storage, loreDir)`, find the entity by `entry.id` in `model.entries`, and `setState` the new `LoreEntry` (AD-10 — model rebuilt, never patched). Mirror `CategoryEntitiesPage._rescan` exactly, including the **try/catch that keeps the current view on an unexpected walk failure** (AD-8 at the call site).
  - [x] If the entity is **gone** after a rescan (deleted/renamed — `firstWhere` finds nothing), degrade gracefully: show a small "This entity is no longer present." state (do not crash, do not show a stale tree indefinitely). Popping back to the entities list (which also rescans) is acceptable, but must not throw.
- [x] **Task 3 — Route entity taps through the detail page (AC: 3, 4)**
  - [x] In `apps/mobile/lib/app/category_entities_page.dart`, change `_openEntity`: if `entry.tree != null` → push `EntityDetailPage(storage, entry, loreDir)`; else (simple entity) → push `EditorPage(_repoPath(entry.id))` as today. On return from **either**, run the existing `_rescan()` (already wired) so the entities list reflects any title change.
  - [x] Update the class doc comment (it currently says "Story 2.3 will route an entity tap to a detail tree instead" — now it does) — keep the FR5 "one node type" rendering in the *list* unchanged; the branch is only in the tap handler, not the row's appearance.
- [x] **Task 4 — Tests (AC: 1–5)**
  - [x] **Detail widget tests** (`test/app/`, `FakeRepoStorage` with `dirEntries`/`fileContents` seeding an entity folder): card at top; section headers present (e.g. "events" / prettified quest names) with their items; a nested quest section renders nested; `media/` content does not appear; the entity's own card is not among the sub-entries; tapping the card, a root item, a section item, and a section overview each opens `EditorPage` with the correct file content; a card-only entity folder shows just the card row without throwing.
  - [x] **Routing tests** (extend `test/app/browse_test.dart`): tapping a **simple** entity opens the editor directly (unchanged); tapping an **entity folder** opens the detail page (assert a section header or a sub-entry shows, not the raw editor).
  - [x] **Rescan test:** open detail → open a sub-entry → edit its heading → save → back → the detail row shows the new title (re-walk), mirroring the Story 2.2 live-update test.
  - [x] Re-run fixtures (4/4) and `npm test` (4/4) — must stay green (AC5). `flutter analyze` clean; `flutter test` green.

### Review Findings

Cross-model review (Opus 4.8 implementation, 3 Sonnet layers). The Acceptance Auditor independently re-ran the gates (`flutter analyze` clean, 135/135, `npm test` 4/4, `lore/`+contract git-clean) and **confirmed all 5 ACs fully implemented** with no Story 2.2 regression. Findings below are gaps the ACs/tests did not cover.

**Patch:**

- [x] [Review][Patch] **The entity-root node's `tree.overview` is never rendered — a "dual-card" folder's second card is stranded.** When an entity folder contains both `index.md` and `<name>.md`, the loader picks one as the card and sets the other as `tree.overview` (verified: `lore_loader.dart:382-390`); `_rows()` reads only `tree.items`/`tree.children`, so that file is unreachable in the UI (present only in the flat `entry.children`). Plausible via a rename between the two card conventions. Render `tree.overview` (as an Overview row under the card), mirroring how sections render `node.overview`. [apps/mobile/lib/app/entity_detail_page.dart _rows] (blind)
- [x] [Review][Patch] **No cap on indentation depth — deeply nested sections overflow / squeeze rows unreadably.** `depth * 16.0` left padding grows unbounded through `quests/<arc>/<chapter>/…`; on a narrow phone a deep hierarchy squeezes row content to an unreadable column (RenderFlex risk). Clamp the effective indent depth. [apps/mobile/lib/app/entity_detail_page.dart:_leaf, _sectionHeader] (edge+blind)
- [x] [Review][Patch] **Unreachable `node.title.isEmpty ? node.name` fallback in `_appendSection`.** The root (the only node with an empty title) is never passed here, so the fallback is dead code and is interpretive logic beyond "render verbatim" (AD-9). Render `node.title` directly. [apps/mobile/lib/app/entity_detail_page.dart _appendSection] (auditor)
- [x] [Review][Patch] **Test gap — the "entity gone after rescan" degrade state is untested** (Task 2's own acceptance). Add a widget test: delete the entity between scans and assert the "no longer present" state, no throw. [apps/mobile/test/app/entity_detail_page_test.dart] (auditor)
- [x] [Review][Patch] **Test gap — assertions are presence-only; order/nesting not verified.** Add an ordering assertion (card above items above sections; a nested item below its section header) so a "sections before card" or "flattened nesting" regression is caught. [apps/mobile/test/app/entity_detail_page_test.dart] (auditor)

**Deferred:**

- [x] [Review][Defer] **Rapid double-tap stacks duplicate routes** — on a detail leaf/card row (two `EditorPage` pushes) and on the entity row in `CategoryEntitiesPage` (two destinations). No navigation single-flight guard; pre-existing app-wide pattern deferred repo-wide since Story 2.1b/2.2. [apps/mobile/lib/app/entity_detail_page.dart _open; apps/mobile/lib/app/category_entities_page.dart _openEntity] (edge)
- [x] [Review][Defer] **Eager `ListView(children: _rows(entry))` vs `ListView.builder`** — materializes every row on each build, unlike the sibling `CategoryEntitiesPage`. A real NFR6 cost only for a very content-heavy entity; realistic single-entity trees are small, so the descriptor-based lazy refactor is disproportionate for v0.1. Revisit if entities grow large. [apps/mobile/lib/app/entity_detail_page.dart:93] (blind)

## Dev Notes

### What this story is — a rendering story over an already-built tree

The lore model **already contains the whole tree** (Story 2.1a): `LoreEntry.tree` is the entity folder's content tree, with `media/` excluded and the entity card excluded from its own children, and section titles already prettified. **This story renders that tree as a navigable outline — it adds no parsing, no filtering, and no model change.** If you find yourself calling `prettify`, skipping `media`, or excluding the card in the widget, stop: the model did it, and duplicating it risks diverging from the golden-fixture contract (AC5). Read the model, render it faithfully.

### The model shape you render (`apps/mobile/lib/lore/lore_model.dart`)

- **`LoreEntry.tree : LoreNode?`** — the entity folder's root node; **null for a simple entity** (drives AC4's branch). The root node's **`title` is `''`** (empty) — render its `items` under the card and its `children` as the top-level sections; don't print an empty header.
- **`LoreEntry.id`** — the entity card's loreDir-relative path → the card row's edit target.
- **`LoreNode`**: `name`, `title` (section header — the overview's `# heading` if it has one, else the prettified folder name), `overview : LoreOverview?` (the section's own card), `items : List<LoreItem>`, `children : List<LoreNode>` (nested sections).
- **`LoreItem`**: `title` (`"<ru> — <en>"` when paired, else the primary title), `group`, `passage`, `langs : Map<String, LoreLang>`. **To open it, use the primary variant's file:** `(langs['orig'] ?? langs['ru'] ?? langs['en'])!.file` — a **loreDir-relative** id.
- **`LoreLang.file`** — loreDir-relative path of that variant's file (named `file` to match the contract; it's an id, not an absolute path).
- **`LoreOverview.id`** — loreDir-relative path of a section's own card.
- **`LoreEntry.children : List<LoreChild>`** — a **flat** list of every sub-entry (excludes the card). You *could* render a flat list from this, but AC1 wants the **tree** (sections + nesting), so render `tree`, not `children`. `children` is there for other consumers (search, etc.).

**All leaf ids are loreDir-relative** → join `loreDir` before handing to `EditorPage`, exactly as `CategoryEntitiesPage._repoPath` does: `loreDir.isEmpty ? id : '$loreDir/$id'`. Empty `loreDir` (the picked folder is the lore folder) passes the id through unchanged.

### Files being MODIFIED / ADDED (read before editing)

- **`apps/mobile/lib/app/entity_detail_page.dart`** (NEW) — the detail tree; stateful, rescans on editor return.
- **`apps/mobile/lib/app/category_entities_page.dart`** (MODIFY) — current state: a `StatefulWidget` whose `_openEntity` pushes `EditorPage(_repoPath(entry.id))` for **every** entity, then `_rescan()`s the list. **Change:** branch in `_openEntity` — folder entity → `EntityDetailPage`, simple entity → editor (unchanged). **Preserve:** the `_rescan()` machinery, the `_repoPath` join, the FR5 one-node-type row rendering, and the class's rescan-on-return contract. The row's *appearance* must not change (still one node type); only the tap destination branches.
- **`apps/mobile/lib/app/editor_page.dart`** (reference, unchanged) — `EditorPage(storage: …, path: repoRelativePath)`; the leaf tap target. Save-on-pop + dirty guard already handled there.

### Design decision — simple entity vs entity folder (baked into the ACs)

- **Simple entity (`tree == null`) → editor directly** (AC4). A flat card has nothing to navigate; a detail page would be an empty-feeling extra tap, and Story 2.2 users value "navigate to any card" being quick.
- **Entity folder (`tree != null`) → detail page** (AC1). This is where the tree earns its place.
- A folder entity whose tree happens to be **card-only** (no items/sections) still opens the detail page (shows just the card row) — an acceptable, rare edge; do not special-case it beyond not-throwing. *(If the team later prefers a uniform detail page for all entities, that's a small change — but the fast path for simple cards is the recommended default.)*

### Rendering guidance (mobile, possibly-deep nesting)

- A **flat scrollable list** (`ListView`/`CustomScrollView`) built by recursively flattening `tree` into rows (card row, item rows, section-header rows, …) with an **indent level per depth** is the simplest robust approach; `ExpansionTile`s are also fine but add per-section state you don't need for v0.1. Quests nest as `quests/<quest>/`, so support arbitrary depth — don't hard-code two levels.
- Keep leaf rows visually uniform (title as the primary line); a section header is a non-tappable label (unless it has an `overview`, which is a separate tappable row beneath it). Distinguish the **entity card** row (top) from sub-entries with an icon/label so the author knows which is the card.

### Architecture guardrails

- **AD-8 / NFR7 — total.** The model is total; the UI just renders it. Handle empty lists and null `overview`/`tree` as states, never faults. The rescan is wrapped in try/catch that keeps the current view (AD-8 at the call site — the pattern the 1.3/1.4/2.1b/2.2 reviews all enforced).
- **AD-9 — purity.** No tree-shape logic in the widget; consume `LoreEntry.tree` as-is. The only UI-side computation is the loreDir→repo-path join (a UI concern, crossing model-space to storage-space) and flattening-for-display.
- **AD-10 — model rebuilt, never patched.** The detail view is a snapshot; edits are reflected by a full `loadLore` re-walk on editor return, then re-finding the entity by `id`. Never mutate the tree in place.
- **AD-2 — contract untouched.** Rendering only; no loader/model change; fixtures 4/4, `npm test` 4/4 (AC5).
- **NFR6 — instant.** The tree is already in memory; rendering is O(nodes). The rescan re-walks (a few hundred files) — acceptable per AD-10, same as 2.2.

### Previous story intelligence

- **2.2 (done):** `CategoryEntitiesPage` is stateful, joins `loreDir` onto model ids via `_repoPath`, and **rescans on editor return** (a review finding — the stale-snapshot fix). **Reuse that exact pattern** for `EntityDetailPage` (the same `_repoPath` and `_rescan` shape). The 2.2 review's recurring themes — nothing stranded, deterministic order, never strand the UI on an error, AD-8 at the call site — all apply here.
- **Requirement change (committed in `5ee1c50`):** the picked folder **is** the lore folder → `loreDir` is often `''`, so `_repoPath` must handle the empty case (it does). Also: the loader now skips dot-prefixed **files** as well as dirs, and there is **no root-promotion fallback** — none of this affects detail rendering, but keep `loreDir` flowing from Home → CategoryEntitiesPage → EntityDetailPage unchanged (don't re-resolve config in the detail page).
- **1.4 (done):** `EditorPage(storage, path)` opens a repo-relative path and handles dirty/save-on-pop. Leaves just push it.
- **Toolchain:** Flutter at `C:\programs\flutter\bin` (3.44.7 / Dart 3.12.2); `flutter analyze` + `flutter test`; `npm test` for the JS reference cross-check.

### Git intelligence

`5ee1c50` (Story 2.2 + the loreDir=root requirement change) is the baseline. `CategoryEntitiesPage` and the `_repoPath`/rescan pattern this story reuses were committed there. `LoreEntry.tree`/`LoreNode`/`LoreItem` were committed in `0f62c8a` (2.1a) and are unchanged since.

### Library / version policy

No new dependencies. Pure Dart tree traversal + existing Flutter Material widgets (`ListView`/`ListTile`/`Navigator`). Do not add a tree-view package.

### Testing standards

- **Detail rendering → widget tests** in `test/app/` using `FakeRepoStorage` (`dirEntries`/`fileContents`) — seed an entity folder with a card, a root sub-entry, an `events/` section, and a nested `quests/<quest>/` section, plus a `media/` folder to prove it's excluded. Assert structure, tap-to-editor for each leaf kind, and the card-only no-throw case.
- **Routing → extend `browse_test.dart`:** simple entity → editor; folder entity → detail page.
- **Rescan → live-update test** mirroring 2.2's.
- **Contract gate:** fixtures 4/4 and `npm test` 4/4 stay green; `git status --porcelain lib/lore.js test/fixtures/ scripts/` empty. This story touches none of them — verify, don't assume.

### Project Structure Notes

- New UI: `apps/mobile/lib/app/entity_detail_page.dart`; modified `apps/mobile/lib/app/category_entities_page.dart`. Pure model logic stays in `lore/` (unchanged). Consistent with the established `app/` (UI) + `lore/` (pure) split (the documented variance from the spine's "lore/ owns UI" wording, resolved in favor of the shipped layout).
- Tests: `apps/mobile/test/app/entity_detail_page_test.dart` (new) + additions to `apps/mobile/test/app/browse_test.dart`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.3] — user story + ACs (FR6)
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR6] — entity-detail content tree (`{overview, items, children}`; card, folder-named sections, nested quests; `media/` excluded)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-8] (total/never-throw), #AD-9 (purity), #AD-10 (model rebuilt), #AD-2 (fixtures are the contract)
- [Source: apps/mobile/lib/lore/lore_model.dart] — `LoreEntry.tree`, `LoreNode`, `LoreItem`, `LoreLang`, `LoreOverview`, `LoreChild` — the shapes you render
- [Source: apps/mobile/lib/lore/lore_loader.dart] — how the tree is built (media skip, card exclusion, `prettify`, overview resolution) — read-only context; do not modify
- [Source: apps/mobile/lib/app/category_entities_page.dart] — the `_repoPath` + `_rescan` pattern to reuse and the tap handler to branch
- [Source: apps/mobile/lib/app/editor_page.dart] — `EditorPage(storage, path)`, the leaf tap target
- [Source: _bmad-output/implementation-artifacts/2-2-browse-categories-and-entities.md] — prior story: rescan-on-return, id↔path join, one-node-type list
- [Source: _bmad-output/project-context.md] — entity-resolution rules (entity card not its own child; `media/` skipped; forward-slash ids)

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- `flutter analyze` → **No issues found.**
- `flutter test` → **135 passing** (128 → +7): 6 `EntityDetailPage` widget tests + 1 routing test.
- **Contract gate (AC5)** → fixtures pass (part of `flutter test`), `npm test` 4/4, and `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/` is **empty** — no loader/model/contract change (this story only renders the existing model).
- One test needed a fix during dev: the multi-leaf tap test originally re-`pumpWidget`ed inside a loop mid-navigation (stale routes); restructured to pump once and `pageBack()` between probes.

### Completion Notes List

- **This is a pure rendering story — the model does the heavy lifting.** `EntityDetailPage` reads `LoreEntry.tree` as-is: it does **not** prettify, skip `media/`, or exclude the entity card — the loader (Story 2.1a) already did all three, so FR6's guarantees (AC2) hold for free and the golden-fixture contract can't drift. No loader/model change; fixtures and `npm test` untouched (git-verified).
- **The detail outline:** the entity **card** on top (keyed, visually distinct with a "Card" subtitle), then the entity-root node's direct items, then its child folders as **sections** — each section a non-tappable header (`node.title`, already prettified) with an optional tappable **Overview** row (`node.overview`) and its items, recursing into nested sections with per-depth indentation (quests nest arbitrarily deep, not hard-coded to two levels). Every leaf taps into `EditorPage` via the loreDir→repo-path join.
- **Routing branch (AC4):** `CategoryEntitiesPage._openEntity` now branches on `entry.tree` — a folder entity opens the detail page; a **simple entity opens its card directly in the editor** (a flat card has no tree to navigate, keeping "navigate to any card" one tap). The list row's appearance is unchanged (still FR5 one node type); only the tap destination branches.
- **Snapshot + rescan reused from Story 2.2:** the detail page seeds from the passed `entry` and re-walks on editor return, re-finding the entity by its stable `id` (AD-10 rebuild), with the same AD-8 try/catch that keeps the current view on a walk failure. If the entity is gone after a rescan (deleted/renamed), it degrades to a "no longer present" state rather than showing a stale tree or throwing.
- **Never-throws (AC5):** a card-only entity folder renders just the card row; a null `overview` renders nothing for that slot; no list is assumed non-empty. Covered by a dedicated test asserting `tester.takeException()` is null.
- **RU/EN items** open their **primary** variant (`langs['orig'] ?? 'ru' ?? 'en'`) in the bare editor — the tabbed RU/EN editor is Story 2.8, deliberately not here.
- No new dependencies.

### File List

**Added:**
- `apps/mobile/lib/app/entity_detail_page.dart` (the detail-tree outline; stateful, rescans on editor return)
- `apps/mobile/test/app/entity_detail_page_test.dart` (6 widget tests: rendering, media/card exclusion, tap-to-editor for each leaf kind, card-only no-throw, rescan live-update)

**Modified:**
- `apps/mobile/lib/app/category_entities_page.dart` (`_openEntity` branches: folder entity → `EntityDetailPage`, simple entity → `EditorPage`; doc comment updated)
- `apps/mobile/test/app/browse_test.dart` (routing test: folder entity → detail tree, simple entity → editor)

**Deliberately NOT modified (verified git-clean):** `lib/lore.js`, `test/fixtures/lore-model/**`, `scripts/**`, `apps/mobile/lib/lore/**` (the model was rendered, not changed — AC5).

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-24 | Addressed code review (Opus 4.8 impl, 3 Sonnet layers): 5 patch findings fixed. **Reachability:** the entity-root node's `tree.overview` is now rendered as an Overview row, so a dual-card folder's (`index.md` + `<name>.md`) second card is no longer stranded. **Robustness:** indentation depth is clamped (`_kMaxIndentDepth`) so deeply nested quest hierarchies can't squeeze rows off-screen; removed the unreachable `node.title.isEmpty ? node.name` fallback (render verbatim, AD-9). **Coverage:** added tests for the dual-card overview, the "entity gone after rescan" degrade state, and row ordering/nesting (was presence-only). Tests 135 → 138; `flutter analyze` clean; fixtures 4/4; `npm test` 4/4; `lore/`+contract git-verified untouched. 2 findings deferred (rapid double-tap route stacking — pre-existing pattern; eager `ListView` vs `.builder` — disproportionate for small v0.1 trees). Blind Hunter's "dead `_rescan` catch" dismissed — kept intentionally as the AD-8-at-call-site guard. |
| 2026-07-24 | Implemented Story 2.3: view an entity's detail tree. New `EntityDetailPage` renders `LoreEntry.tree` as a navigable outline — card on top, folder-named sections (Events/Quests) with items and optional overview rows, nested quests nested with per-depth indentation — each leaf tapping into the editor. `CategoryEntitiesPage` now branches entity taps: folder entity → detail page, simple entity → editor directly. Reuses Story 2.2's loreDir→repo-path join and rescan-on-return (AD-10/AD-8). Pure rendering: no loader/model change, so `media/` exclusion, card-not-its-own-child, and prettified titles come from the model (2.1a) and the golden fixtures stay green. Tests 128 → 135 (+7); `flutter analyze` clean; fixtures 4/4; `npm test` 4/4; contract + `lore/` git-verified untouched. No new dependencies. |
