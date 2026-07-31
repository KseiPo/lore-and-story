---
baseline_commit: 810cfa3
---

# Story 2.10: Create a new entity

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to create a new card,
so that I can add a race or location from the phone.

## Acceptance Criteria

1. **AC1 (FR24 — create a simple entity):** Given a category screen, when I trigger "create entity" and enter a title, then a new `<slug>.md` file seeded with `# Title\n` is written to the category folder via the atomic writer (`RepoStorage.writeAtomic`). The slug is derived from the title (lowercased, spaces→hyphens, ASCII-safe). After creation, the model rescans and the new entity appears in the category's list.
2. **AC2 (FR24 — new top-level category):** Given I create the first entity of a brand-new top-level category (a category folder that does not yet exist under `loreDir`), when I confirm, then the category folder is created first (via a new `RepoStorage.ensureDir`), and then the `.md` file is written inside it. The category appears in the home screen's categories list after rescan.
3. **AC3 (RU/EN awareness):** Given the project's bilingual convention, when I create a new entity, then the file is created as `<slug>.ru.md` (the project's default authoring language). The loader will classify it as a lone `.ru.md` (a translation candidate) — consistent with the existing convention that `.en.md` is created later (Story 2.9 / FR13).
4. **AC4 (open the new entity after creation):** Given the entity is created, when the write succeeds, then the editor opens on the new file so the author can immediately start writing content beyond the seed `# Title\n`.
5. **AC5 (AD-4 / NFR1 — atomic byte-exact):** Given any create, when the write happens, then it goes through `writeAtomic` — atomic (temp+rename), explicit UTF-8, byte-exact. No new writer.
6. **AC6 (AD-8 / NFR7 — total, never crash):** Given invalid input (empty title, a title that produces an empty slug, a write failure, a missing category folder for non-new-category creates), when the create is attempted, then the UI shows an error message and never crashes. A failed write does not navigate to the editor.
7. **AC7 (AD-10 — model rebuilt):** Given a successful create, when the author returns from the editor, then the calling screen (category entities page or home page) rescans via `loadLore` — the existing rescan-on-return pattern — and the new entity appears without manual refresh.
8. **AC8 (no regression):** No loader/model change. The `RepoStorage` port gains only `ensureDir`. All existing tests stay green. `flutter analyze` clean; `flutter test` green; fixtures 4/4; `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/` **empty** (lore/ model/loader untouched).

## Tasks / Subtasks

- [x] **Task 1 — Add `ensureDir` to `RepoStorage` port + adapter + fake (AC: 2, 5, 8)**
  - [x] Add `Future<void> ensureDir(String path)` to `RepoStorage` in `apps/mobile/lib/storage/repo_storage.dart`. Docstring: creates the directory (and any missing parents) at the repo-relative path; a no-op if it already exists; throws `RepoStorageException` on failure. Paths are repo-relative, forward-slash normalized (same contract as every other port method).
  - [x] Implement in `AllFilesRepoStorage` (`apps/mobile/lib/storage/all_files_repo_storage.dart`): normalize the path via `_normalizeRepoPath`, translate to OS path via `_toOsPath`, call `Directory(osPath).create(recursive: true)`, catch `FileSystemException` → `RepoStorageException`. This is the **only** `dart:io` touch (AD-3/AD-9).
  - [x] Implement in `FakeRepoStorage` (`apps/mobile/test/fakes.dart`): record the path in a new `ensureDirCalls` list; add the path to `_dirEntries` (with an empty list) so subsequent `listDir`/`exists` reflect it.
  - [x] Re-export if needed from `apps/mobile/lib/storage/storage.dart` (the barrel).
- [x] **Task 2 — Create-entity UI flow on `CategoryEntitiesPage` (AC: 1, 3, 4, 5, 6, 7)**
  - [x] Add a FAB (FloatingActionButton) with an add icon to `CategoryEntitiesPage` (`apps/mobile/lib/app/category_entities_page.dart`). Tapping it opens a dialog (`showDialog` / `AlertDialog`) prompting for an entity title (a `TextField`).
  - [x] On confirm: derive the slug from the title (`title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'[^a-z0-9\-]'), '')`). Validate: if slug is empty after sanitization, show an error (snackbar or inline) and do not proceed.
  - [x] Compute the file path: `<category-folder>/<slug>.ru.md` (repo-relative, forward-slash normalized). The category folder path = `widget.loreDir` (if non-empty, prefix it) + the category key. Use `_repoPath(widget.category.key)` as the category's repo-relative folder.
  - [x] **Guard against clobbering:** check `storage.exists(filePath)` before writing. If the file already exists, show an error ("An entity with this name already exists") and do not write (AD-4 safety — a create must not silently overwrite).
  - [x] Write the seed: `storage.writeAtomic(filePath, '# $title\n')`. On success, push `EditorPage(storage: storage, path: filePath)` so the author lands in the editor (AC4). On failure (the `writeAtomic` throws), show an error snackbar and do not navigate.
  - [x] On return from the editor, the existing `_rescan()` fires (AD-10) — no new refresh logic needed.
