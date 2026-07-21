---
baseline_commit: fcf34a3
---

# Story 1.4: Open and save one file in a bare editor

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want to open a file, edit its text, and save it,
so that I can make a real edit from my phone end-to-end.

## Acceptance Criteria

1. **AC1 (FR7 — raw editor):** Given a resolved `loreDir`, when I pick a file, then its raw markdown loads into an editable text field with no markup hidden (no WYSIWYG, no markup-hiding — the raw buffer is the content).
2. **AC2 (FR11 — explicit save + save-on-background):** Given I have edited the buffer, when I tap save, then the file is written via the Story 1.2 atomic writer (`RepoStorage.writeAtomic`), the dirty indicator clears, and backgrounding the app (going to a paused lifecycle state) also saves if the buffer is dirty.
3. **AC3 (dirty indicator):** Given the buffer differs from the loaded content, when I look at the editor, then a dirty indicator is visible; it clears immediately after a successful save and reappears on the next edit.
4. **AC4 (no autosave-per-keystroke):** Given I am typing, when each keystroke lands, then no write happens — only explicit save (AC2) or backgrounding (AC2) triggers a write.
5. **AC5 (pick within `loreDir`, end-to-end thesis proven):** Given the ready view, when I choose to open a file, then I browse starting at the resolved `loreDir` (not the whole shared-storage tree) and picking any file opens it in the editor; this closes Epic 1's full loop (grant → pick → edit → atomic save).
6. **AC6 (scaffold hygiene):** Given a clean checkout, `flutter analyze` is clean and `flutter test` passes including new editor/picker tests.

## Tasks / Subtasks

- [x] **Task 1 — A generic in-repo file browser scoped to a start path (AC: 1, 5)**
  - [x] `app/lore_file_picker_page.dart`: drill-down browser over the injected `RepoStorage`, rooted at a repo-relative `startPath` (the resolved `loreDir`) — distinct from `RootPickerPage` (device-root picking), doc-commented as such.
  - [x] Lists both files and folders (dirs sorted first); tapping a folder descends, tapping a file pops with its repo-relative path.
  - [x] Missing/empty `loreDir` → "No files found." state; `listDir`'s existing degrade-to-`[]` contract makes this never throw.
  - [x] Explicitly scoped as a flat drill-down, not Epic 2's entity-tree browser — commented in the file header.
- [x] **Task 2 — Bare editor screen (AC: 1, 2, 3, 4)**
  - [x] `app/editor_page.dart`: `storage.read(path)` loads raw text verbatim into a multi-line `TextField` (monospace, no rendering) — FR7.
  - [x] Dirty tracked via a `TextEditingController` listener comparing current text to the originally-loaded text; a dot indicator in the `AppBar` title shows/hides with it (AC3).
  - [x] Explicit save (`AppBar` save icon, enabled only when dirty) calls `writeAtomic` then clears dirty; `onChanged`/the listener never writes (AC4).
  - [x] Save-on-background via `WidgetsBindingObserver.didChangeAppLifecycleState(AppLifecycleState.paused)` — fires the same guarded `_save()` path if dirty. A `_saving` flag prevents an explicit save and a background save from overlapping (the review-history-informed race guard called out in Dev Notes).
  - [x] A read failure (`RepoStorageException`) shows an error state with the message; never crashes, never opens an empty buffer over a real failure.
- [x] **Task 3 — Wire the ready view to open the picker → editor (AC: 5)**
  - [x] `_ReadyView` gained an "Open a file" button; `_openFile` builds `storage` from `_rootPath`, pushes `LoreFilePickerPage(startPath: _loreDir)`, then on a selected path pushes `EditorPage` with that same `storage` instance. *Correction (code review): the Dev Notes asked that the instance built in `_refresh` be threaded through; in fact `_refresh` never stores it, so `_openFile`/`_openEntry` each construct a fresh one via `storageFactory`. Harmless — the adapter is stateless and holds only a root string — but the earlier claim that no second adapter was built was inaccurate.*
