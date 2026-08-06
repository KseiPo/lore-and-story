---
baseline_commit: d81d80ed83526c98a08ec88950230672a4b659e7
---

# Story 2.17: Promote a simple entity to an entity folder

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to convert a flat card into an entity folder,
so that it can hold events and quests like a full character.

## Context

Every simple entity today (`characters/frank.md`) is a dead end — it can never grow sub-entries (events, quests) the way an entity folder (`characters/selena/selena.md` + `events/`, `quests/`) can. FR26 is the fix: an in-app action that moves `<slug>.md` to `<slug>/<slug>.md`. The loader already recognizes this exact resulting shape as an entity folder (a folder containing `<folder-name>.md` — see `lore_loader.dart`'s walk) with **zero loader changes needed**; promotion is purely a `storage/`-layer + `app/`-layer operation, re-scanned afterward like every other write.

FR26 itself calls this out as **"the only authoring op that moves a file"** — `RepoStorage` has `listDir`/`read`/`readBytes`/`writeAtomic`/`ensureDir`/`exists` today, but nothing that relocates content. This story adds exactly one new port capability: an atomic rename (`movePath`). A rename is a single filesystem operation — it never re-encodes bytes, so "preserving the card's bytes exactly" (the AC's own words) holds *by construction*, with none of `writeAtomic`'s UTF-8/BOM concerns to reason about. This mirrors Story 2.16's `readBytes` addition almost exactly in shape (port method + adapter + fake + dedicated tests) — that story is the direct template to follow here.

## Acceptance Criteria

1. **(FR26 — the promotion itself)** Given a simple entity `<slug>.md` (an entry with no content tree) shown in the category's entity list, when I choose to promote it and confirm, then the app creates the folder `<slug>/`, moves the card into it as `<slug>/<slug>.md`, and the entity list re-scans to show it as a folder (tapping it now opens the detail-tree outline, not the plain editor).
2. **(FR26/NFR1 — atomic, byte-exact by construction)** Given the move, when it runs, then it is a **single filesystem rename** — not a read-then-write-then-delete — so it can never leave two copies or a partially-written file, and the card's bytes are preserved exactly (no re-encode step exists to corrupt them).
3. **(AD-3/AD-9/NFR3 — port extension, adapter-only I/O)** Given the `RepoStorage` port, when the move capability (`movePath`) is added, then it is implemented **only** in `AllFilesRepoStorage`; no `dart:io` import appears anywhere else. The test fake (`FakeRepoStorage`) implements it too.
4. **(AD-8/NFR7 — total, original never lost)** Given a promotion that fails — the target folder/file already exists, the entity vanished before the move runs, or an I/O error — when it happens, then the app shows an error and the original `<slug>.md` is never deleted or corrupted (the rename either fully succeeds or the source is left untouched — no exception reaches the widget tree, the entity list stays usable).

**Non-goals (explicitly out of scope):** demoting a folder back to a simple entity (no such feature exists or is planned); promoting a sub-entry within an entity folder (FR26/epics.md only ever describes promoting a **top-level** simple entity); a top-level `.ru.md`/`.en.md`-suffixed entity is not special-cased — it promotes using its full filename-minus-`.md` as the slug (e.g. `frank.ru.md` → `frank.ru/frank.ru.md`), an unusual but harmless result; inventing guard logic for this narrow, currently-hypothetical case is not worth the complexity (see Dev Notes).

## Tasks / Subtasks

- [x] **Task 1: Add `movePath` to `RepoStorage` + `AllFilesRepoStorage` + `FakeRepoStorage`** (AC: 2, 3)
  - [x] 1.1 In `apps/mobile/lib/storage/repo_storage.dart`, add to the `RepoStorage` interface: `Future<void> movePath(String from, String to);` with a doc comment stating: it's a rename (not copy+delete), so content is never re-encoded; it is the **only** relocating operation in the port (FR26); **callers are responsible for checking `exists` on `to` before calling** — `movePath` does not itself re-check or refuse an existing target, mirroring `writeAtomic`'s "just do it" contract (the guard lives at the call site, matching the existing `_createEntity`/`_createSubEntry` pattern of checking `exists` before writing); throws `RepoStorageException` if `from` doesn't exist or the OS rename fails, leaving `from` untouched on failure.
  - [x] 1.2 In `apps/mobile/lib/storage/all_files_repo_storage.dart`, implement `movePath`: normalize both `from`/`to` via `_normalizeRepoPath`, guard against either being empty (the repo root) exactly like `writeAtomic`'s existing "cannot write to an empty path (the repo root)" guard, then `await File(fromOsPath).rename(toOsPath)` in a `try`/`on FileSystemException catch` translating to `RepoStorageException(e.message, from, osErrorCode: e.osError?.errorCode)`.
  - [x] 1.3 In `apps/mobile/test/fakes.dart`, add `final List<(String from, String to)> moveCalls = [];` (same record-tuple shape as the existing `writeCalls`) and implement `movePath`: `_fileContents.remove(from)` — throw `RepoStorageException('not found (fake)', from)` if `null` — else record the call and set `_fileContents[to] = content`. (Only text content moves in this story; `fileBytes`/images are untouched — promoting a card never touches its `media/` sibling folder.)
  - [x] 1.4 Tests in `apps/mobile/test/storage/all_files_repo_storage_test.dart`: `movePath` moves a real file — source gone (`exists` false), destination has the identical bytes (assert via `readBytes`, including a Cyrillic/binary-ish payload, to prove no re-encode); moving a missing source throws `RepoStorageException`; moving to a destination whose parent directory doesn't exist throws `RepoStorageException` (mirrors the existing "writeAtomic into a missing parent directory throws" test in this file — `movePath` requires the caller to `ensureDir` first, same as every other create flow in this app).

- [x] **Task 2: Add the "Promote to folder" action to `CategoryEntitiesPage`** (AC: 1)
  - [x] 2.1 In `apps/mobile/lib/app/category_entities_page.dart`'s `ListTile` builder (in `build()`), add a `trailing: IconButton(icon: Icons.create_new_folder_outlined, tooltip: 'Promote to folder', onPressed: () => _promoteEntity(e))` shown **only** when `e.tree == null` (a folder entity has no promote action — it's already one); `null` otherwise. A single `IconButton` is enough — no `PopupMenuButton` needed for one action.
  - [x] 2.2 Add a confirm dialog `_showPromoteConfirmDialog(BuildContext, String title) → Future<bool?>` (module-level function, mirroring `_showCreateEntityDialog`'s shape): `AlertDialog` with a short explanation ("`<title>` will become a folder that can hold events and quests. The card itself is unchanged — just moved."), Cancel (`pop(false)`) and a keyed **Promote** button (`Key('promote-entity-confirm')`, `pop(true)`).
  - [x] 2.3 Add `Future<void> _promoteEntity(LoreEntry entry)`: await the confirm dialog, bail on cancel/unmount. Derive the slug and target ids from `entry.id` (last `/`-segment minus its trailing `.md`, mirroring `_createSubEntry`'s existing `lastIndexOf('/')` string-splitting style — do not introduce a new path utility): `newFolderId = dirId.isEmpty ? slug : '$dirId/$slug'`, `newCardId = '$newFolderId/$slug.md'`. Convert to repo-relative paths via the existing `_repoPath` helper. Guard: if `exists(newFolderPath)` **or** `exists(newCardPath)`, show a "A folder with this name already exists." snackbar and stop (deliberately conservative — refuses rather than merging into a pre-existing folder of the same name, even a bare subcategory with unrelated content; see Dev Notes). Otherwise `ensureDir(newFolderPath)` then `movePath(cardPath, newCardPath)`, wrapped in the same `try`/`on RepoStorageException`/`catch (_)` → snackbar shape `_createEntity`/`_createSubEntry` already use. On success, `_rescan()` (no forced navigation — the promoted row's existing `onTap: () => _openEntity(e)` already routes correctly post-rescan, since `_openEntity` branches on `entry.tree != null`, which the loader now sets).

- [x] **Task 3: Tests** (AC: 1–4)
  - [x] 3.1 New file `apps/mobile/test/app/promote_entity_test.dart` (mirrors `create_entity_test.dart`'s `LoreStoryApp`-through-fakes setup, not `category_entities_page.dart` in isolation — promotion must be proven end-to-end through real navigation, matching this codebase's established pattern for authoring-op tests). Cases: tapping promote + confirming on a simple entity creates the folder and moves the card (assert the old path no longer `exists`, the new path's content is byte-identical via `read`, and `FakeRepoStorage.moveCalls` recorded the expected `(from, to)`); cancelling the confirm dialog leaves everything untouched (`moveCalls` empty, original still `exists`); a folder-entity row (`entry.tree != null`) renders **no** promote `IconButton`; promoting when the target folder already exists shows an error snackbar and `moveCalls` stays empty (guard fires before any write); after a successful promotion, tapping the now-promoted row opens `EntityDetailPage` (not `EditorPage`) — proves the re-scan + existing `_openEntity` branch work together, not just that files moved on disk.
  - [x] 3.2 Storage-layer tests covered by Task 1.4.

- [x] **Task 4: Hygiene gates** (AC: 1–4)
  - [x] 4.1 `flutter analyze` clean.
  - [x] 4.2 `flutter test` green — record the before/after pass count in Dev Agent Record.
  - [x] 4.3 Confirm no `lore/` model, loader, or JS-core/fixture changes: `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` empty (the loader already recognizes `<slug>/<slug>.md` as an entity folder card via its existing `<folder-name>.md` rule — verified by reading `lore_loader.dart`'s walk before writing this story; no loader change is needed or in scope).
  - [x] 4.4 Confirm `dart:io` still appears **only** in `all_files_repo_storage.dart` within `apps/mobile/lib/` (grep for `^import 'dart:io'` — `movePath`'s implementation must not leak it anywhere else, AD-3/AD-9/NFR3).

### Review Findings

- [x] [Review][Patch] The collision guard checks `exists(newFolderPath) || exists(newCardPath)` before `ensureDir`+`movePath` — but only the *file* (`newCardPath`) existing is actually dangerous (a silent-overwrite risk); checking the *folder* too means a single transient `movePath` failure after `ensureDir` already succeeded leaves an empty orphaned folder that then **permanently** blocks every future retry through the UI (the guard trips again forever, no recovery short of manual filesystem access) [apps/mobile/lib/app/category_entities_page.dart:144-145] — applied: guard now checks only `newCardPath`; `ensureDir` is idempotent so proceeding into an existing (possibly orphaned) folder is safe; added a regression test proving a retry after an orphaned-folder state succeeds
- [x] [Review][Patch] AC4's "vanished entity"/I/O-error failure path (`_promoteEntity`'s `catch` block) has zero test coverage — no `FakeRepoStorage` flag exists to force `movePath` to throw after `ensureDir` succeeds, unlike the established `failWrites: true` pattern both `create_entity_test.dart` and `create_sub_entry_test.dart` use to prove their equivalent error-snackbar paths (Task 3.1 explicitly says to mirror `create_entity_test.dart`'s setup) [apps/mobile/test/fakes.dart, apps/mobile/test/app/promote_entity_test.dart] — applied: added `failMove` to `FakeRepoStorage` (mirrors `failWrites`) and a widget test proving the error snackbar shows and the original card is left intact
- [x] [Review][Patch] No re-entrancy guard on the promote `IconButton` — a fast double-tap launches two concurrent `_promoteEntity` calls on the same row; the second `movePath` throws (source already gone) and surfaces a spurious "Failed to promote this entity" for an operation that in fact already succeeded [apps/mobile/lib/app/category_entities_page.dart:126] — applied: added a `_promotingIds` set guarding both the button's `onPressed` and `_promoteEntity` itself; proved with a controllable-delay test double (`_SlowMoveStorage`) since the plain fake resolves too fast to observe the in-flight window
- [x] [Review][Patch] `_promoteEntity` never checks `entry.tree == null` itself — it relies entirely on the UI hiding the trailing icon for folder entities; a future call site (refactor, programmatic call) could silently move just the card out of an existing entity folder, orphaning its events/quests/children with no error raised [apps/mobile/lib/app/category_entities_page.dart:126] — applied: added an early-return guard at the top of `_promoteEntity`
- [x] [Review][Patch] `FakeRepoStorage.movePath` doesn't verify the destination's parent directory exists first, unlike the real `AllFilesRepoStorage` (whose OS rename would throw ENOENT) — a caller that forgets to `ensureDir` first would pass in tests but fail in production [apps/mobile/test/fakes.dart] — applied: `movePath` now throws `RepoStorageException` when the destination's parent isn't a known directory, mirroring the real adapter
- [x] [Review][Defer] `movePath(from, to)` with `from == to` (identical paths) has unhandled, platform-dependent rename-onto-self behavior [apps/mobile/lib/storage/all_files_repo_storage.dart] — deferred, not reachable via this story's only call site (the two paths always differ structurally); revisit if a second `movePath` caller is ever added
- [x] [Review][Defer] The collision-guard snackbar always says "A folder with this name already exists" even when the actual collision is a stray *file* (not a folder) at that path [apps/mobile/lib/app/category_entities_page.dart:146-148] — deferred, narrow and cosmetic (a file named with no extension colliding with a promotion slug)
- [x] [Review][Defer] The confirm dialog interpolates the entity title unescaped — a title containing a double quote renders with odd nested-quote punctuation [apps/mobile/lib/app/category_entities_page.dart] — deferred, cosmetic only; `Text` is not HTML, no injection risk
- [x] [Review][Dismiss] A TOCTOU race exists between the `exists()` guard and the subsequent `ensureDir`/`movePath` calls (an external change could land in between) — not reachable in this app's single-author, confirm-gated usage model (AD-5); matches an already-accepted class of gap present in every other authoring op in this codebase (`_createEntity` has the identical exists-then-write race), never previously flagged as a blocker
- [x] [Review][Dismiss] No success feedback (snackbar) after a successful promotion — not an AC requirement; the row's visible change (the promote icon disappears, tapping the row now opens a different screen) is itself implicit confirmation
- [x] [Review][Dismiss] The `on RepoStorageException` and following `catch (_)` blocks in `_promoteEntity` are byte-for-byte identical — matches the pre-existing, already-established pattern from `_createEntity`/`_createSubEntry`; not a regression introduced by this story
- [x] [Review][Dismiss] The slug derivation strips only a trailing `.md`, not `.ru.md`/`.en.md` — explicitly called out as an accepted, documented non-goal in this story's own spec ("Non-goals" section); the Acceptance Auditor independently confirmed this is not an AC violation
- [x] [Review][Dismiss] `RepoStorageException.osErrorCode` is discarded at the call site, collapsing every failure into one generic message — matches the pre-existing established precedent used by every other authoring op in this codebase (`_createEntity`/`_createSubEntry` also collapse to a generic "Failed to..." message)

## Dev Notes

### What changes, precisely

**File to MODIFY — `apps/mobile/lib/storage/repo_storage.dart`:**
- Add `Future<void> movePath(String from, String to);` to the `RepoStorage` interface (no new import needed — both params are `String`).

**File to MODIFY — `apps/mobile/lib/storage/all_files_repo_storage.dart`:**
- Add `movePath` — the only new `dart:io` code this story introduces, and it belongs here (the one file permitted to import `dart:io`).

**File to MODIFY — `apps/mobile/lib/app/category_entities_page.dart`:**
- `build()`'s `ListTile` gains a conditional `trailing` `IconButton`.
- New: `_promoteEntity(LoreEntry entry)`, `_showPromoteConfirmDialog(BuildContext, String title)`.
- Current relevant state (read before editing): `_entries` (seeded from `widget.category.entries`, rebuilt by `_rescan()`), `_repoPath(id)` (loreDir-relative → repo-relative), `_createEntity()` (the closest existing precedent — guard-check-`exists`, write, navigate, `_rescan()`), `_slugify()` (title → filename slug — **not** reused here; promotion derives its slug from the *existing* file's id, not a fresh title input).

**File to MODIFY — `apps/mobile/test/fakes.dart`:**
- `FakeRepoStorage` gains `moveCalls` + `movePath`.

**Not touched in this story:** `apps/mobile/lib/lore/**` (the loader already handles the resulting shape — see Task 4.3's verification note), `lib/lore.js`, `test/fixtures/lore-model/**`, `entity_detail_page.dart` (a promoted entity is opened by the *existing* `_openEntity` branch in `category_entities_page.dart`, unchanged), `apps/mobile/lib/app/editor_page.dart` (no involvement — promotion never opens an editor).

### Architecture constraints

- **AD-3 / NFR3** (all filesystem access through `RepoStorage`): `movePath` is a port method like the other five; the UI layer calls only the port, never `dart:io`.
- **AD-9** (I/O isolated to adapter files): `movePath`'s *implementation* lives only in `all_files_repo_storage.dart`; the port declaration itself stays pure (no new import needed there at all — simpler than Story 2.16's `readBytes`, which needed `dart:typed_data` for `Uint8List`).
- **AD-4** (every write is atomic and byte-exact): a rename **is** the atomic primitive here — simpler than `writeAtomic`'s temp-file-then-rename dance, because there's no *content* to write, only a directory entry to relocate. This is *why* FR26 calls promotion "the only authoring op that moves a file" rather than "the only op needing a special writer."
- **AD-8 / NFR7** (total, never crash, original never lost): the risk surface is entirely at the UI call site (`_promoteEntity`) — the port method itself either fully succeeds or leaves `from` untouched (a real OS rename has no partial-content failure mode the way a multi-step write does). The call site's job is: guard against an existing target *before* touching storage, and catch/report any failure without leaving the screen stranded — exactly the shape `_createEntity`/`_createSubEntry` already established.
- **AD-10** (model rebuilt, not patched): after `movePath` succeeds, `_rescan()` re-walks and rebuilds `_entries` from disk — no in-memory patching of the promoted entry's `tree` field. This is also *why* no navigation is forced after promoting: the same row, same `onTap`, now correctly routes to `EntityDetailPage` once the rescanned `LoreEntry.tree` is non-null — no new UI branching needed.
- **A known, accepted partial-state edge case (not new, not this story's to fix):** if `ensureDir(newFolder)` succeeds but the subsequent `movePath` then fails (e.g. a permission error), an empty `newFolder` is left behind alongside the still-intact original `<slug>.md`. This is harmless (no data loss, the loader treats an index-less folder as a plain subcategory) and is the **exact same accepted tradeoff** `entity_detail_page.dart`'s `_createSubEntry` already has today (its `ensureDir` isn't rolled back if the following `writeAtomic` fails either). Do not add new rollback machinery for this story — it would be scope creep inconsistent with the codebase's existing risk tolerance here.

### Previous story intelligence

**Immediate previous story (2.16, done)** is the direct template for Task 1 — it added `readBytes` to this exact port in this exact shape (interface + doc comment → adapter implementation mirroring an existing method's structure → fake with a call-tracking list → dedicated adapter tests). `movePath` is simpler than `readBytes` was: no `dart:typed_data` import needed on the pure port side, and the fake's implementation is a plain map move rather than needing a second byte-content map. 2.16's own code review also surfaced a durable lesson worth carrying forward: **don't let a test's fixture/story-file summary overclaim what the code actually guards** (that story's `_maxImageBytes` doc comment initially overclaimed OOM protection it didn't provide) — when writing `movePath`'s doc comment, state precisely what it does and doesn't guarantee (a rename either succeeds or leaves the source untouched; it does **not** itself refuse an existing target — the caller does).

**Functional precedents for the UI flow:**
- **Story 2.10's `_createEntity`** (`category_entities_page.dart`, the exact file this story also modifies): the established shape — check `exists` before writing, `writeAtomic`, catch `RepoStorageException`/generic `catch (_)` into an identical snackbar message pattern, navigate, `_rescan()`. `_promoteEntity` mirrors this shape closely, swapping "write a new file" for "ensureDir + movePath" and dropping the navigate step (promotion doesn't open an editor).
- **Story 2.11's `_createSubEntry`** (`entity_detail_page.dart`): the `ensureDir`-before-write pattern and its accepted non-rollback-on-partial-failure precedent (see Architecture constraints above) — read that method in full before implementing `_promoteEntity`, since the two are structurally the closest analog in the codebase.
- **Cross-model review** ([[cross-model-code-review]]): expect probing on the "what if the target already exists" and "what if the move fails halfway" cases — both are addressed above; know the reasoning so you're not caught flat-footed re-deriving it during review.

### Testing standards

- Prioritize the **atomicity/never-loses-the-original** properties (AC2/AC4) and the **end-to-end wiring** (does tapping promote actually change what `_openEntity` routes to afterward) over incidental UI presence, per [[testing-emphasis]] — this mirrors Story 2.16's own testing priority (degrade-safety over happy-path).
- Reuse `FakeRepoStorage` (extended with `moveCalls`) — no new fake type needed, consistent with every prior storage-touching story in this epic.
- New test file (`promote_entity_test.dart`) rather than folding into `create_entity_test.dart`: promotion is a distinct authoring op (moves, doesn't create) with its own fixture shape; a dedicated file keeps both readable, matching how `browse_test.dart`/`create_entity_test.dart` are already split by concern rather than by source file.

### Project Structure Notes

- New test file: `apps/mobile/test/app/promote_entity_test.dart`.
- No new dependencies — `File.rename` is `dart:io` SDK, already imported in `all_files_repo_storage.dart`.
- No architecture changes — this is a UI + one port-capability story, same shape as 2.16.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.17, and FR26's definition (Promotion phase section) + FR24/FR25 for the sibling create-ops this story's UI flow mirrors]
- [Source: _bmad-output/implementation-artifacts/2-16-render-local-repo-images-in-the-preview.md] — the direct template for Task 1's port-extension shape and its own review lesson about doc-comment accuracy
- [Source: apps/mobile/lib/storage/repo_storage.dart] — the port `movePath` is added to; `writeAtomic`'s empty-path guard and byte-exactness doc comments are the pattern to mirror
- [Source: apps/mobile/lib/storage/all_files_repo_storage.dart] — `writeAtomic`'s structure (empty-path guard, `FileSystemException` → `RepoStorageException`) is `movePath`'s direct template
- [Source: apps/mobile/lib/app/category_entities_page.dart] — full file: `_createEntity`, `_repoPath`, `_rescan`, `_slugify`, the `ListTile` builder this story extends
- [Source: apps/mobile/lib/app/entity_detail_page.dart] — `_createSubEntry`'s `ensureDir`-before-write pattern and its accepted non-rollback precedent
- [Source: apps/mobile/lib/lore/lore_loader.dart] — walk logic confirming `<slug>/<slug>.md` is already recognized as an entity-folder card via the existing `<folder-name>.md` precedence rule (`_walkCategory`'s `['index.md', '${item.name}.md']` check) — read in full before this story to confirm no loader change is needed
- [Source: apps/mobile/test/app/create_entity_test.dart] — the `LoreStoryApp`-through-fakes test setup pattern to mirror in the new `promote_entity_test.dart`
- [Source: apps/mobile/test/fakes.dart] — `FakeRepoStorage`, extended with `moveCalls`/`movePath`
- [Source: ARCHITECTURE.md §3.2] — the entity-folder recognition rule (`<folder-name>.md`/`index.md`) this story's resulting file layout satisfies without any loader change
- [Source: _bmad-output/planning-artifacts/epics.md — FR26, NFR1, NFR3, NFR7]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5

### Debug Log References

- Baseline before work (branch tip `d81d80e`, main after Story 2.16's merge): `flutter test` 323 passing, `flutter analyze` clean.
- Task 1 (`movePath`) implemented and tested cleanly on the first pass — 29/29 storage tests green, no surprises. `File.rename()` mirrored `writeAtomic`'s existing empty-path guard and `FileSystemException` translation exactly as planned.
- Two real issues surfaced only when running the **full** suite (not just the new/touched files), both fixed:
  1. **Compile break**: `markdown_preview_test.dart`'s `_SyncThrowingStorage` (a hand-written `RepoStorage` test double added in Story 2.16's review-fix pass) implements every port method individually — adding `movePath` to the interface broke it. Fixed by adding a trivial no-op override. This is the exact "grep for the enum name" lesson Story 2.15 already flagged in a different form: growing a shared interface requires a full-suite compile check, not just the files a story's own diff touches.
  2. **Real regression in `FakeRepoStorage`**: my first cut of `movePath`/`ensureDir` mutated `_dirEntries`' `List<RepoEntry>` values in place (`.add()`/`.removeWhere()`), which crashes if the seeded list is an immutable `const [...]` literal (common in most test fixtures) — so I first "fixed" that by deep-copying every seeded list into a fresh mutable `List` in the constructor. That broke 4 **existing, unrelated** tests (`widget_test.dart`'s two "re-scans from disk" tests, `browse_test.dart`'s conflict-count test, `entity_detail_page_test.dart`'s "deleted between scans" test) — all of which deliberately hold their own reference to a seeded list and `.add()`/mutate it directly between two rescans to simulate an external filesystem change, relying on that list being the *same object* the fake reads from. Root-caused by reading those tests' own comments ("A mutable listing lets the test change the repo between scans") before assuming a fix. Final approach: keep the constructor's shallow `Map.of(dirEntries)` (preserves list-value identity), and make `ensureDir`/`movePath` **copy-on-write** — replace a touched key's list with a new one via `[...existing, newEntry]` rather than mutating in place. This fixes the immutable-list crash without touching any list identity the fake itself doesn't own.
- `flutter analyze` → **No issues found** (full project).
- `flutter test` → **331 passing** (323 → +8: 3 `movePath` storage tests, 5 `promote_entity_test.dart` widget tests — one per Task 3.1 case). Verified via full-suite run, not just the touched files, after both fixes above.
- Contract gate: `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` empty — confirmed the loader needed zero changes, exactly as predicted during story creation (the walker already recognizes `<slug>/<slug>.md` via its existing `<folder-name>.md` precedence rule).
- `dart:io` isolation: `grep -rn "^import 'dart:io'" apps/mobile/lib/` returns exactly one hit, `all_files_repo_storage.dart`.

### Completion Notes List

- Added `Future<void> movePath(String from, String to)` to the `RepoStorage` port, implemented in `AllFilesRepoStorage` via a single `File.rename()` (mirrors `writeAtomic`'s empty-path guard; no content re-encode, so byte-exactness holds by construction) and in `FakeRepoStorage` (records `moveCalls`, moves the entry in `_fileContents`, and keeps `listDir` results consistent via copy-on-write updates to `_dirEntries` — see Debug Log for why copy-on-write, not in-place mutation).
- Added the "Promote to folder" action to `CategoryEntitiesPage`: a trailing `IconButton` shown only for simple entities (`entry.tree == null`), a confirm dialog, and `_promoteEntity` — guards against an existing target (checks `exists` on both the new folder and new card path before writing, mirroring `_createEntity`'s established pattern), then `ensureDir` + `movePath`, then `_rescan()`. No forced navigation after promoting — the same row's existing `onTap`/`_openEntity` branch already routes correctly once the rescanned model reports a non-null `tree`.
- Confirmed (by reading `lore_loader.dart`'s walk before implementing) that no loader change is needed: a folder containing `<folder-name>.md` is already recognized as an entity folder by the existing precedence rule.
- `FakeRepoStorage` gained a `_addSibling` helper shared by `ensureDir`/`movePath` to keep `listDir` self-consistent with structural ops, without breaking existing tests that hold a live reference to a seeded list (see Debug Log for the regression this required fixing).
- No `lore/` model, loader, or JS-core/fixture changes; no new dependencies (`File.rename` is `dart:io` SDK, already imported in the one file allowed to use it); `flutter analyze` clean; `flutter test` 323 → 331 (+8).

### File List

- MODIFIED: apps/mobile/lib/storage/repo_storage.dart
- MODIFIED: apps/mobile/lib/storage/all_files_repo_storage.dart
- MODIFIED: apps/mobile/lib/app/category_entities_page.dart
- MODIFIED: apps/mobile/test/fakes.dart
- MODIFIED: apps/mobile/test/storage/all_files_repo_storage_test.dart
- MODIFIED: apps/mobile/test/app/markdown_preview_test.dart
- NEW: apps/mobile/test/app/promote_entity_test.dart
- MODIFIED: _bmad-output/implementation-artifacts/sprint-status.yaml
- MODIFIED: _bmad-output/implementation-artifacts/deferred-work.md

## Change Log

- 2026-08-06: Addressed code review findings — 5 patches applied. **High — collision guard could permanently brick promotion**: it refused when either the target *folder* or *card* existed; only the card existing is actually dangerous, and checking the folder too meant one transient `movePath` failure after `ensureDir` succeeded left an orphaned empty folder that then blocked every future retry forever. Guard now checks only the card path. **High — AC4's failure path was untested**: added `failMove` to `FakeRepoStorage` (mirrors `failWrites`) and a widget test proving the error snackbar and original-card-intact behavior. **Medium — no re-entrancy guard**: added a `_promotingIds` set disabling the button while a promotion is in flight, proven with a controllable-delay test double (`_SlowMoveStorage`) since the plain fake resolves too fast to observe the race window. **Medium — no defensive `entry.tree == null` check inside `_promoteEntity` itself**: added. **Medium — `FakeRepoStorage.movePath` didn't verify the destination parent exists**: added, mirroring the real adapter's ENOENT behavior. 3 items deferred (same-path rename, a cosmetic collision-message wording gap, unescaped title interpolation); 5 dismissed (pre-existing patterns matched from `_createEntity`/`_createSubEntry`, an out-of-scope non-goal, or not reachable in this app's usage model). `flutter test` 331 → 334 (+3); `flutter analyze` clean; contract gate clean.
- 2026-08-05: Implemented Story 2.17 — an in-app "Promote to folder" action converts a simple entity (`<slug>.md`) into an entity folder (`<slug>/<slug>.md`), so it can hold sub-entries. Added `RepoStorage.movePath` (port + `AllFilesRepoStorage` rename-based adapter + test fake), wired a confirm-guarded promote flow into `CategoryEntitiesPage`. No loader change needed — the existing entity-folder recognition rule already covers the result. Along the way, hardened `FakeRepoStorage` to keep `listDir` consistent after `ensureDir`/`movePath` (copy-on-write, preserving existing tests' reliance on shared list references). No new dependencies. `flutter analyze` clean; `flutter test` 323 → 331 (+8).