- [x] **Task 3 — Create entity with a new top-level category (AC: 2, 6)**
  - [x] Add a "New category" entry point: either on the home page (`_ReadyView`) as a secondary action, or as a separate option in the category-entities create dialog (e.g., a "Create in new category" flow reachable from the home page).
  - [x] **Recommended approach:** Add a FAB on the home page's `_ReadyView`. Tapping it opens a dialog that asks for **both** a category name and an entity title. The category name derives a folder slug (same sanitization as the entity slug). The entity title derives the entity file slug. On confirm:
    1. Compute the category folder path: `<loreDir>/<category-slug>` (repo-relative).
    2. Call `storage.ensureDir(categoryFolderPath)` to create the folder.
    3. Compute the file path: `<categoryFolderPath>/<entity-slug>.ru.md`.
    4. Guard against clobbering (`exists` check).
    5. `writeAtomic(filePath, '# $title\n')`.
    6. On success, push the editor. On return, `_refresh()` fires (AD-10) and the new category appears.
  - [x] An `ensureDir` failure → error snackbar, no navigate, no write. A `writeAtomic` failure after a successful `ensureDir` → error snackbar, no navigate (the empty folder will be harmless — the loader treats a folder with no card as a nested category, and an empty nested category produces nothing; it self-corrects on the next create or file drop).
- [x] **Task 4 — Tests (AC: 1–8)**
  - [x] **Create entity (data-safety core)** (`test/app/create_entity_test.dart`): seed a `FakeRepoStorage` with a category and its entities; tap the FAB, enter a title, confirm; assert `writeCalls` contains exactly one entry `('<category>/<slug>.ru.md', '# Title\n')`; assert no `ensureDirCalls` (existing category). Assert the editor opens (find `EditorPage` in the navigator). Verify a duplicate-slug create is rejected (seed the file, try to create, assert no write + error shown).
  - [x] **Create in new category** (`test/app/create_entity_test.dart`): seed a `FakeRepoStorage` with an existing lore model; tap the home FAB, enter a category name and entity title, confirm; assert `ensureDirCalls` contains the new category path; assert `writeCalls` contains `('<loreDir>/<cat-slug>/<entity-slug>.ru.md', '# Title\n')`.
  - [x] **Error paths**: empty title → no write, error shown; special-char-only title → no write; `writeAtomic` failure (use `failWrites: true`) → error snackbar, no editor navigation; cancel dialog → no write.
  - [x] **Regression:** the full existing test suite stays green. Contract gate: `flutter analyze` clean; `flutter test` 255/255; fixtures 4/4; `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/` **empty**.

### Review Findings

- [x] [Review][Patch] **Hero tag clash — duplicate FABs crash navigation** [category_entities_page.dart:148, home_page.dart:329] — Both `FloatingActionButton` widgets use the default `heroTag`. When pushing from HomePage to CategoryEntitiesPage, both FABs coexist during the route transition, triggering Flutter's "multiple heroes with the same tag" assertion. Fix: added `heroTag: null` to both FABs. **HIGH**
- [x] [Review][Patch] **Hyphen-only slug accepted as valid** [category_entities_page.dart:157, home_page.dart:556] — A title like `"!! !!"` slugifies to `"-"`, which passes the `isEmpty` check and creates a file named `-.ru.md`. Fix: added `.replaceAll(RegExp(r'^-+|-+$'), '')` to strip leading/trailing hyphens. **MEDIUM**
- [x] [Review][Patch] **Narrow catch violates AD-8 at the call site** [category_entities_page.dart:93, home_page.dart:292] — Both create methods catch only `on RepoStorageException`. Any other exception propagates uncaught past the UI boundary. Fix: added `catch (_)` fallback after the specific catch. **MEDIUM**
- [x] [Review][Patch] **Clobber check is language-suffix-blind** [category_entities_page.dart:85, home_page.dart:282] — The "already exists" guard only checked `<slug>.ru.md`. Fix: expanded to also check `<slug>.md` and `<slug>.en.md`. **MEDIUM**
- [x] [Review][Patch] **New-category flow silently merges into existing category** [home_page.dart:280] — `ensureDir` is a no-op for existing dirs. Fix: added `exists` check before `ensureDir` and info snackbar when category already exists. **LOW**