- [x] **Task 4 — Tests (AC: 1, 2, 3, 4, 6)**
  - [x] `test/app/editor_page_test.dart` (7 tests): raw-content load, dirty-indicator on/off, no-write-on-typing, save writes+clears-dirty, save-on-background-while-dirty, no-save-on-background-while-clean, read-failure error state.
  - [x] `test/app/lore_file_picker_page_test.dart` (4 tests): lists files+folders, descends into a folder, file tap pops the repo-relative path, missing `loreDir` shows the empty state.
  - [x] Extended `test/fakes.dart`'s `FakeRepoStorage` (per Dev Notes guidance, not a new fake): multi-path `dirEntries`, `fileContents` seeding, and a `writeCalls` record log so `writeAtomic` calls are assertable. `read` now throws `RepoStorageException` for an unseeded path (previously always returned `''`) — verified this doesn't regress the existing ready-view test, since `resolveProjectConfig`'s catch-all (from the Story 1.3 review) already falls back to defaults on any read failure.
  - [x] `flutter analyze` clean; `flutter test` green (65 passing).
- [x] **Task 5 — Post-implementation fix: hidden folders + real navigation (user-reported, AC1, AC5)**
  - [x] **Bug found via real usage:** the ready view's "Top-level entries" list (added in Story 1.1 to demonstrate the seam) was never interactive — no `onTap` at all — so it looked like browsing but did nothing. Separately, "Open a file" started at `_loreDir`, which does not exist when the user points the repo root **directly at their lore content folder** (a reasonable choice) rather than at an outer project folder containing a `lore/` subfolder — so the picker showed nothing and the user could not open any file.
  - [x] Added a browse filter hiding Syncthing's own folders (`.stfolder`, `.stversions`, ...), applied in `LoreFilePickerPage`, `RootPickerPage`, and the ready view's top-level list. *(Initially added to `storage/repo_storage.dart` as an all-dot-prefix predicate; the code review moved it to `app/browse_filter.dart` and narrowed it — see Review Findings.)*
  - [x] Made the ready view's top-level entries genuinely navigable: tapping a folder pushes `LoreFilePickerPage` rooted at that folder (recursive descent + file selection, already supported); tapping a file opens it directly in `EditorPage`.
  - [x] `_openFile` ("Open a file" button) now checks `storage.exists(_loreDir)` and falls back to the true repo root (`''`) when it doesn't exist, instead of showing an empty picker.
  - [x] Tests: hidden-folder filtering at the top level and at every picker depth; tapping a top-level folder navigates into the picker; tapping a top-level file opens the editor; the exact reported scenario (`loreDir` absent under the chosen root) falls back to root and lets the user reach real content.
- [x] **Task 6 — Remove the "Run atomic round-trip" debug feature (user-requested)**
  - [x] Deleted `lib/storage/round_trip_spike.dart` and `test/storage/round_trip_spike_test.dart`; removed the barrel export, the `_runRoundTripSpike`/`_showSpikeResult` methods, the `onRunSpike` wiring, and the button. The spike was a Story 1.2 debug trigger whose purpose (proving the safe filesystem round-trip through Syncthing) was fulfilled once the on-device S1 check passed.
  - [x] **Note for the record:** the spike carried the codebase's only U+FFFD write-back guard (added by Story 1.2's own code review to stop malformed files being corrupted). Deleting it silently removed that protection, and the editor's save path never had one. Caught by all three layers of this story's code review and re-established in `EditorPage` — see Review Findings.
  - [x] `flutter analyze` clean; `flutter test` green.

### Review Findings

**Data-loss class (all converged across layers):**

