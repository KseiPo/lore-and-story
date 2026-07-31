---
baseline_commit: 810cfa341c3057935dde034fadb93cb437df617e
---

# Story 2.11: Create a new event / sub-entry

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to add an event or sub-entry under an entity folder,
so that a character can accumulate written content from the phone.

## Acceptance Criteria

1. **AC1 (FR25 — create a sub-entry in a group):** Given an entity detail screen (entity folder with `tree != null`), when I trigger "add sub-entry", enter a group name and an entry title, then a new `<slug>.ru.md` file seeded with `# Title\n` is written to `<entity-folder>/<group-slug>/` via `writeAtomic`. The group folder is created first via `ensureDir` if it doesn't already exist. After creation, the model rescans and the new sub-entry appears in the detail tree.
2. **AC2 (FR25 — existing group):** Given an existing group folder (e.g. `events/`), when I create a sub-entry with that group name, then `ensureDir` is a no-op and the new file is written into the existing folder. The new item appears under the correct section in the detail tree after rescan.
3. **AC3 (RU/EN awareness):** Given the project's bilingual convention, when I create a new sub-entry, then the file is created as `<slug>.ru.md`. The loader will classify it as a lone `.ru.md` (a translation candidate) — consistent with the existing convention.
4. **AC4 (open after creation):** Given the sub-entry is created, when the write succeeds, then the editor opens on the new file so the author can immediately start writing.
5. **AC5 (AD-4 / NFR1 — atomic byte-exact):** Given any create, when the write happens, then it goes through `writeAtomic`. No new writer.
6. **AC6 (AD-8 / NFR7 — total, never crash):** Given invalid input (empty title, empty group, a slug that resolves to empty, a write failure, an `ensureDir` failure), when the create is attempted, then the UI shows an error message and never crashes. A failed write does not navigate to the editor. Both `on RepoStorageException` and a generic `catch (_)` fallback are used (per Story 2.10 review fix).
7. **AC7 (AD-10 — model rebuilt):** Given a successful create, when the author returns from the editor, then `EntityDetailPage._rescan()` re-walks and the new sub-entry appears in the tree without manual refresh.
8. **AC8 (entity folder only):** Given a simple entity (no tree / `tree == null`), the create-sub-entry action is not available — the FAB is hidden. Only entity folders can hold sub-entries.
9. **AC9 (clobber guard):** Given a file with the same slug already exists (as `.ru.md`, `.md`, or `.en.md`), when the create is attempted, then an error is shown and no write occurs (per Story 2.10 expanded clobber guard).
10. **AC10 (no regression):** No loader/model change. All existing tests stay green. `flutter analyze` clean; `flutter test` green; `git status --porcelain apps/mobile/lib/lore/` **empty** (lore/ untouched).

## Tasks / Subtasks

- [x] **Task 1 — Add create-sub-entry FAB and flow on `EntityDetailPage` (AC: 1–9)**
  - [x] Add a `FloatingActionButton` to `EntityDetailPage`'s `Scaffold`, **visible only when `_entry?.tree != null`** (AC8). Use `heroTag: null` to avoid the duplicate-hero assertion when multiple pages with FABs coexist in the navigator (2.10 review fix).
  - [x] Tapping the FAB opens a dialog (`showDialog` / `AlertDialog`) with **two fields**: a group name (`TextField`) and an entry title (`TextField`). The group field should have `hintText` like `'e.g. events'` and the title field like `'e.g. Raven\'s Nest'`. Both required.
  - [x] On confirm: derive `groupSlug` and `entrySlug` from the inputs using the same `_slugify` logic from Story 2.10 (lowercase, spaces→hyphens, strip non-`[a-z0-9\-]`, strip leading/trailing hyphens). Validate: if either slug is empty after sanitization, show an error snackbar and do not proceed.
  - [x] Compute the entity folder path from the entry: `entry.id` is the loreDir-relative card path (e.g. `characters/selena/selena.md`); the entity folder is the directory portion. Use Dart's path manipulation or string ops to extract it. Then compute `groupFolder = '$entityFolder/$groupSlug'` and `filePath = '$groupFolder/$entrySlug.ru.md'` — both loreDir-relative. Convert to repo-relative via `_repoPath(...)`.
  - [x] Call `storage.ensureDir(_repoPath(groupFolder))` to create the group folder if it doesn't exist (AC1, AC2).
  - [x] **Clobber guard (AC9):** check `storage.exists` for `_repoPath(filePath)`, `_repoPath('$groupFolder/$entrySlug.md')`, and `_repoPath('$groupFolder/$entrySlug.en.md')`. If any exists, show "A sub-entry with this name already exists" snackbar, do not write.
  - [x] Write the seed: `storage.writeAtomic(_repoPath(filePath), '# $title\n')`. On success, push `EditorPage(storage: widget.storage, path: _repoPath(filePath))` (AC4). On failure, show error snackbar and do not navigate.
  - [x] Wrap the storage calls in `try { ... } on RepoStorageException { ... } catch (_) { ... }` — both clauses show a generic error snackbar (AC6, per 2.10 review fix).
  - [x] On return from the editor, the existing `_rescan()` fires (AC7, AD-10) — no new refresh logic needed.