## Dev Notes

### What this story is — a create-entity flow, on top of the browse + edit foundation

Stories 2.1–2.9 built the complete browse → edit → save → RU/EN pipeline. This story adds the **first authoring op**: creating a brand-new simple entity from the phone. It is a thin flow — a dialog collecting a title, a slug derivation, a `writeAtomic` of the seed `# Title\n`, and an editor push — on top of the existing `CategoryEntitiesPage` and `HomePage`. No model/loader change: the loader already picks up any `.md` file in a category folder on the next walk.

### The slug derivation — keep it simple and safe

The slug must produce a valid, portable, syncer-friendly filename. Derive it from the title: lowercase, whitespace→hyphens, strip non-`[a-z0-9\-]`. This matches the hand-authored slugs in the existing lore (`selena`, `raven-s-nest`, `the-wandering-fox`). An empty slug after sanitization (e.g. a title of only special characters) is an error — reject with a message, don't write.

The file is always `.ru.md` (AC3): the project's convention is that new content is authored in RU first, and the EN translation is created later (Story 2.9 / FR13). The loader's `_langRe` will classify it as `langs['ru']`, and the entity detail page will show the "needs translation" badge from Story 2.9.

### Why `ensureDir` on the port — and why `writeAtomic` is not enough

`writeAtomic` writes a temp file in the **same directory** as the target, then renames. If the parent directory doesn't exist (a brand-new category), the temp-file creation throws `FileSystemException`. We cannot silently add `mkdir -p` inside `writeAtomic` — that changes its contract for all callers and masks bugs where a path is wrong. Instead, add an explicit `ensureDir(path)` to the port (AD-3: all filesystem access through the port), called **before** `writeAtomic` only when creating a new category. This is a minimal, testable, opt-in extension.

### The existing rescan-on-return handles refresh

Both `CategoryEntitiesPage._rescan()` and `HomePage._refresh()` already re-walk on return from a pushed page. After the create + editor round-trip, the entity (and any new category) appears automatically — no new refresh logic needed (AD-10).

### Clobber guard — why we check `exists` before writing

`writeAtomic` is a blind overwrite (temp+rename replaces any existing file). For a **create** op, silently overwriting an existing entity would be data loss. An `exists` check before writing prevents this. The TOCTOU window (a syncer drops a file between `exists` and `writeAtomic`) is accepted per the project's AD-5 stance — the external syncer owns propagation, and a collision produces a `*.sync-conflict-*` copy that Story 2.4 surfaces. The check is still valuable for the common case (the author accidentally taps Create twice, or picks a name that already exists).

### Files being MODIFIED (read before editing)

- **`apps/mobile/lib/storage/repo_storage.dart`** (MODIFY) — add `Future<void> ensureDir(String path)` to the `RepoStorage` interface. One new method, nothing else changes.
- **`apps/mobile/lib/storage/all_files_repo_storage.dart`** (MODIFY) — implement `ensureDir`: normalize path, translate to OS path, `Directory(osPath).create(recursive: true)`, catch→wrap. The only `dart:io` touch.
- **`apps/mobile/lib/app/category_entities_page.dart`** (MODIFY) — add a FAB + create-entity dialog. The `_openEntity`/`_rescan` machinery is unchanged; the create flow sits beside it.
- **`apps/mobile/lib/app/home_page.dart`** (MODIFY) — add a FAB to `_ReadyView` for the "create in new category" flow. The `_refresh`/`_scanOnce`/`_openCategory` machinery is unchanged.
- **`apps/mobile/test/fakes.dart`** (MODIFY) — implement `ensureDir` in `FakeRepoStorage` (record + add to `_dirEntries`).

**Do NOT modify** (verify git-clean): `apps/mobile/lib/lore/**` (no model/loader change — the loader already discovers `.md` files on the next walk), `lib/lore.js`, `test/fixtures/**`, `scripts/**`.

### Architecture guardrails