- [x] [Review][Patch] **Malformed files are silently corrupted on save** — `read` decodes invalid UTF-8 best-effort to U+FFFD, and `_save` writes that lossy buffer back byte-exactly over the original. The only guard in the codebase was in `round_trip_spike.dart` (added by Story 1.2's own review) and was destroyed with the spike deletion; the write path moved to the editor, the guard did not move with it. Block saving a buffer that loaded with replacement chars. [apps/mobile/lib/app/editor_page.dart:87]
- [x] [Review][Patch] **Dirty flag force-cleared instead of recomputed after save** — `_save` captures `text` before the await then unconditionally sets `_original = text; _dirty = false`. Keystrokes typed during a real (non-instant) write are marked clean, the save button disables, and the background save early-returns on `!_dirty` — newest edits never reach disk. Recompute `_dirty = _controller.text != _original`. [apps/mobile/lib/app/editor_page.dart:92]
- [x] [Review][Patch] **`_saving` guard drops the deferred save rather than deferring it** — backgrounding while an explicit save is in flight hits the guard and simply returns; the pause-save never happens. A correct guard must re-run after the in-flight write (pending-save flag). The story doc wrongly presents this flag as a proven race fix. [apps/mobile/lib/app/editor_page.dart:83]
- [x] [Review][Patch] **Back with unsaved edits discards them silently** — no `PopScope`/`WillPopScope`; `dispose` drops the controller without saving. Back is the most common way to leave an editor on Android, and the story's own Dev Notes demand the edit never be silently lost. Save-or-confirm on pop. [apps/mobile/lib/app/editor_page.dart:119]

**Correctness / robustness:**

- [x] [Review][Patch] **Editor load/save catch only `RepoStorageException`** — any other throwable (Error subtypes, untranslated platform exceptions) escapes as an unhandled async error, leaving the page stuck on a spinner or the failure invisible. `ProjectConfig` was hardened to catch-alls for exactly this reason; the editor was not. [apps/mobile/lib/app/editor_page.dart:65, :94]
- [x] [Review][Patch] **`_openFile` uses `BuildContext` across an async gap with no `mounted` check** — `await storage.exists(_loreDir)` then `Navigator.of(context)` inside `_openFileFrom`. Every other await site in this file guards; the new method dropped the pattern, and `analyze` misses it because the context use is in a different method. [apps/mobile/lib/app/home_page.dart:145]
- [x] [Review][Patch] **`media/` is no longer skipped** — the deleted `findFirstMatching` enforced `name != 'media'`, documented as the Story 2.1b walk contract and reaffirmed in ARCHITECTURE.md ("`media/` folders are skipped by the walker"). The picker now lists `media/`, so a user can open a binary, lossily decode it, and destroy it on save. Second consistency casualty of the deletion. [apps/mobile/lib/storage/repo_storage.dart:112]
- [x] [Review][Patch] **Browse filter was misplaced (partially actioned per user decision)** — the helper planted browsing-UI policy in the pure port file whose own doc says the port is the storage seam; **moved to `app/browse_filter.dart`** where all consumers live. The review also proposed narrowing it from all-dot-prefix to a syncer/VCS/app-temp list; it was briefly narrowed, then **KseiPo chose to keep hiding all dot-files** ("simpler like this") — one uniform rule instead of a maintained special-case list. Accepted consequences, documented in the filter: a dot-prefixed folder can't be chosen as a repo root, and legitimate dot-files aren't editable in-app. `media/` skipping is retained regardless. [apps/mobile/lib/app/browse_filter.dart]
- [x] [Review][Patch] **System Back exits the picker instead of going up a level** — `_relPath` is mutated in place with no route push and no `PopScope`, so Back from four levels deep dumps the user to the home page and loses their position. [apps/mobile/lib/app/lore_file_picker_page.dart:69]

**Tests & docs:**

- [x] [Review][Patch] **Test gaps on the branchiest new code** — `_up()` is entirely untested (including its `i == -1 → startPath` fallback), and no test picks a file *from the picker* and asserts the editor opens, so AC5's actual loop and `_openFileFrom`'s post-pop push are unverified. Also missing: save-failure snackbar, and the AC3 "dirty reappears on the next edit" clause. [apps/mobile/test/app/lore_file_picker_page_test.dart]
- [x] [Review][Patch] **Dirty indicator has no `Key`/semantics** — a bare 10px `Icons.circle`, invisible to screen readers, and the tests bind to icon identity, contrary to the story's own testing standard asking for a `Key` or semantic label. [apps/mobile/lib/app/editor_page.dart:127]
- [x] [Review][Patch] **`FakeRepoStorage` silently ignores `dirEntries['']`** — `listDir` returns `_entries` for the root and only consults `dirEntries` otherwise, so seeding the root the natural way yields an empty listing with no error. Now a real trap, since `startPath: ''` became a production branch. [apps/mobile/test/fakes.dart]
- [x] [Review][Patch] **Story documentation is materially inaccurate** — (a) claims **70 passing**, actual is **63** (doc updated before the spike removal, never corrected); (b) File List lists `round_trip_spike.dart` as *Modified* when it is **deleted**, and Task 5 narrates a refactor of a file that no longer exists; (c) the removal of a delivered, reviewed Story 1.2 deliverable appears in **no** Change Log row, Completion Note, or retirement note against Story 1.2 (still `done` in sprint-status); (d) Task 3 claims a single `RepoStorage` instance is threaded through, but `_openFile`/`_openEntry` each rebuild it via `storageFactory`. [_bmad-output/implementation-artifacts/1-4-open-and-save-one-file-in-a-bare-editor.md]

**Deferred:**

- [x] [Review][Defer] **Editor never re-checks the file before overwriting** — open a file, background the app while Syncthing pulls a desktop edit, return and save: the remote edit is atomically obliterated. Deferred because a refuse-on-mismatch guard without the Epic 2 conflict UX (FR17 / Story 2.4) creates an unresolvable blocked save with no recovery path; single-author v0.1 makes the window narrow. Revisit *with* the conflict UI. [apps/mobile/lib/app/editor_page.dart:87]
- [x] [Review][Defer] **`*.sync-conflict-*` files are unfiltered and freely editable** — deliberately not hidden: FR17 requires conflict copies be *surfaced with a badge*, never hidden. The badge UI is Epic 2 / Story 2.4; hiding them now would contradict the requirement. [apps/mobile/lib/storage/repo_storage.dart:112]
- [x] [Review][Defer] **`_openEntry` doesn't `exists`-check a folder that vanished since listing** — yields an empty picker with the Up button suppressed; not a crash, and the port doc's `exists` disambiguation is already applied in `_openFile`. [apps/mobile/lib/app/home_page.dart:152]
- [x] [Review][Defer] **A `loreDir` with a trailing slash breaks `_atStart`** — `'lore/'` never equals `'lore'`, showing a phantom extra Up level. `ProjectConfig.parse` doesn't strip trailing slashes; obscure. [apps/mobile/lib/app/lore_file_picker_page.dart:81]
- [x] [Review][Defer] **A regular *file* named exactly `loreDir` passes the `exists` check** — picker opens on a file path, lists nothing, hides Up. Needs an `isDirectory` capability on the port to fix properly. [apps/mobile/lib/app/home_page.dart:145]

## Dev Notes

### What this story is (the payoff of Epic 1)

This is the last Epic 1 story and the one that makes the product thesis real for
the user: **grant → pick a file inside `loreDir` → edit raw markdown → atomic
save**, with a dirty indicator and save-on-background. Everything built in 1.1–1.3
(the `RepoStorage` seam, the byte-exact atomic writer, config resolution) comes
together here as an actual editing action. There is still no entity model,
highlighting, RU/EN pairing, or conflict-badge UI — all of that is Epic 2. Keep
the picker and editor **bare**, matching FR7's explicit framing (raw text, no
markup hidden, no WYSIWYG) — resist the urge to add polish beyond the ACs.