- [x] **Task 2 — Tests (AC: 1–10)**
  - [x] **Create sub-entry in new group** (`test/app/create_sub_entry_test.dart`): seed a `FakeRepoStorage` with an entity folder (e.g. `characters/selena/selena.md` as card, an existing `events/` section with an item). Tap the FAB on the detail page, enter a group name and title, confirm. Assert `ensureDirCalls` contains the group folder path; assert `writeCalls` contains `('<entity-folder>/<group-slug>/<entry-slug>.ru.md', '# Title\n')`; assert `EditorPage` opens.
  - [x] **Create sub-entry in existing group**: same entity folder, use an existing group name (e.g. "events"). Assert `ensureDirCalls` contains the group path (ensureDir is a no-op for existing); assert write goes through.
  - [x] **FAB hidden for simple entity**: seed a simple entity (no tree/folder). Assert no `FloatingActionButton` on the detail page.
  - [x] **Error paths**: empty group → no write, error shown; empty title → no write; hyphen-only slug → no write; duplicate exists → error, no write; `writeAtomic` failure (`failWrites: true`) → error snackbar, no navigation; cancel dialog → no write.
  - [x] **Regression:** the full existing test suite stays green. Contract gate: `flutter analyze` clean; `flutter test` all passing; `git status --porcelain apps/mobile/lib/lore/` **empty**.

### Review Findings

- [x] [Review][Patch] Reserved "media" group name creates invisible sub-entry — added reserved-name guard for "media" in `entity_detail_page.dart` (group) and `home_page.dart` (category). Tests added in both test files. [entity_detail_page.dart:129, home_page.dart:275]
- [x] [Review][Defer] Cyrillic/non-ASCII group/title names always rejected by `_slugify` — `[^a-z0-9\-]` strips all non-ASCII, so pure-Cyrillic input (e.g. "События") slugifies to empty string. Pre-existing from Story 2.10; requires design decision on slug strategy (transliterate? keep?). [entity_detail_page.dart:322-329]
- [x] [Review][Defer] TextEditingController not disposed in dialog — `_showCreateSubEntryDialog` creates two controllers without `.dispose()`. Pre-existing pattern from Story 2.10 (`_showCreateEntityDialog`). Controllers become unreachable when dialog closes. [entity_detail_page.dart:338-339]
- [x] [Review][Defer] No re-entrancy guard on FAB during async storage calls — Modal dialog prevents concurrent taps during dialog phase; theoretical only during the post-dialog await chain. Pre-existing pattern from Story 2.10. [entity_detail_page.dart:115]

## Dev Notes

### What this story is — a create-sub-entry flow on the entity detail page

Story 2.10 added entity creation on `CategoryEntitiesPage` (top-level) and `HomePage` (new category). This story adds the second authoring op: creating a **sub-entry within an entity folder** — an event, a scene, a quest entry. The flow mirrors 2.10's pattern (FAB → dialog → slugify → ensureDir → clobber guard → writeAtomic → push editor), but lives on `EntityDetailPage` and targets a subfolder (group) within the entity rather than the category root.

No model/loader change: the loader already discovers any `.md` file in a sub-folder via `_buildNode`'s recursive walk. The new file appears in the tree after `_rescan()`.