- **AD-3 — all filesystem access through `RepoStorage`.** The new `ensureDir` is a port method; no `dart:io` outside the adapter. [ARCHITECTURE-SPINE.md#AD-3]
- **AD-4 / NFR1 — every write atomic and byte-exact.** Creates go through `writeAtomic` (temp+rename); `ensureDir` is a separate, explicit step that only creates directories. No new writer. [#AD-4]
- **AD-8 / NFR7 — total, never crash.** Empty slug, duplicate name, write failure, ensureDir failure — all surface error messages, never throw past the UI boundary. [#AD-8]
- **AD-9 — model purity per-slice.** `ensureDir` is in the port (pure Dart); implementation is in the adapter (`dart:io`). No import leaks. [#AD-9]
- **AD-10 — model rebuilt, never patched.** After create + editor, the caller's `_rescan()` / `_refresh()` re-walks from disk. No in-memory model mutation. [#AD-10]
- **AD-12 — slice internals private.** `ensureDir` is exposed on the public `RepoStorage` port, re-exported via the barrel. No internal leak. [#AD-12]

### Previous story intelligence

- **2.9 (done):** `FileEditor` has `createIfMissing` mode (an absent file opens as an empty buffer; first save creates it). Story 2.10 does **not** need `createIfMissing` — the entity file is created by the dialog's `writeAtomic` *before* the editor opens, so the editor opens an existing file. This is a deliberate difference: 2.9's EN tab creates on first save because the create surface IS the editor (the author types the translation); 2.10's create is a one-shot seed (`# Title\n`) and the editor is for writing content into an already-existing file.
- **2.8 (done):** `PairedEditorPage` and the save/dirty/pop contract — unchanged, not involved.
- **2.7 (done):** Preview toggle — the new entity opens in the plain `EditorPage` (not `PairedEditorPage`). A freshly-created `.ru.md` with only `# Title\n` opens preview-first per 2.7; brief but harmless.
- **project testing-emphasis:** Cover the **business logic** — create writes the correct file, slug derivation, clobber guard, error paths. Don't over-invest in UI tests for the dialog appearance.
- **Cross-model review ([[cross-model-code-review]]):** Expect probing on: slug derivation edge cases (Unicode titles, all-special-char titles), clobber guard (exists→write race), `ensureDir` creating deeply nested paths, the `.ru.md` convention, and whether a failed create strands a dirty buffer (it shouldn't — the editor isn't opened on failure).

### Git intelligence

Baseline `810cfa3` (Story 2.9 merged + epic restructure). Branch per story, ff-merge to main, never push, model `Co-Authored-By` trailer ([[git-story-workflow]]).

### Library / version policy

**No new dependencies.** `ensureDir` uses `Directory.create(recursive: true)` from `dart:io` (already imported in the adapter). The dialog uses `showDialog`/`AlertDialog`/`TextField` — all Material, already available.

### Testing standards

- **Create entity → widget tests** in `test/app/`: FAB tap → dialog → title entry → confirm → assert `writeCalls` (correct path, correct seed content); assert editor navigation; assert no `ensureDirCalls` for an existing category.
- **Create in new category → widget test**: assert `ensureDirCalls` + `writeCalls` (correct paths).
- **Error paths → widget tests**: empty slug → error, no write; duplicate exists → error, no write; write failure → error snackbar, no navigation.
- **Regression → the whole existing suite** stays green.
- **Contract gate:** fixtures 4/4, `npm test` 4/4, `git status --porcelain … apps/mobile/lib/lore/` empty. `storage/` changes limited to the port + adapter (the `ensureDir` addition); `app/`-only UI changes.

### Project Structure Notes

- Storage port extended: `repo_storage.dart` gains `ensureDir`; `all_files_repo_storage.dart` gains its `dart:io` implementation.
- UI only: `category_entities_page.dart` (FAB + create dialog for existing categories); `home_page.dart` (FAB + create dialog for new categories).
- Tests: additions to `category_entities_page_test.dart`, `home_page_test.dart`, `fakes.dart`.
- No `lore/` change — the loader already discovers new `.md` files on the next walk.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.10] — user story + ACs (FR24: create new entity with `# Title` seed; create category folder for new categories)
- [Source: _bmad-output/planning-artifacts/prds/prd-lore-and-story-2026-07-19/prd.md#FR24] (create a new simple entity in a chosen category, seed `# Title`, may create the category folder)
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-3] (all filesystem access through the port), #AD-4 (atomic byte-exact write), #AD-8 (total, never crash), #AD-9 (I/O isolated to adapter), #AD-10 (model rebuilt), #AD-12 (slice internals private)
- [Source: apps/mobile/lib/storage/repo_storage.dart] — the port gaining `ensureDir`
- [Source: apps/mobile/lib/storage/all_files_repo_storage.dart] — the adapter implementing `ensureDir` (`Directory.create(recursive: true)`)
- [Source: apps/mobile/lib/app/category_entities_page.dart] — FAB + create-entity dialog for existing categories
- [Source: apps/mobile/lib/app/home_page.dart] — FAB + create dialog for new categories
- [Source: apps/mobile/lib/lore/lore_loader.dart#_walkCategory] — how the loader discovers `.md` files in category folders (unchanged by this story)
- [Source: apps/mobile/lib/lore/lore_browse.dart#categoriesOf] — how categories are grouped from entries (unchanged)
- [Source: _bmad-output/implementation-artifacts/2-9-create-a-translation-from-a-missing-en.md] — the `FileEditor.createIfMissing` pattern (NOT used here — different design: 2.10 creates the file before opening the editor)
- [Source: _bmad-output/project-context.md] — entity resolution rules, bilingual conventions, testing emphasis

## Dev Agent Record

### Agent Model Used

claude-opus-4-6 (Claude Opus 4.6)

### Debug Log References

- Baseline before work: `flutter test` 245 passing, analyze clean.
- `flutter analyze` → **No issues found.**
- `flutter test` → **255 passing** (245 → +10: 6 create-in-existing-category + 4 create-in-new-category). Focused on the create/clobber-guard/error-path business logic per the project testing-emphasis.
- **Contract gate (AC8):** `npm test` 4/4; `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/` **empty** — no model/loader change; the loader already discovers new `.md` files on the next walk.

### Completion Notes List

- **`RepoStorage.ensureDir` (port + adapter + fake).** Added `Future<void> ensureDir(String path)` to the `RepoStorage` interface. `AllFilesRepoStorage` implements it via `Directory(osPath).create(recursive: true)` with `FileSystemException` → `RepoStorageException` wrapping — the only `dart:io` touch (AD-3/AD-9). `FakeRepoStorage` records calls in `ensureDirCalls` and registers the path in `_dirEntries` so `exists`/`listDir` reflect it. Already re-exported via the barrel.
- **Create entity in existing category (`CategoryEntitiesPage`).** Added a FAB that opens a dialog prompting for a title. On confirm: derives slug (lowercase, spaces→hyphens, strip non-`[a-z0-9\-]`); validates non-empty slug; computes `<category>/<slug>.ru.md` path; guards against clobbering via `exists` check; writes `# Title\n` via `writeAtomic`; pushes `EditorPage` on success. On return, the existing `_rescan()` fires (AD-10). Error paths: empty/invalid slug → snackbar; duplicate name → snackbar; write failure → snackbar, no navigation.
- **Create entity in new category (`HomePage`).** Added a FAB (visible only in ready state) that opens a two-field dialog (category name + entity title). On confirm: derives both slugs; validates both non-empty; calls `ensureDir` on the category folder path; guards against clobbering; writes the seed; pushes the editor. On return, `_refresh()` fires and the new category appears in the categories list. Error paths mirror the category-entities flow.
- **All entities created as `.ru.md`** (AC3) — consistent with the project convention that new content is authored in RU first; EN translation created later via Story 2.9's flow.
- **No model/loader/storage-contract change** — three UI files + one port extension + one adapter method + one fake method. `lore/` slice git-clean.

### File List

**Modified:**
- `apps/mobile/lib/storage/repo_storage.dart` (add `ensureDir` to `RepoStorage` interface)
- `apps/mobile/lib/storage/all_files_repo_storage.dart` (implement `ensureDir` via `Directory.create(recursive: true)`)
- `apps/mobile/lib/app/category_entities_page.dart` (FAB + create-entity dialog + `_createEntity` + `_slugify` + `_showCreateEntityDialog`)
- `apps/mobile/lib/app/home_page.dart` (FAB on `_ReadyView` + `_createInNewCategory` + `_slugify` + `_showNewCategoryDialog` + `_NewCategoryResult`)
- `apps/mobile/test/fakes.dart` (`FakeRepoStorage.ensureDir` + `ensureDirCalls`)

**New:**
- `apps/mobile/test/app/create_entity_test.dart` (10 tests: create in existing category, clobber guard, empty/invalid slug, write failure, cancel; create in new category with ensureDir, empty category/entity names, write failure)

**Deliberately NOT modified (verified git-clean):** `apps/mobile/lib/lore/**`, `lib/lore.js`, `test/fixtures/**`, `scripts/**`.

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-31 | Implemented Story 2.10: Create a new entity (FR24). Extended `RepoStorage` with `ensureDir` for new-category creation. Added FAB + create dialogs on `CategoryEntitiesPage` (existing category) and `HomePage` (new category). Entities created as `<slug>.ru.md` with `# Title\n` seed via `writeAtomic`; clobber guard via `exists` check; error paths surface snackbars, never crash. No loader/model change — the walker discovers new files on the next rescan. Tests 245 → 255 (+10); analyze clean; `npm test` 4/4; contract git-clean. |