### Files being MODIFIED (read before editing)

- **`apps/mobile/lib/app/home_page.dart`** — `_ReadyView` currently shows root
  path, lore folder, the top-level entry list, "Run atomic round-trip", and
  "Change folder". **Add** an "Open a file" action that pushes the new picker with
  the **already-built `storage` instance** (constructed from `_rootPath` inside
  `_refresh`) and the resolved `_loreDir`. Do not rebuild a second `RepoStorage`
  for this — thread the existing one through, the same way `_runRoundTripSpike`
  does. **Preserve** everything already there (epoch guard, vanished-root check,
  round-trip spike, config resolution) — this story only adds a new
  action/navigation, it does not change `_refresh`'s logic.
- **`apps/mobile/lib/app/root_picker_page.dart`** — read this for the navigation
  pattern (BFS-free, simple current-path + up/down, `_relPath` state,
  `storage.listDir(_relPath)`) to reuse *the pattern*, not the class. `RootPickerPage`
  is scoped to `kPrimaryExternalStorageRoot` and returns an absolute path for
  *root selection*; `LoreFilePickerPage` is scoped to the resolved `loreDir` (a
  repo-relative path already inside the granted repo) and returns a repo-relative
  **file** path for *file selection*. Keep them separate types.

### Architecture guardrails