### Entity folder path derivation

The `EntityDetailPage` receives `entry` (`LoreEntry`) and `loreDir`. The entry's `id` field is the **loreDir-relative** card path, e.g. `characters/selena/selena.md`. The entity folder is the directory of that path: `characters/selena/`. Extract it by stripping the filename:

```dart
// entry.id = 'characters/selena/selena.md'
final lastSlash = entry.id.lastIndexOf('/');
final entityFolder = lastSlash < 0 ? '' : entry.id.substring(0, lastSlash);
// entityFolder = 'characters/selena'
```

The group folder within the entity: `$entityFolder/$groupSlug` (loreDir-relative).
The file path: `$entityFolder/$groupSlug/$entrySlug.ru.md`.
All converted to repo-relative via `_repoPath(...)` before storage calls.

### The `_slugify` function — duplicate from 2.10 (file-private, deliberate)

Copy the same `_slugify` from `category_entities_page.dart` / `home_page.dart`:

```dart
String _slugify(String title) {
  return title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9\-]'), '')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
```

This is a file-private pure function, deliberately duplicated per the project convention (2.10 review confirmed this is fine).

### The dialog — two fields: group name + entry title

The dialog has two `TextField`s:
- **Group name** — the subfolder within the entity (e.g. `events`, `quests`). Required. Slugified for the folder name.
- **Entry title** — the name of the new sub-entry (e.g. `The Dark Forest`). Required. Slugified for the filename.

Use `Key('sub-entry-group-field')`, `Key('sub-entry-title-field')`, `Key('create-sub-entry-confirm')` for test targeting.

### Review fixes from 2.10 already baked in

- **heroTag: null** on the FAB (prevents duplicate-hero assertion during navigation transitions)
- **Expanded clobber guard** — check `.ru.md`, `.md`, and `.en.md` before writing
- **`catch (_)` fallback** after `on RepoStorageException` (AD-8 at the call site)
- **Leading/trailing hyphen stripping** in `_slugify` (rejects hyphen-only slugs)

### Files being MODIFIED (read before editing)

- **`apps/mobile/lib/app/entity_detail_page.dart`** (MODIFY) — add FAB + create-sub-entry dialog + `_createSubEntry` method + `_slugify` + `_showCreateSubEntryDialog` helper + `_SubEntryResult` class. The existing `_open`/`_openItem`/`_rescan`/build machinery is unchanged.

**Do NOT modify** (verify git-clean): `apps/mobile/lib/lore/**` (no model/loader change), `lib/lore.js`, `test/fixtures/**`, `scripts/**`.

### Architecture guardrails

