---
baseline_commit: 43bad3c
---

# Story 2.8: Edit RU/EN pairs safely

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want a paired RU/EN file shown as one item with tabs,
so that I can work bilingually without corrupting the pair.

## Acceptance Criteria

1. **AC1 (FR12 — RU/EN tabs, RU default):** Given a sub-entry that exists as a language pair (`<base>.ru.md` + `<base>.en.md`, i.e. a `LoreItem` whose `langs` has **two or more** variants), when I open it from the entity detail tree, then it opens a **tabbed editor** with one tab per language (`[RU] [EN]`, original/RU first), the **original (RU) tab selected by default**; each tab edits **its own** file. A single-variant item (`orig`-only, or only one of ru/en) opens the **plain single-file editor** exactly as today.
2. **AC2 (FR14 / AD-6 — per-file save, never merge):** Given I edit and save either tab, when the write happens, then it goes through `RepoStorage.writeAtomic` to **that language's individual file only** (`…​.ru.md` **or** `…​.en.md`), byte-exact; the app **never** writes a merged/combined file and never touches the other language's file. Each tab has its **own** dirty state, save, lossy guard, and conflict banner — independent of the other.
3. **AC3 (one editor implementation, reused — AD-7 spirit):** Given the paired editor, when it is built, then the per-file editing surface (load, highlighting controller, dirty tracking, atomic save with single-flight + save-pending, save-on-background, lossy-UTF-8 guard/banner, conflict banner, convention highlighting, and the Story 2.7 preview toggle) is **factored into a reusable widget** used by **both** the single-file editor **and** each RU/EN tab — the hardened logic is **not** reimplemented or forked. The existing `EditorPage` becomes a thin single-file host over it.
4. **AC4 (no lost edits across tabs — AD-10):** Given unsaved edits in one or both tabs, when I switch tabs, then each tab **keeps its own unsaved buffer** (switching never reloads/discards); and when I back out of the paired editor **or** the app is backgrounded, then **every** dirty tab is saved-or-asked (a lossy tab that can't be saved prompts before discarding) — no tab's edits are silently dropped.
5. **AC5 (no regression; contract untouched):** The single-file `EditorPage` behaves **identically** to today (all load/dirty/save/save-on-background/save-on-pop/lossy/conflict-banner/toolbar/convention-highlighting/preview-toggle behavior preserved — the existing editor, browse, detail, conflicts, and widget tests stay green). **No loader/model/contract change** — the model already provides `LoreItem.langs` (Story 2.1a); fixtures 4/4, `npm test` 4/4. `flutter analyze` clean; `flutter test` green with new paired-editor tests.

## Tasks / Subtasks

- [x] **Task 1 — Extract a reusable per-file editor (`FileEditor`) (AC: 3, 5)**
  - [x] Add `apps/mobile/lib/app/file_editor.dart` — move the per-file editing machinery **verbatim** out of `_EditorPageState` into a new `FileEditor` `StatefulWidget` with a **public** `FileEditorState`: the `ConventionHighlightingController`, `_load`, `_onChanged`/`_dirty`, `_save`/`_canSave` (single-flight + `_savePending`), `didChangeAppLifecycleState` save-on-background, the lossy `_lossyLoad` guard + banner, the `isConflictCopy` banner (Story 2.4), and the `_previewing` toggle body-swap (Story 2.7). It renders the **ready-state body** (conflict banner, lossy banner, then `MarkdownPreview` **or** `TextField`+`EditorToolbar`) plus the loading/error states — **no `Scaffold`/`AppBar`** of its own.
  - [x] Expose to a host (needed for the paired AppBar and the cross-tab pop guard): `bool get isDirty`, `bool get canSave`, `bool get isLossy`, `bool get isConflictCopy`, `bool get previewing`, `void togglePreview()`, `Future<void> save()`, and an `onStateChanged` `VoidCallback` (fired whenever dirty/preview/load-state changes) so the host can rebuild its AppBar. Keep `kDirtyIndicatorKey` semantics.
  - [x] Rework `apps/mobile/lib/app/editor_page.dart` into a **thin single-file host**: a `Scaffold` whose AppBar shows the path + dirty indicator + preview toggle + Save action (all bound to one `FileEditor` via a `GlobalKey<FileEditorState>`), a `PopScope` that delegates save-or-ask to that `FileEditor`, and `body: FileEditor(storage:, path:)`. **Public API unchanged:** `EditorPage({required storage, required path})` — every current call site and test keeps working. The AppBar actions and pop/background behavior now call through the `FileEditor` handle instead of local state.
  - [x] **Preserve every behavior** — the 1.4/2.4/2.5/2.6/2.7 reviews hardened save/dirty/pop/lossy/conflict/highlighting/preview. The existing `editor_page_test.dart` (and browse/detail/conflicts/widget tests) are the regression guard: they must pass **unchanged** (the `enterEditMode` helper still finds `Icons.edit_outlined`, Save is still `Icons.save_outlined`, the dirty key still resolves).
- [x] **Task 2 — The paired RU/EN editor (`PairedEditorPage`) (AC: 1, 2, 4)**
  - [x] Add `apps/mobile/lib/app/paired_editor_page.dart` — a `StatefulWidget` given the `LoreItem` (its `langs`) + `RepoStorage` + `loreDir`. Build the ordered variant list **original/RU first** (`ru`/`orig` before `en`) and a `TabController` (length = variant count, **initialIndex = the original/RU tab**). Render a `Scaffold` whose AppBar has the item title, a `TabBar` labeled by language (`RU` / `EN` / `Original`), and — reflecting the **active** tab's `FileEditor` — the dirty indicator + preview toggle + Save action. Body: `TabBarView` of one `FileEditor` per variant, each with a `GlobalKey<FileEditorState>` and given that variant's **repo-relative** file path.
  - [x] **Independent + kept-alive tabs (AC4):** each `FileEditor` owns its own buffer/dirty/lossy/save; `TabBarView` keeps both alive so switching never reloads (use `AutomaticKeepAlive`/`PageStorage` as needed, or confirm `TabBarView`'s default keep-alive suffices — verify a tab's unsaved edit survives a switch). Rebuild the AppBar (dirty/preview) on tab change and on each `FileEditor.onStateChanged`.
  - [x] **Pop + background across all tabs (AC4 / AD-10):** a `PopScope(canPop: none-dirty)` whose handler, for **every** tab's `FileEditor`, saves it if `canSave` else asks-before-discard (reuse the editor's discard dialog wording; a lossy tab can't be saved → prompt). A `WidgetsBindingObserver` saves **every** dirty+savable tab on background. Never merge — each `FileEditor.save()` writes only its own `path` (AD-6).
  - [x] Preview toggle in the paired AppBar toggles the **active** tab's `FileEditor` (per-tab preview state is fine; preview-first default from Story 2.7 applies per tab).
- [x] **Task 3 — Route paired items to the paired editor (AC: 1, 5)**
  - [x] In `apps/mobile/lib/app/entity_detail_page.dart`, change `_itemRow`/`_open` so a `LoreItem` with **≥2 language variants** (`item.langs.length >= 2`) pushes `PairedEditorPage(item, loreDir)`; a single-variant item pushes `EditorPage` for its one file (today's `primary?.file` path). Preserve the **rescan-on-return** (`_rescan` — AD-10/FR3) for both. Keep `_repoPath` id→repo-path joining (model ids are loreDir-relative; the editor is repo-relative).
  - [x] Leave `LoreOverview` rows and the entity **card** row on the single-file `EditorPage` (cards are single-language — only sub-entry `LoreItem`s carry `langs`).
- [x] **Task 4 — Tests (AC: 1–5)**
  - [x] **Paired-editor widget tests** (`test/app/paired_editor_page_test.dart`, with a `FakeRepoStorage` seeding both `x.ru.md` and `x.en.md`): opening a pair shows `[RU][EN]` tabs with **RU selected**; editing the RU tab and saving writes **only** `x.ru.md` (`writeCalls == [('…/x.ru.md', <ru text>)]`, `x.en.md` untouched); switching to EN, editing, saving writes **only** `x.en.md`; **switching tabs preserves** each tab's unsaved edit (edit RU → switch to EN → back to RU → RU text intact, still dirty); backing out with a dirty tab saves it (or, if lossy, prompts) — **no merged file is ever written** (assert no `writeCalls` entry targets a combined/base path).
  - [x] **Routing test** (`entity_detail_page_test.dart`): tapping a paired sub-entry opens `PairedEditorPage` (tabs present); tapping a single-variant sub-entry opens the plain `EditorPage` (no tabs) — both still `_rescan` on return.
  - [x] **Regression:** the full existing suite stays green after the `FileEditor` extraction (editor/browse/detail/conflicts/widget). Re-run the contract gate: `flutter analyze` clean; `flutter test` green; fixtures 4/4; `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/` **empty** (no model/loader/contract change).

### Review Findings

Cross-model review (Opus 4.8 implementation, 3 Sonnet layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor). The Auditor independently reproduced every gate (analyze clean, 240/240, `npm test` 4/4, contract/`lore/`/`storage/` git-clean, no pubspec change) and found all 5 ACs met; it also confirmed the per-file-save test genuinely rules out a merged write and that background-save is proven for a *non-active* tab. Blind + Edge converged (and Blind empirically reproduced with probe tests) on a real save-failure data-loss path plus a dirty-signal gap.

**Patch:**

- [x] [Review][Patch] **Med — backing out silently discards edits when the save fails (or is mid-flight).** `FileEditorState._save()` swallows a `writeAtomic` failure into a transient `ScaffoldMessenger` snackbar and returns `void`; both `_handlePop`s (`editor_page.dart` and `paired_editor_page.dart`) do `if (canSave) { await save(); … pop(); }` and pop **unconditionally**. Blind reproduced it: `FakeRepoStorage(failWrites: true)` + dirty + back → `writeCalls` empty, no discard dialog, route popped anyway — the edit is gone with no warning (violates the story's own "must not silently discard", AD-10). Pre-existing (the single-file editor had it) but 2.8 doubles the surface (per tab). Fix at the shared seam: `save()` returns `Future<bool>` (true = buffer persisted/clean; false on failure or in-flight); each `_handlePop` **does not pop when a save returns false** — the screen stays open with the edits and the snackbar. This also closes the `_savePending` in-flight race (Edge/Blind) safely. [apps/mobile/lib/app/file_editor.dart _save / editor_page.dart _handlePop / paired_editor_page.dart _handlePop] (blind+edge)
- [x] [Review][Patch] **Med — the paired AppBar dirty indicator reflects only the active tab.** `PairedEditorPage.build` computes the "Unsaved changes" dot from `active?.isDirty`, while `PopScope.canPop` correctly uses `_anyDirty`. Blind reproduced: dirty the EN tab, switch to the clean RU tab → no dot, even though EN holds unsaved edits (and the `Tab` labels give no hint either). The *action* is right (back-out saves every tab), but the *signal* undersells it — a user on RU can't tell EN is dirty. Fix: drive the AppBar dot from `_anyDirty`, and mark each dirty tab's label. [apps/mobile/lib/app/paired_editor_page.dart build/TabBar] (blind)
- [~] [Review][Skip] **Coverage — no paired-level test for the lossy-tab-prompts-on-pop branch.** AC4's `anyLossyDirty` branch is unexercised at the paired level (the single-file lossy-pop path is covered, and the paired branch reuses the same `FileEditor` lossy guard + shared `confirmDiscardUnsaved`). **Skipped by KseiPo's decision — de-emphasize UI/widget test coverage for now; cover business logic, not UI polish** ([[testing-emphasis]]). The code path exists and is sound by inspection/reuse. [apps/mobile/test/app/paired_editor_page_test.dart] (auditor)
- [x] [Review][Patch] **Low — hygiene.** The `paired_editor_page.dart` "RU default" comment is misleading (the logic prefers `orig`, matching the loader's primary, not literally RU) — reword. Add a defensive `?? langs.values.first` to `_openItem`'s single-file branch so a (loader-impossible) non-`{ru,en,orig}` key can't make a tappable row a silent no-op. [apps/mobile/lib/app/paired_editor_page.dart / entity_detail_page.dart _openItem] (blind+edge)

**Dismissed (5):** `PairedEditorPage` with empty `langs` crashes in `initState` — unreachable (routing sends only `langs.length >= 2`; `_itemRow` guards non-empty); a single-variant item with a non-`{ru,en,orig}` key silently no-ops — unreachable (the loader only ever emits `ru`/`en`/`orig`), and the P4 fallback covers it defensively anyway; `canPop` is `true` on the first frame before any `FileEditor` mounts — harmless (nothing can be dirty pre-load); mid-swipe the AppBar reflects the tab being dragged toward — cosmetic, settles on release; `_repoPath`/`_leaf` minor duplication — intentional/low-value. **Confirmed sound by Blind:** AD-6 (never merge — one `path` per `FileEditor`, no both-variants write path), the extraction is behavior-identical (verbatim move + `_notify` calls, no setState-during-build), keep-alive is correct, and back-out/background cover every dirty (kept-alive) tab.

## Dev Notes

### What this story is — a tabbed view over two files, one editor implementation

The model **already** merges a `<base>.ru.md` + `<base>.en.md` pair into one `LoreItem` whose `langs` map holds both variants (Story 2.1a; keys `ru`/`en`/`orig`, each `LoreLang` carries its own loreDir-relative `file` + `text`). So this story is **not** a model change — it's the editor/UI half of FR12/FR14: open a paired item as `[RU][EN]` tabs, and make each tab save **its own** file (AD-6, never merge).

The one real engineering decision is **how to avoid two divergent editor implementations.** The single-file editor (`EditorPage`) is heavily hardened (save single-flight + save-pending, save-on-background, save-on-pop, lossy-UTF-8 guard, conflict banner, convention highlighting, preview toggle — each added and reviewed across Stories 1.4/2.4/2.5/2.6/2.7). Reimplementing that for a two-file tabbed editor would fork it and invite drift. **So: extract the per-file editing surface into a reusable `FileEditor`, and compose it** — once in the single-file host, twice (in tabs) in the paired host. This is the AD-7 "one implementation, many consumers" instinct applied to the editor itself, and Story 2.9 (create-translation from a missing EN) reuses the same `PairedEditorPage`/`FileEditor`.

### The pairing model (how `langs` is keyed) — read before wiring the tabs

From `lore_loader.dart`: files in a folder are grouped by `base` (filename minus a `.ru`/`.en` suffix minus `.md`); a `.ru.md` → key `ru`, `.en.md` → key `en`, anything else → key `orig`. So:

- **A true pair** `x.ru.md` + `x.en.md` → `langs = {ru, en}`, title `"<ru title> — <en title>"`, RU is the original/primary. **→ this story's tabbed editor.**
- **Single language** (`x.md` → `{orig}`, or only `x.ru.md` → `{ru}`, or only `x.en.md` → `{en}`) → single-file editor. (A lone `.ru.md` with a *missing* `.en.md` is the "needs translation" case — **Story 2.9 / FR13**, not here. 2.8 opens the ≥2-variant pair; don't build the create-EN flow.)

Tab order/default: **original/RU first, selected by default** (FR12). Generalize safely: order `ru`/`orig` before `en`; default to the primary (`langs['orig'] ?? langs['ru'] ?? langs['en']`) — for the canonical ru+en pair this is the RU tab, satisfying FR12.

### AD-6 — the pair is a view; saves target the individual file

**Never write a merged file.** Each tab's `FileEditor` is constructed with **one** variant's repo-relative path and writes back to exactly that path via `writeAtomic`. There is no code path that concatenates or combines the two languages. The `"<ru> — <en>"` title is a **display** join only (from the model) — it is never a filename and never written. Test this explicitly: after editing both tabs, `writeCalls` contains only the two individual `.ru.md`/`.en.md` paths, never a base/combined path.

### Files being ADDED / MODIFIED (read before editing)

- **`apps/mobile/lib/app/file_editor.dart`** (NEW) — the extracted per-file editing surface (`FileEditor` + public `FileEditorState`). Everything currently in `_EditorPageState` **except** the `Scaffold`/`AppBar`; exposes `isDirty`/`canSave`/`isLossy`/`isConflictCopy`/`previewing`/`togglePreview()`/`save()` + an `onStateChanged` callback.
- **`apps/mobile/lib/app/editor_page.dart`** (MODIFY → thin host) — current state: a single `StatefulWidget` owning all per-file state + a `Scaffold(PopScope, AppBar[path+dirty+preview+save], body: Column[banners, TextField/preview, toolbar])` (Story 2.7). **Change:** keep the same public constructor; host one `FileEditor` via `GlobalKey<FileEditorState>`; the AppBar actions + `PopScope` + background-save delegate to that handle. Behavior must be identical (the tests prove it).
- **`apps/mobile/lib/app/paired_editor_page.dart`** (NEW) — the RU/EN `TabBar`/`TabBarView` host over two `FileEditor`s; active-tab AppBar actions; cross-tab pop/background save.
- **`apps/mobile/lib/app/entity_detail_page.dart`** (MODIFY) — current `_itemRow` opens `item.langs['orig'] ?? langs['ru'] ?? langs['en']` in `EditorPage` (it literally notes "RU/EN tabs are Story 2.8"). **Change:** route `langs.length >= 2` → `PairedEditorPage`, else the single-file `EditorPage`. Preserve `_repoPath` and `_rescan`-on-return.

**Do NOT modify** (verify git-clean): `apps/mobile/lib/lore/**` (the model already has `langs` — no loader/model change), `apps/mobile/lib/storage/**` (`writeAtomic` is enough — no new port method), `lib/lore.js`, `test/fixtures/**`, `scripts/**`.

### Architecture guardrails

- **AD-6 — RU/EN pairs are a view; saves target the individual file.** Every tab writes only its own `.ru.md`/`.en.md`; the app never writes a merged file. [ARCHITECTURE-SPINE.md#AD-6]
- **AD-4 / NFR1 — atomic byte-exact writes.** Each tab saves through the same `RepoStorage.writeAtomic` (temp+rename, preserved EOL/trailing newline, explicit UTF-8) — reused via `FileEditor`, not reimplemented. [#AD-4]
- **AD-10 — the editor owns the buffer; a structural op never strands a dirty buffer.** Switching tabs preserves each buffer; back/background save-or-ask across **all** tabs (no silent loss). Rescan-on-return still rebuilds the model (never patched). [#AD-10] [[ad8-call-site]]
- **AD-8 / NFR7 — total.** Malformed/lossy files still open per tab (the lossy guard + best-effort preview carry over from 2.6/2.7); a read/save failure in one tab surfaces its own error, never crashes the paired page. [#AD-8]
- **AD-7 spirit — one editor, many hosts.** `FileEditor` is the single per-file implementation; `EditorPage` and `PairedEditorPage` are thin hosts. No forked save/dirty/lossy logic. [#AD-7]
- **AD-2 — contract untouched.** No loader/model/fixtures change; `langs` already exists. Fixtures 4/4, `npm test` 4/4. [#AD-2]

### Previous story intelligence

- **2.1a (done):** `LoreItem.langs` (`Map<String,LoreLang>`, keys ru/en/orig) already carries both variants with per-variant `file`/`text`. `_itemRow` in `entity_detail_page.dart` currently opens the primary and comments that tabs are this story.
- **2.7 (done):** the editor opens **preview-first** (`_previewing` defaults true) with an AppBar toggle; `MarkdownPreview` is the read-only surface. This preview toggle is part of the per-file surface → it moves into `FileEditor` and each tab gets its own. Tests use a shared `enterEditMode` helper (`test/app/editor_test_helpers.dart`) that taps `Icons.edit_outlined` — reuse it for paired-editor tests that need the `TextField`.
- **1.4/2.4 (done) — the hardened bits to preserve exactly:** single-flight save + `_savePending` re-run; save-on-background (best-effort, `writeAtomic` is atomic so a killed write is safe); save-on-pop or ask; the lossy-UTF-8 guard that **disables save** and warns; the conflict-copy banner via exported `isConflictCopy`. Moving these into `FileEditor` must not alter them — the reviews caught real bugs here (dropped save-pending, pop discarding edits, lossy corruption), so lean on the existing tests.
- **Cross-model review ([[cross-model-code-review]])** finds a real issue every story — expect probing on: a tab silently reloading and losing edits on switch; back/background missing one tab; a save targeting the wrong file or a merged path; and any behavior drift in the single-file editor from the extraction. Cover these up front.
- **Toolchain:** Flutter `C:\programs\flutter\bin` (not on PATH — prefix it); `flutter analyze` + `flutter test`; `npm test` for the JS cross-check.

### Git intelligence

Baseline `43bad3c` (Story 2.7 merged). `app/` holds the editor/browse/detail/preview UI; the model (`lore/`) already provides `langs`. No paired-editor or `FileEditor` code exists yet. Branch per story, ff-merge to main, never push, model `Co-Authored-By` trailer ([[git-story-workflow]]).

### Library / version policy

**No new dependencies.** Tabs are Material `TabBar`/`TabBarView`/`TabController` (built-in). The editing surface, highlighting, preview, and atomic save are all existing code being **reused** via `FileEditor`. No markdown/tab/state package.

### Testing standards

- **Paired editor → widget tests** (`test/app/paired_editor_page_test.dart`): tabs + RU default; per-tab save writes only its own file; tab-switch preserves unsaved edits; cross-tab pop/background save; never a merged write.
- **Routing → widget test** (`entity_detail_page_test.dart`): ≥2-variant item → `PairedEditorPage`; single-variant → `EditorPage`; both rescan on return.
- **Regression → the whole existing suite** stays green after the `FileEditor` extraction (this is the main risk — the single-file editor must be behavior-identical).
- **Contract gate:** fixtures 4/4, `npm test` 4/4, `git status --porcelain … apps/mobile/lib/lore/` empty. This story is `app/`-only.

### Project Structure Notes

- New UI: `apps/mobile/lib/app/file_editor.dart`, `apps/mobile/lib/app/paired_editor_page.dart`.
- Modified UI: `apps/mobile/lib/app/editor_page.dart` (thin host over `FileEditor`), `apps/mobile/lib/app/entity_detail_page.dart` (route paired items).
- Tests: `apps/mobile/test/app/paired_editor_page_test.dart` (new); additions to `entity_detail_page_test.dart`; the existing editor/browse/conflicts/widget tests act as the extraction regression guard.
- No `lore/` or `storage/` change — `app/`-only, consistent with the established slice split.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.8] — user story + ACs (FR12 tabs/RU-default, FR14 individual-file save)
- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.9] — the next story (create EN from a missing translation) that **reuses** this paired editor; keep the create-EN flow out of 2.8
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR12] (RU/EN pair shown as one item with `[RU][EN]` tabs, RU default), #FR14 (always write the individual file; never collapse a pair)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-6] (RU/EN pairs are a view; saves target the individual file), #AD-4 (atomic byte-exact write), #AD-10 (editor owns the buffer; never strand a dirty buffer), #AD-8 (total), #AD-2 (contract untouched)
- [Source: apps/mobile/lib/lore/lore_model.dart] — `LoreItem.langs` (`Map<String,LoreLang>`, keys ru/en/orig; each `LoreLang.file` is the loreDir-relative path to write)
- [Source: apps/mobile/lib/lore/lore_loader.dart] — the language grouping (`_langRe = \.(ru|en)\.md$`; base-grouped; original-first title) that defines what a "pair" is
- [Source: apps/mobile/lib/app/editor_page.dart] — the hardened single-file editor to extract into `FileEditor` and preserve behavior-identically
- [Source: apps/mobile/lib/app/entity_detail_page.dart] — `_itemRow`/`_open` (currently opens the primary; routes to the paired editor here)
- [Source: _bmad-output/implementation-artifacts/2-7-preview-rendered-markdown.md] — the preview toggle now part of the per-file surface; the `enterEditMode` test helper
- [Source: _bmad-output/project-context.md] — "Bilingual scenes are paired files: `base.ru.md` + `base.en.md`"; a missing `.en.md` is a deliberate "needs translation" signal (Story 2.9), not a defect; write individual files, never merge

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Claude Opus 4.8)

### Debug Log References

- Baseline before work: `flutter test` 232 passing, analyze clean.
- **Task 1 (extraction) regression guard:** after moving the per-file machinery into `FileEditor` and making `EditorPage` a thin host, the existing editor + browse + detail + conflicts + widget tests (55 in that subset) passed **unchanged** — the single-file editor behaves identically.
- One extraction bug caught by analyze: the new public getter `isConflictCopy` shadowed the imported `isConflictCopy` loader function (`invocation_of_non_function_expression`) — fixed by importing `lore` prefixed and calling `lore.isConflictCopy(...)`.
- `flutter analyze` → **No issues found.**
- `flutter test` → **240 passing** (232 → +8: 6 paired-editor + 2 routing).
- **Contract gate (AC5):** `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/ apps/mobile/lib/storage/` **empty** — no model/loader/storage change (the model already provides `langs`; `writeAtomic` was enough).

### Completion Notes List

- **One editor implementation, three hosts (AD-7 spirit).** Extracted the hardened per-file editing surface (`ConventionHighlightingController`, load, dirty tracking, atomic save with single-flight + save-pending, save-on-background, lossy-UTF-8 guard/banner, conflict banner, convention highlighting, the Story 2.7 preview toggle) into `app/file_editor.dart` (`FileEditor` + **public** `FileEditorState`). It renders the body only — no `Scaffold`/`AppBar` — and exposes `isDirty`/`canSave`/`isLossy`/`isReady`/`isConflictCopy`/`previewing`/`togglePreview()`/`save()` + an `onStateChanged` callback so a host can drive its chrome. `EditorPage` is now a thin single-file `Scaffold` host over one `FileEditor` (same public constructor — every call site/test unchanged); the discard-dialog was factored into a shared `confirmDiscardUnsaved`.
- **`PairedEditorPage` — a tabbed view over two files (FR12/FR14/AD-6).** For a `LoreItem` with ≥2 `langs`, it builds a `TabController` (variants ordered original/RU first, **RU/primary selected by default**) and a `TabBarView` of one `FileEditor` per variant, each given that variant's repo-relative path. The AppBar (title + `TabBar` + dirty indicator + preview toggle + Save) reflects the **active** tab. **Each save writes only its own `.ru.md`/`.en.md` via `writeAtomic` — the pair is never merged** (the `"<ru> — <en>"` title is display-only). Tabs are kept alive (an `AutomaticKeepAlive` wrapper) so switching **never reloads/discards** an unsaved buffer; back-out saves-or-asks across **all** tabs; and background-save is automatic per tab (each `FileEditor` keeps its own lifecycle observer). Verified: RU-save writes only `.ru.md`, EN-save only `.en.md`, tab-switch preserves edits, pop saves the dirty tab, background saves both — and no merged path is ever written.
- **Routing.** `entity_detail_page._itemRow` now taps into `_openItem(item)`: `langs.length >= 2` → `PairedEditorPage`, else the plain `EditorPage` for the single file. Both re-walk on return (rescan preserved). Cards/overviews stay single-file (only sub-entry `LoreItem`s carry `langs`).
- **No model/loader/storage change.** The pairing already exists in `LoreItem.langs` (Story 2.1a) and `writeAtomic` already targets individual files — this story is `app/`-only. `lore/`, `storage/`, and the JS contract are git-clean.
- **Story 2.9 (create-EN from a missing translation) reuses this** `PairedEditorPage`/`FileEditor` — it will add the empty-EN "needs translation" tab + create-on-save, not a new editor.

### File List

**Added:**
- `apps/mobile/lib/app/file_editor.dart` (the reusable per-file editing surface — `FileEditor` + public `FileEditorState`)
- `apps/mobile/lib/app/paired_editor_page.dart` (the RU/EN tabbed editor over two `FileEditor`s)
- `apps/mobile/test/app/paired_editor_page_test.dart`

**Modified:**
- `apps/mobile/lib/app/editor_page.dart` (thin single-file host over `FileEditor`; shared `confirmDiscardUnsaved`; `kDirtyIndicatorKey` retained)
- `apps/mobile/lib/app/entity_detail_page.dart` (`_openItem` routes paired items to `PairedEditorPage`, single files to `EditorPage`; rescan-on-return preserved)
- `apps/mobile/test/app/entity_detail_page_test.dart` (RU/EN pair-routing tests)
- `apps/mobile/test/app/editor_page_test.dart` (review P1: failed-save-on-back keeps the screen — never discards)

**Deliberately NOT modified (verified git-clean):** `apps/mobile/lib/lore/**` (model already provides `langs`), `apps/mobile/lib/storage/**` (`writeAtomic` sufficient — no new port method), `lib/lore.js`, `test/fixtures/**`, `scripts/**`.

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-26 | Addressed code review (Opus 4.8 impl, 3 Sonnet layers), 3 patches applied + 1 test-coverage finding skipped by author decision. **Med (P1, data-loss — confirmed by probe):** backing out with a **failed** (or in-flight) save popped the screen and silently discarded the edit, because `_save()` swallowed write failures into a snackbar and returned void while both `_handlePop`s popped unconditionally. Fixed at the shared seam: `FileEditorState.save()` now returns `Future<bool>` (persisted?), and neither host navigates away on a false result — the screen stays with the edit. This hardens the single-file editor too. **Med (P2):** the paired dirty indicator now reflects **any** dirty tab (AppBar dot on `_anyDirty`) plus a per-tab marker, so a dirty background language is discoverable. **Low (P4):** reworded the misleading "RU default" comment; added a defensive `?? langs.values.first` fallback. **Skipped (P3):** a paired lossy-pop widget test — de-emphasizing UI test coverage for now (business logic is covered; the branch reuses the tested single-file guard). Added one data-loss guard test (failed-save-on-back keeps the screen). Tests 240 → 241; analyze clean; `npm test` 4/4; contract/`lore/`/`storage/` git-clean. |
| 2026-07-26 | Implemented Story 2.8: edit RU/EN pairs safely (FR12/FR14/AD-6). Extracted the hardened per-file editing surface into a reusable `FileEditor` (public `FileEditorState`); `EditorPage` became a thin single-file host over it (behavior-identical — existing tests unchanged). Added `PairedEditorPage`: a `[RU][EN]` `TabBar`/`TabBarView` (RU default) of one `FileEditor` per language, each saving **only its own** `.ru.md`/`.en.md` via `writeAtomic` — the pair is never merged. Tabs kept alive (switch preserves unsaved edits); back-out saves-or-asks across all tabs; background-save is per-tab automatic. `entity_detail_page` routes `langs.length >= 2` → paired editor, else the plain editor (rescan-on-return preserved). No new deps; no loader/model/storage/contract change (the model already carries `langs`). Tests 232 → 240 (+8); analyze clean; `npm test` 4/4; `lore/`+`storage/`+contract git-clean. |