- **FR7 — raw editor, never WYSIWYG.** The buffer is the content being proofread;
  no markdown rendering, no syntax hiding in this story (highlighting/preview are
  Epic 2, FR9/FR9a/FR10). [prd.md#FR7]
- **FR11 — explicit save + save-on-background, no autosave-per-keystroke.**
  Matches the epic's own AC wording exactly. [prd.md#FR11; epics.md Story 1.4]
- **AD-4 — every write goes through `RepoStorage.writeAtomic`** (Story 1.2's
  byte-exact, atomic, temp+rename writer). Never call `dart:io` or bypass the
  port from this story's UI. [ARCHITECTURE-SPINE.md#AD-4]
- **AD-10 (preview of the boundary Epic 2 formalizes) — "the editor owns the
  in-memory buffer of the one open file."** This story is the first place that
  boundary exists in code: `EditorPage` owns its `TextEditingController`'s buffer;
  it does not attempt to update any shared model (there isn't one yet — Epic 2
  introduces the loader). Don't wire this editor into any cache of "the current
  file's content" outside the page itself. [ARCHITECTURE-SPINE.md#AD-10]
- **AD-9 / AD-12 — seam and slice boundaries hold.** `LoreFilePickerPage` and
  `EditorPage` live in `app/`, depend only on the injected `RepoStorage` port
  (never `dart:io`, never the concrete adapter) — same pattern as `HomePage`/
  `RootPickerPage`. [ARCHITECTURE-SPINE.md#AD-9, #AD-12]
- **AD-8 — total, never-throw UI.** A read failure (file deleted between listing
  and opening, permission revoked) shows an error state, never crashes.
  [ARCHITECTURE-SPINE.md#AD-8]

### Save-on-background is best-effort (know the boundary, don't over-build)

Flutter's `AppLifecycleState.paused` callback is not guaranteed to complete an
in-flight `Future` before Android reclaims the process — there is no durable
"finish this write before you die" guarantee without a foreground service or
WorkManager, which is out of scope for a v0.1 bare editor. This is an accepted
risk exactly like Story 1.2's on-device check being the only real proof of the
atomic write: the **atomic** part of `writeAtomic` still protects against a
*partial* file even if the process dies mid-write (worst case: the write simply
doesn't happen and the old content is unchanged on disk — never a corrupted
file). Do not add retry queues, WorkManager, or a foreground service here; that
would be scope creep beyond FR11's explicit ask. Note this boundary in code
comments so a future story doesn't assume more durability than exists.

### Previous story intelligence (Stories 1.1–1.3 — all done)

- **`RepoStorage.read`** (1.2) is best-effort UTF-8 (never throws on malformed
  content) but **throws `RepoStorageException` on a missing file** — handle that
  in the editor's load path (Task 2's "handle a read failure gracefully").
- **`RepoStorage.writeAtomic`** (1.2, hardened in its review) is byte-exact,
  atomic, and per-target-scoped (no cross-file interference); it throws
  `RepoStorageException` on failure — surface that to the user rather than
  silently losing the edit.
- **`_loreDir`** (1.3) is available in `_HomePageState` — pass it straight into
  the new picker as the start path; it is **not** cached beyond the current
  `_refresh` cycle, so read it from state at navigation time, not a captured
  closure from an earlier build.
- **Cross-model code review caught a real, non-cosmetic bug in every one of the
  last three stories** (data-loss in the round-trip spike, a byte-exactness
  violation, and an unenforced "never throws" claim). Expect the same rigor here
  — the save-on-background path and the picker's "file vs folder" tap handling
  are the likeliest places for a subtle bug (e.g. double-save races if backgrounding
  fires while an explicit save is still in flight — consider guarding with an
  in-flight-save flag).
- Toolchain: `flutter analyze` + `flutter test`; `kotlin.incremental=false` already
  set for the Windows Android build.

### Git intelligence

Recent commits: `fcf34a3` "Resolve project configuration (Story 1.3)", `d465b88`
"Prove safe atomic byte-exact write path (Story 1.2)", `ade0c11` "Scaffold mobile
app and RepoStorage seam (Story 1.1)". This story is the fourth and final piece of
Epic 1, built directly on all three.

### Library / version policy

No new dependencies. Plain Flutter `TextField`/`TextEditingController`,
`WidgetsBindingObserver` (already used in `HomePage`), and the existing
`RepoStorage` port cover everything needed.

### Testing standards

- Follow the existing test patterns: `FakeRepoStorage`/`FakeStoragePermission` in
  `test/fakes.dart` for widget tests; real `AllFilesRepoStorage` + `Directory.systemTemp`
  for anything needing genuine file I/O (probably not required here since the
  editor/picker only need a `RepoStorage`, and the fake suffices for widget-level
  assertions of "was `writeAtomic` called with X").
  If `FakeRepoStorage` needs a `writeAtomic` call-recording capability (it currently
  no-ops), extend it there rather than duplicating a new fake.
- Assert dirty-indicator *state*, not literal visual styling — e.g. check for a
  `Key`, an icon's presence/absence, or a semantic label, matching the pattern
  already used in `widget_test.dart` (`find.text(...)`).

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 1 · Story 1.4] — user story, ACs (FR7, FR11)
- [Source: prd.md#FR7] (raw-markdown editor, never WYSIWYG) and #FR11 (explicit save + save-on-background, dirty indicator, no autosave-per-keystroke)
- [Source: ARCHITECTURE-SPINE.md#AD-4] (atomic write), #AD-8 (total/never-throw), #AD-9 (per-slice purity), #AD-10 (editor owns its buffer), #AD-12 (slice boundaries)
- [Source: _bmad-output/implementation-artifacts/1-2-prove-a-safe-atomic-round-trip-headless-spike.md] (`read`/`writeAtomic` exact throw/never-throw contract this story depends on)
- [Source: _bmad-output/implementation-artifacts/1-3-resolve-project-configuration.md] (`_loreDir` availability and resolution timing)
- [Source: apps/mobile/lib/app/root_picker_page.dart] (navigation pattern to follow, not reuse directly)

## Dev Agent Record

### Agent Model Used

claude-sonnet-5 (Claude Sonnet 5)

### Debug Log References

- `flutter analyze` → No issues found (one lint fixed mid-implementation: `prefer_initializing_formals` on the extended `FakeRepoStorage` constructor).
- `flutter test` → **65 passing** (54 → +11: 7 editor tests + 4 picker tests).
- One real test bug caught and fixed during implementation: `writeCalls` was originally typed `List<MapEntry<String,String>>`, and an `expect(storage.writeCalls, [MapEntry(...)])` assertion failed even though the printed values were identical — `MapEntry` uses identity equality in Dart, not structural. Switched to a Dart record `(String path, String contents)`, which does support `==`/`orderedEquals`; tests then passed correctly. This was a test-infrastructure bug, not an app-code bug, but worth flagging since it could otherwise mask a real regression in a future story.
- **Post-implementation (Task 5):** the user tried the app on a real repo and hit a real usability bug: `flutter analyze` clean, `flutter test` → 70 passing after that fix.
- **After the spike removal (Task 6):** 70 → **63 passing** (7 spike tests deleted). *An earlier revision of this document left the count at 70 — that was stale and is corrected here.*
- **After the code review patches:** `flutter analyze` clean, `flutter test` → **70 passing** (63 → +7 new tests covering the malformed-file guard, dirty-reappears-after-save, save-failure snackbar, picker `_up()` at both a nested and a root start path, the full picker→editor loop, and `media/` hiding).

### Completion Notes List

- **Epic 1 is now complete end-to-end**: grant → pick a file inside `loreDir` → edit raw markdown (no WYSIWYG, no autosave-per-keystroke) → explicit or background atomic save. Fully CI-verified — no on-device gate for this story (unlike 1.1/1.2), since FR7/FR11's behaviors are all provable with widget tests against the `RepoStorage` port.
- **Race guard — initially wrong, corrected by review.** An explicit save and a background save funnel through one `_save()`. The first implementation used a bare `_saving` return-if-busy flag, which this story's code review correctly showed *converts a race into a dropped write* (backgrounding during an in-flight save silently no-ops). It now defers via a `_savePending` flag and re-runs after the in-flight write. The original Completion Notes claimed this flag was a proven proactive race fix; it was not, and that claim was wrong.
- **Save-on-background is intentionally best-effort** — documented in code and the story: Android can reclaim the process before the write completes. This is acceptable because `writeAtomic`'s atomicity (Story 1.2) means a killed write leaves the *old* content intact, never a partial file. No WorkManager/foreground-service/retry-queue was added — that would be scope creep beyond FR11.
- **`FakeRepoStorage` extended, not duplicated** — the story's Dev Notes explicitly asked for this. It's now a small in-memory multi-path filesystem (`dirEntries`, `fileContents`, `writeCalls`) instead of the single-level "root listing + always-empty-read" fake from Story 1.1. Verified this doesn't regress the existing ready-view widget test.
- **`LoreFilePickerPage` deliberately kept separate from `RootPickerPage`** — different concerns (device-root picking vs. in-repo file picking) per the story's explicit anti-pattern warning; no shared base class introduced.
- No new dependencies; plain Flutter `TextField`/`TextEditingController`/`WidgetsBindingObserver`.
- **Root-cause of the post-implementation bug**: the story's original design assumed `loreDir` is always a *subfolder* of the chosen repo root. That's true when the root is an outer project folder (containing `lore/`, `lore-story.json`, etc.), but breaks when the user reasonably points the root directly at their lore content folder — there's no nested `lore` subfolder inside itself. The fix (fallback to `''` when `loreDir` doesn't exist) makes the app work either way without requiring the user to understand this distinction.

### File List

**Created:**
- `apps/mobile/lib/app/lore_file_picker_page.dart`
- `apps/mobile/lib/app/editor_page.dart`
- `apps/mobile/test/app/editor_page_test.dart`
- `apps/mobile/test/app/lore_file_picker_page_test.dart`

- `apps/mobile/lib/app/browse_filter.dart` (browse-hiding policy; added by the code review, replacing the port-level helper)

**Modified:**
- `apps/mobile/lib/app/home_page.dart` (`_openFile` action + `loreDir`-exists fallback + `mounted` guard; `_openEntry`/`_openFileFrom`; tappable top-level entries in `_ReadyView`; browse filtering in `_refresh`; removed the round-trip spike trigger)
- `apps/mobile/lib/storage/repo_storage.dart` (no net change — an `isHiddenBrowseEntry` helper was added mid-story then moved to `app/browse_filter.dart` by the review)
- `apps/mobile/lib/app/root_picker_page.dart` (browse filtering)
- `apps/mobile/lib/storage/storage.dart` (dropped the `round_trip_spike` export)
- `apps/mobile/test/fakes.dart` (`FakeRepoStorage` extended: `dirEntries`, `fileContents`, `writeCalls`, `failWrites`; `read` now throws for an unseeded path instead of always returning `''`; `exists` reflects seeded dirs/files; `listDir` honours `dirEntries['']` for the root)
- `apps/mobile/test/widget_test.dart` (browse-filtering, top-level navigation, `loreDir`-fallback, full picker→editor loop, and `media/`-hiding tests; restored the `flutter/material.dart` import)

**Deleted:**
- `apps/mobile/lib/storage/round_trip_spike.dart` — the Story 1.2 "Run atomic round-trip" debug trigger, retired at the user's request once the on-device S1 check had passed. **Its U+FFFD write-back guard was load-bearing and has been re-established in `EditorPage`** (see Task 6 and Review Findings).
- `apps/mobile/test/storage/round_trip_spike_test.dart` — its 7 tests. No coverage of `writeAtomic`'s byte-exactness was lost: that lives in `test/storage/all_files_repo_storage_test.dart` and is untouched.

## Change Log

| Date | Change |
| --- | --- |
| 2026-07-20 | Implemented Story 1.4, completing Epic 1: added `LoreFilePickerPage` (in-repo file browser rooted at `loreDir`) and `EditorPage` (raw-text editor, dirty tracking, explicit + background atomic save via `RepoStorage.writeAtomic`, race-guarded), wired into the ready view via "Open a file". Extended `FakeRepoStorage` into a proper multi-path fake with write-call recording. Tests 54 → 65. analyze clean. Fully CI-verified, no on-device gate. Status → review. |
| 2026-07-20 | Post-implementation fix from real usage: hid Syncthing technical folders from every browsing surface; made the ready view's top-level entries genuinely navigable (tap a folder to descend, tap a file to open it) instead of a static display; fixed "Open a file" to fall back to the true repo root when the resolved `loreDir` doesn't exist under it (the case where the user points the root directly at their lore folder). Tests 65 → 70. analyze clean. |
| 2026-07-20 | **Removed the "Run atomic round-trip" debug feature** (user-requested): deleted `round_trip_spike.dart` + its 7 tests, the barrel export, and the button/handlers. It was a Story 1.2 debug trigger that had served its purpose once the on-device S1 check passed. Story 1.2 remains `done` — its byte-exactness coverage lives in `all_files_repo_storage_test.dart` and is untouched — but its in-app trigger no longer exists. Tests 70 → 63. |
| 2026-07-20 | Addressed code review (Sonnet 5 impl, reviewed by 3 parallel layers): 13 patch findings fixed. **Data loss:** re-established the U+FFFD guard the spike deletion had removed (malformed files can no longer be saved, and are flagged in-editor); dirty flag now recomputed after save instead of force-cleared (was losing keystrokes typed during a write); `_saving` now defers via `_savePending` instead of dropping the second save; `PopScope` saves-or-confirms on Back instead of silently discarding edits. **Correctness:** catch-alls on editor load/save; `mounted` guard after the `exists` await; `media/` skipping restored (the deletion's second casualty); browse filter narrowed from all-dot-prefix to an intentional list and moved from the pure port to `app/browse_filter.dart`; system Back now goes *up* a level in the picker. **Tests/docs:** +7 tests (malformed guard, dirty-reappears, save-failure, `_up()` × 2, full picker→editor loop, `media/` hiding); keyed/semantic dirty indicator; fixed the `dirEntries['']` fake trap; and corrected this document's stale test count, wrong File List entry, missing spike-removal record, and an inaccurate claim about threading a single storage instance. Tests 63 → **70**. analyze clean. 5 findings deferred. |