- **AD-3 — all filesystem access through `RepoStorage`.** Uses `ensureDir` + `writeAtomic` + `exists` — all port methods. No `dart:io` outside the adapter. [ARCHITECTURE-SPINE.md#AD-3]
- **AD-4 / NFR1 — every write atomic and byte-exact.** Creates go through `writeAtomic`. `ensureDir` is a separate, explicit step for the group folder. [#AD-4]
- **AD-8 / NFR7 — total, never crash.** Empty slugs, duplicate names, write/ensureDir failures — all surface error messages, never throw past the UI boundary. Both specific and generic catches. [#AD-8]
- **AD-9 — model purity per-slice.** No `dart:io` in `entity_detail_page.dart`. [#AD-9]
- **AD-10 — model rebuilt, never patched.** After create + editor, `_rescan()` re-walks from disk. [#AD-10]

### Previous story intelligence

- **2.10 (done):** Established the create-entity pattern: FAB → dialog → slugify → ensureDir → clobber guard → writeAtomic → push editor → rescan. Review found and fixed: hero tag clash, hyphen-only slug, narrow catch, language-suffix-blind clobber, category-exists warning. All these fixes are **already baked into** the 2.11 spec above.
- **2.10 testing pattern:** `FakeRepoStorage` with `dirEntries` + `fileContents` seeding, `_pumpReady` + `_tapFab` helpers, assert on `writeCalls`/`ensureDirCalls`/snackbar messages/EditorPage navigation. Reuse this pattern for 2.11 tests.
- **2.9 (done):** `PairedEditorPage` has `createIfMissing` mode — not used here. New sub-entries open in plain `EditorPage` on the seed file; the `.ru.md` with no `.en.md` triggers the "needs translation" flow from Story 2.9 on the *next* open (after rescan rebuilds the model with the new item).
- **project testing-emphasis:** Cover the **business logic** — create writes the correct file, slug derivation, clobber guard, error paths. Don't over-invest in UI tests for the dialog appearance.

### Git intelligence

Baseline from HEAD (Story 2.10 + review fixes, not yet committed). Branch per story, ff-merge to main, never push, model `Co-Authored-By` trailer ([[git-story-workflow]]).

### Library / version policy

**No new dependencies.** `ensureDir`, `writeAtomic`, `exists` are already on the `RepoStorage` port. The dialog uses `showDialog`/`AlertDialog`/`TextField` — all Material, already available.

### Testing standards

- **Create sub-entry → widget tests** in `test/app/create_sub_entry_test.dart`: seed entity folder in fake, tap FAB, enter group + title, confirm; assert `ensureDirCalls` + `writeCalls` (correct paths, correct seed); assert editor navigation.
- **Error paths → widget tests**: empty group/title, hyphen-only slug, duplicate exists, write failure, cancel.
- **FAB hidden for simple entity → widget test**: seed simple entity, verify no FAB.
- **Regression → full suite** stays green.
- **Contract gate:** `git status --porcelain apps/mobile/lib/lore/` empty. No model/loader change.

### Project Structure Notes

- UI only: `entity_detail_page.dart` (FAB + create dialog for sub-entries within entity folders).
- Tests: new `create_sub_entry_test.dart`.
- No `lore/` or `storage/` change — `ensureDir` already exists from Story 2.10.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.11] — user story + ACs (FR25: create sub-entry/event in entity folder)
- [Source: ARCHITECTURE-SPINE.md#AD-3, #AD-4, #AD-8, #AD-9, #AD-10]
- [Source: apps/mobile/lib/app/entity_detail_page.dart] — the page gaining FAB + create flow
- [Source: apps/mobile/lib/lore/lore_model.dart] — LoreEntry.id (card path), LoreNode/LoreItem/group structure
- [Source: apps/mobile/lib/lore/lore_loader.dart#_buildNode] — how groups/sub-entries are discovered (unchanged)
- [Source: apps/mobile/lib/app/category_entities_page.dart#_createEntity] — the 2.10 create pattern to mirror
- [Source: _bmad-output/implementation-artifacts/2-10-create-a-new-entity.md] — previous story intelligence + review fixes

## Dev Agent Record

### Agent Model Used

claude-opus-4-6

### Debug Log References

None — clean first-pass implementation.

### Completion Notes List

- Added FAB to EntityDetailPage, visible only for entity folders (tree != null), with heroTag: null.
- Two-field dialog (group + title) mirrors the Story 2.10 create pattern.
- File-private `_slugify` duplicated per project convention (deliberate, confirmed in 2.10 review).
- Entity folder path derived from `entry.id` by stripping the card filename.
- ensureDir → clobber guard (3-suffix: .ru.md, .md, .en.md) → writeAtomic → push EditorPage → _rescan on return.
- Both `on RepoStorageException` and `catch (_)` fallback (AD-8 at the call site).
- 9 widget tests covering: new group, existing group, FAB hidden for simple entity, empty group, empty title, hyphen-only slug, duplicate exists, write failure, cancel dialog.
- Full suite: 267 tests pass, zero regressions. `flutter analyze` clean. `lore/` untouched.

### File List

- `apps/mobile/lib/app/entity_detail_page.dart` — MODIFIED (FAB + create-sub-entry flow + _slugify + dialog helpers + media guard)
- `apps/mobile/lib/app/home_page.dart` — MODIFIED (media reserved-name guard on category creation)
- `apps/mobile/test/app/create_sub_entry_test.dart` — NEW (10 widget tests)
- `apps/mobile/test/app/create_entity_test.dart` — MODIFIED (+1 reserved-name test)

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-31 | Implemented create-sub-entry FAB and flow on EntityDetailPage with 9 tests |
| 2026-07-31 | Code review: patched reserved "media" name guard (cross-cutting: entity_detail_page + home_page), 3 deferred, 9 dismissed |
