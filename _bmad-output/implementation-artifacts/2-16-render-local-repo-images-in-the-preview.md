---
baseline_commit: cecb2dd721aab1b9799a34265e76973bc6d68fb9
---

# Story 2.16: Render local repo images in the preview

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As the author,
I want the images I embed (`![alt](media/…)`) to render in the read-only preview,
so that I can see a card/scene the way it actually reads, illustrations included.

## Context

Story 2.7 added the read-only markdown preview (FR10) but deliberately rendered `![alt](src)` images as **alt text / a placeholder only** — real image loading was split out to this story because it reaches into the `storage/` slice, and `RepoStorage` today has only a UTF-8 `read`. Story 2.13 then reused the same `MarkdownPreview` widget unchanged for the entity-card preview on the detail screen. Both `MarkdownPreview`'s own doc comment and both prior stories' Dev Notes name this story as the one that adds real loading — this is not new scope, it is the planned second half of Story 2.7's image handling.

This story does two things: (1) adds a **bytes read** to the `RepoStorage` port (+ the `all_files` adapter + the test fake) — the one piece of I/O `MarkdownPreview` needs and doesn't have; (2) extends `MarkdownPreview` to resolve a local-relative `src` against the open file's directory and load it, **degrading to today's alt-text placeholder** for every failure mode (missing, unreadable, non-image, oversized, or a network URL). Both existing call sites (`FileEditor`'s preview toggle, used by both `EditorPage` and `PairedEditorPage`; and `EntityDetailPage`'s card preview) pass the new params through — the widget is *extended*, not restructured.

## Acceptance Criteria

1. **(extends FR10 — local images load)** Given a `![alt](src)` with a **local relative** `src`, when the preview renders, then the image is resolved relative to the **open file's directory** (forward-slash normalized) and loads from the repo via `RepoStorage`, displaying in place of the alt-text placeholder.
2. **(AD-3/AD-9/NFR3 — port extension, adapter-only I/O)** Given the `RepoStorage` port, when image loading is added, then a **bytes read** — `Future<Uint8List> readBytes(String path)` — is added to the port and implemented **only** in `AllFilesRepoStorage`; no `dart:io` import appears anywhere else. The test fake (`FakeRepoStorage`) implements it too, so widget tests can seed image bytes without touching the filesystem.
3. **(AD-8/NFR7 — total, never crash)** Given a **missing, unreadable, non-image, oversized, or network (`http(s)://`)** image, when the preview renders, then it degrades to the alt text / a placeholder and **never crashes** — no exception reaches the widget tree, no error screen, the rest of the preview renders normally.
4. **(AC5-of-2.7 honored — extend, don't restructure)** Given `MarkdownPreview` from Story 2.7, when images are added, then its constructor gains **optional** `storage`/`filePath` params (existing bare `MarkdownPreview(text: ...)` call sites keep compiling and keep today's alt-text-only behavior) — the editor preview (`FileEditor`, Story 2.7) and the detail-card preview (`EntityDetailPage`, Story 2.13) call sites pass them through.

**Non-goals (explicitly out of scope):** network image fetching (never — offline-first, NFR4/NFR5); tap-to-zoom / full-screen image viewer; caching across preview rebuilds beyond avoiding a re-fetch storm on a single build (see Dev Notes); editing/inserting images (out of the toolbar's scope, unrelated to this story).

## Tasks / Subtasks

- [x] **Task 1: Add `readBytes` to `RepoStorage` + `AllFilesRepoStorage` + `FakeRepoStorage`** (AC: 2)
  - [x] 1.1 In `apps/mobile/lib/storage/repo_storage.dart`, add to the `RepoStorage` abstract interface: `Future<Uint8List> readBytes(String path);` with a doc comment mirroring `read()`'s shape — repo-relative path, throws `RepoStorageException` on missing file or I/O error. Unlike `read()`, there is **no** best-effort decode step (bytes are bytes; the caller decides what to do with them) — a missing/unreadable file still throws, exactly like `read()`'s not-found/I/O-error branch. Add `import 'dart:typed_data';` (pure Dart — no `dart:io`, keeps AD-9 intact).
  - [x] 1.2 In `apps/mobile/lib/storage/all_files_repo_storage.dart`, implement `readBytes` mirroring `read()`'s structure: `_toOsPath(_normalizeRepoPath(path))`, then `File(osPath).readAsBytes()` in a `try`/`on FileSystemException catch` that translates to `RepoStorageException(e.message, path, osErrorCode: e.osError?.errorCode)` — no UTF-8/BOM handling (that's `read()`-only).
  - [x] 1.3 In `apps/mobile/test/fakes.dart`, add a `Map<String, Uint8List> fileBytes` constructor param + field to `FakeRepoStorage`, and implement `readBytes` returning the seeded bytes or throwing `RepoStorageException('not found (fake)', path)` — same shape as the existing `read()` fake.
  - [x] 1.4 Tests in `apps/mobile/test/storage/all_files_repo_storage_test.dart`: `readBytes` round-trips exact bytes for a real written/known file (mirror the existing `read()` test's setup pattern in this file); throws `RepoStorageException` for a missing path.

- [x] **Task 2: Extend `MarkdownPreview` to resolve and load local images** (AC: 1, 3, 4)
  - [x] 2.1 In `apps/mobile/lib/app/markdown_preview.dart`, add `final RepoStorage? storage;` and `final String? filePath;` to `MarkdownPreview`'s constructor — both **optional/nullable**, default `null`. Thread them into `_MarkdownRenderer`'s constructor so `_image()` can use them.
  - [x] 2.2 Path resolution order in `_image()` (or a helper it calls), each branch falling through to today's alt-text placeholder — **no branch throws**:
    a. `src` is null/empty → placeholder.
    b. `src` matches `http://` or `https://` (case-insensitive) → placeholder; **never** call storage (no network image fetch — NFR4/NFR5, offline-first).
    c. `storage` or `filePath` is null → placeholder (this is the exact behavior `MarkdownPreview(text: ...)`-only callers get today — the existing "no file load" test in `markdown_preview_test.dart` is the regression guard for this branch).
    d. Otherwise, resolve: take the directory of `filePath` (strip the last `/`-segment — the same inline `lastIndexOf('/')` pattern already used in `lore_loader.dart`'s `_dirname`, `file_editor.dart`'s `_basename`, and `entity_detail_page.dart`'s sub-entry-path logic; don't introduce a new shared path-utility for one call site), normalize any backslashes in `src` to `/`, and join as `dir.isEmpty ? src : '$dir/$src'`. Do **not** attempt real `../`-upward resolution — `AllFilesRepoStorage._normalizeRepoPath` already neutralizes `..` segments by dropping them (documented there as the deliberate anti-escape behavior every `RepoStorage` caller lives with), so a `../`-escaping `src` resolves to a path that (almost always) doesn't exist and correctly falls into the "missing" placeholder branch below — this is expected, not a defect to work around in this story.
  - [x] 2.3 Load asynchronously without re-fetching on every rebuild: wrap the `Image.memory` path in a small stateful widget (e.g. `_RepoImage extends StatefulWidget`) that creates the `readBytes` future **once**, in `initState` (keyed by the resolved path), not inside `build`. While pending, render a small fixed-size placeholder (avoid layout jump); Flutter's `Image.memory` also needs the *whole* byte array up front (no streaming), so there is no partial-render state to handle.
  - [x] 2.4 On success: guard the byte length against a size cap **before** attempting to decode — a module-level `const _maxImageBytes = 15 * 1024 * 1024;` (15 MB; a generous sanity cap for phone-authored illustrations, not a product requirement — pick a reasonable value and name it clearly) — oversized bytes go straight to the placeholder, no `Image.memory` call. Otherwise call `Image.memory(bytes, errorBuilder: (context, error, stackTrace) => <the same alt-text placeholder>)` — the `errorBuilder` is what turns **non-image bytes** (a decode failure) into the placeholder instead of an exception reaching the widget tree; do not try to sniff the file extension/magic bytes yourselves, `Image.memory`'s own decoder is the source of truth for "is this a real image."
  - [x] 2.5 On any thrown error from `readBytes` (missing file, permission error, other I/O failure) → the same alt-text placeholder. Every failure path in this task converges on the **one** existing placeholder widget `_image()` already builds today — don't introduce a second placeholder look.

- [x] **Task 3: Wire `storage`/`filePath` through both call sites** (AC: 1, 4)
  - [x] 3.1 `apps/mobile/lib/app/file_editor.dart:303` — `MarkdownPreview(text: _controller.text)` → add `storage: widget.storage, filePath: widget.path` (both already exist as `FileEditor` fields; no new plumbing). This single change covers **both** `EditorPage` (single-file editor) and `PairedEditorPage` (RU/EN tabs, Story 2.8) — both construct `FileEditor` with their own `storage`/`path` per file already, and both route through this one `MarkdownPreview` call site.
  - [x] 3.2 `apps/mobile/lib/app/entity_detail_page.dart:221` — `MarkdownPreview(text: entry.text)` → add `storage: widget.storage, filePath: _repoPath(entry.id)`, reusing the existing `_repoPath` helper (line ~54) that already converts the loreDir-relative `entry.id` into the repo-relative path — the exact same conversion `_open(entry.id)` on the line above already performs for navigation.

- [x] **Task 4: Tests** (AC: 1–4)
  - [x] 4.1 `apps/mobile/test/app/markdown_preview_test.dart`: extend the `pumpPreview` helper (or add a sibling helper) to optionally accept `storage`/`filePath`. New cases: a local relative image with seeded `FakeRepoStorage.fileBytes` (use a small real, valid image fixture — e.g. a minimal 1×1 PNG byte literal) renders an `Image` widget; a missing file (unseeded path) degrades to the alt-text placeholder, no `Image` widget, no exception; non-image bytes (e.g. arbitrary/garbage bytes, or a plain-text file's bytes) degrade to the placeholder via `errorBuilder`, no exception; oversized bytes (a byte array larger than the cap) degrade to the placeholder without an `Image.memory` call being attempted; an `http://…`/`https://…` src degrades to the placeholder and never reaches `readBytes` (verifiable e.g. by seeding only unrelated paths and asserting no exception + no `Image` widget, or via a fake that flags if called with a URL-like key); a `../`-escaping src degrades to the placeholder, never throws (AD-3 neutralization). **Keep** the existing "an image renders as its alt text / placeholder (no file load)" test unchanged — it now doubles as the regression guard for the `storage`/`filePath == null` fallback branch (Task 2.2c).
  - [x] 4.2 `apps/mobile/test/storage/all_files_repo_storage_test.dart`: covered by Task 1.4.
  - [x] 4.3 One integration-style test per call site, proving the wiring (not just presence/absence — a real data-safety/wiring concern per [[testing-emphasis]]): in `editor_page_test.dart` (or via `FileEditor` if a dedicated test exists), open a file whose buffer references a seeded local image and assert the preview renders an `Image`; in `entity_detail_page_test.dart`, seed an entity card whose text references a seeded local image and assert the same. Both confirm `storage`/`filePath` actually reach `MarkdownPreview` end-to-end, not just that the widget accepts the params in isolation.

- [x] **Task 5: Hygiene gates** (AC: 1–4)
  - [x] 5.1 `flutter analyze` clean.
  - [x] 5.2 `flutter test` green — record the before/after pass count in Dev Agent Record.
  - [x] 5.3 Confirm no `lore/` model, loader, or JS-core/fixture changes: `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` empty (this story never touches the model contract).
  - [x] 5.4 Confirm `dart:io` still appears **only** in `all_files_repo_storage.dart` within `apps/mobile/lib/` (grep for `dart:io` — the new `readBytes` implementation must not leak it anywhere else, AD-3/AD-9/NFR3).

### Review Findings

- [x] [Review][Patch] `..`/`.` segments in a local image `src` are not resolved before reaching storage — a sub-entry (event/quest stage) referencing the entity's shared `media/` folder via `../media/x.png` (the documented pattern — ARCHITECTURE.md's own layout: "media/ # images referenced by the card/sub-entries") silently fails to load, indistinguishable from a genuinely missing file; no test exercises a multi-level (sub-entry) image reference, only the card's own directory-adjacent case [apps/mobile/lib/app/markdown_preview.dart:430 `_resolveImage`] — applied: `_resolveImage` now does genuine segment-based resolution (`..` pops the preceding directory segment) instead of relying on `RepoStorage`'s anti-escape-only normalization; regression test added for a two-level-deep sub-entry reaching the entity's shared `media/`
- [x] [Review][Patch] No size/fit constraint on a successfully loaded image — `Image.memory` renders at native resolution inside the inline text flow (`WidgetSpan`), so any real (non-degenerate) illustration can blow out the preview layout; every test fixture uses a 1×1 PNG, which hid this from the test suite [apps/mobile/lib/app/markdown_preview.dart:512 `_RepoImageState.build`] — applied: wrapped `Image.memory` in a `ConstrainedBox` (`_maxImageDisplaySize` = 280 logical px, `BoxFit.contain`); test asserts the constraint is applied
- [x] [Review][Patch] `readBytes` is called directly in `initState`/`didUpdateWidget` with no defensive wrapper — the `RepoStorage` interface signature doesn't structurally guarantee async-safety (only the two current implementations happen to be safely `async`), so a future implementation that throws synchronously would escape `FutureBuilder` and violate this story's own "never throw past this widget" invariant (AD-8) [apps/mobile/lib/app/markdown_preview.dart:497,507 `_RepoImageState.initState`/`didUpdateWidget`] — applied: both call sites now go through a `_readBytes()` helper wrapping the call in `Future.sync`, guaranteeing no synchronous throw escapes; regression test added with a storage stub whose `readBytes` throws synchronously
- [x] [Review][Patch] The `_maxImageBytes` doc comment overclaims what it protects against — `readBytes` already reads the entire file into memory before the size check runs in `build()`, so the cap only prevents the subsequent `Image.memory` decode, not the read's own memory spike [apps/mobile/lib/app/markdown_preview.dart:464-467 `_maxImageBytes`] — applied: reworded the comment to state precisely what it bounds (decode cost, not the read's memory spike) and pointed to deferred-work.md for the streaming-protection gap
- [x] [Review][Patch] The 1×1 test PNG byte literal is duplicated verbatim across three test files instead of one shared fixture — matches a duplication pattern Story 2.13's own review already flagged and fixed via an extracted helper [apps/mobile/test/app/markdown_preview_test.dart, apps/mobile/test/app/editor_page_test.dart, apps/mobile/test/app/entity_detail_page_test.dart] — applied: extracted to `apps/mobile/test/app/test_image_fixtures.dart`, all three files now import it
- [x] [Review][Defer] A leading-slash `src` (e.g. `/media/hero.png`) isn't distinguished as repo-root-relative — it collapses through path-joining into directory-relative treatment (only coincidentally correct for a card sitting directly in the entity root) [apps/mobile/lib/app/markdown_preview.dart:430 `_resolveImage`] — deferred, no documented project convention for what a leading slash should mean here; inventing one is a product-convention decision, not a code defect
- [x] [Review][Defer] `src` is not percent-decoded or stripped of query/fragment suffixes before path-joining — a percent-encoded or query-suffixed local reference (e.g. copy-pasted from a web export) would silently fail to resolve [apps/mobile/lib/app/markdown_preview.dart:430 `_resolveImage`] — deferred, narrow and safely degrades to the placeholder; not covered by any AC
- [x] [Review][Defer] The exact `_maxImageBytes` cap boundary (15 MB / 15 MB + 1) is untested since the constant isn't exported/injectable for tests; only a comfortably-clear 20 MB case is tested [apps/mobile/lib/app/markdown_preview.dart:467, apps/mobile/test/app/markdown_preview_test.dart] — deferred, low value given the cap is an explicit "sanity cap," not a strict contract
- [x] [Review][Dismiss] AC3's "unreadable" is not tested as distinct from "missing" (e.g. a directory-as-file typo, a permission error) — the code already handles both via the same generic `snapshot.hasError` catch-all already proven by the existing "missing file" test; the widget never branches on error type
- [x] [Review][Dismiss] `FakeRepoStorage.readBytes` only has one hardcoded failure message, so tests can't "prove" generic error handling — false premise, `_RepoImageState` branches solely on the boolean `snapshot.hasError`, never inspects the exception's content
- [x] [Review][Dismiss] No timeout/cancellation on the `readBytes` future (an indefinite hang would leave the loading placeholder forever) — unreachable via real local-file I/O; `AllFilesRepoStorage` never hangs indefinitely on device storage the way network I/O could
- [x] [Review][Dismiss] The oversized-bytes test allocates a real 20 MB `Uint8List` — deliberate and working as intended per the test's own comment; no measured cost to the suite (321 tests still run in ~4s)
- [x] [Review][Dismiss] `data:`/`file://`/`content://`/`blob:` URI schemes fall through to local-path treatment and safely degrade to the placeholder — this is exactly the required AD-8 behavior (never crash, never fetch); supporting these schemes was never in scope (only "local relative" and "http(s)" are named in the ACs)
- [x] [Review][Dismiss] Acceptance Auditor noted the "no file load" test's description string was reworded — cosmetic only, no behavioral or coverage change; Task 4.1's "keep unchanged" refers to behavior, not the verbatim string

## Dev Notes

### What changes, precisely

**File to MODIFY — `apps/mobile/lib/storage/repo_storage.dart`:**
- Add `Future<Uint8List> readBytes(String path);` to the `RepoStorage` interface, `import 'dart:typed_data';` at the top (pure Dart, keeps AD-9).

**File to MODIFY — `apps/mobile/lib/storage/all_files_repo_storage.dart`:**
- Add `readBytes` — the only new `dart:io` code this story introduces, and it belongs here (the one file permitted to import `dart:io`, per its own doc comment at the top of the file).

**File to MODIFY — `apps/mobile/lib/app/markdown_preview.dart`:**
- `MarkdownPreview` constructor gains optional `storage`/`filePath`. `_MarkdownRenderer` gains the same, threaded through to `_image()`. A new small async-loading widget (private to this file) replaces the always-placeholder `_image()` body for the "we have storage+filePath+a resolvable local src" case; every other case still returns exactly what `_image()` returns today.
- **Do not touch** the parse/build `try/catch` at the top of `MarkdownPreview.build()` — that guards *synchronous* parse/AST-walk failures (Story 2.7's AD-8 mechanism). Per-image async failures are a **separate** failure surface, handled entirely inside the new image-loading widget (each image fails independently; one bad image must never blank the whole preview).

**File to MODIFY — `apps/mobile/lib/app/file_editor.dart`:**
- Line 303's `MarkdownPreview(text: _controller.text)` gains `storage: widget.storage, filePath: widget.path`.

**File to MODIFY — `apps/mobile/lib/app/entity_detail_page.dart`:**
- Line 221's `MarkdownPreview(text: entry.text)` gains `storage: widget.storage, filePath: _repoPath(entry.id)`.

**File to MODIFY — `apps/mobile/test/fakes.dart`:**
- `FakeRepoStorage` gains `fileBytes` + `readBytes`.

**Not touched in this story:** `apps/mobile/lib/lore/**` (no model/loader/matcher change — this story is entirely `storage/` + `app/`), `lib/lore.js`, `test/fixtures/lore-model/**`, `apps/mobile/lib/app/editor_page.dart` and `paired_editor_page.dart` (they construct `FileEditor` with `storage`/`path` already — nothing to change there, Task 3.1's one edit covers both), `apps/mobile/lib/app/editor_toolbar.dart`, `apps/mobile/lib/lore/convention_matcher.dart` / `convention_styles.dart` (no new conventions — this is image loading, not markup recognition).

### Architecture constraints

- **AD-3 / NFR3** (all filesystem access through `RepoStorage`): `readBytes` is a port method like the other four; the domain/UI layer (`MarkdownPreview`) calls only the port, never `dart:io`. [ARCHITECTURE-SPINE.md#AD-3]
- **AD-9** (I/O isolated to adapter files): `readBytes`'s *implementation* lives only in `all_files_repo_storage.dart`. The port declaration itself (`repo_storage.dart`) stays pure — `Uint8List` is `dart:typed_data`, not `dart:io`, so declaring the method signature there doesn't violate purity. [#AD-9]
- **AD-8 / NFR7** (total, never throw): this story's whole risk surface is a *new* async I/O path inside a read-only preview. Every failure mode named in AC3 must converge on the placeholder, not an exception — this is the story's primary test-coverage target, more than the "happy path renders an image" case (which is comparatively low-risk — `Image.memory` + `errorBuilder` is a well-trodden Flutter pattern).
- **NFR4 / NFR5** (offline-first, no unconfigured network calls): the `http(s)://` guard is not a formatting nicety — the project's ADRs are explicit that the **only** sanctioned network calls are to a user-configured AI provider (Epic 4). An `<img src="https://...">` must never trigger a fetch. Check this *before* touching storage, not as a fallback after a failed local read.
- **AD-2 / contract untouched**: no loader/model/fixtures change. `readBytes` is a new **port** method, not a model-shape change — the golden fixtures (`test/fixtures/lore-model/`) are unaffected, `npm test` stays 4/4.
- **AD-10** (model rebuilt, not patched): irrelevant here — this story adds no new model field; `LoreEntry.relDir`/`.id` and `FileEditor.path` already carry everything needed to resolve an image's directory, no loader change required.

### Previous story intelligence

**Immediate previous story (2.15, done):** unrelated in subject matter (toolbar tokens + link-format unification) but reinforces two process points still true here: (a) the cross-model review layer needs the **complete** diff — 2.15's own retro noted a review pass was given an incomplete diff once ([[complete-diffs-for-review-subagents]]); (b) `flutter analyze`/`flutter test` + the `git status --porcelain` contract-gate command are the established hygiene ritual every story in this epic ends with — Task 5 here follows the same shape.

**Functional predecessors — the stories that actually built what this one extends:**
- **Story 2.7** (done) built `MarkdownPreview` *specifically* anticipating this story: its own Dev Notes say "Story 2.16 will add `storage`/`filePath` params for images — keep the widget structured so that's an additive change," and its "Not touched in this story" list explicitly names `repo_storage.dart`/`all_files_repo_storage.dart`/`test/fakes.dart` as *this* story's job. The parse/build `try/catch` and the `_image()` placeholder function are exactly where this story's changes land. Read `apps/mobile/lib/app/markdown_preview.dart` in full before editing — the file's own doc comment (lines 9–24) already names this story.
- **Story 2.13** (done) proved `MarkdownPreview` is reused **unchanged** by a second call site (`EntityDetailPage`) — this story is the second time the widget's public API grows (2.7 built it, 2.13 reused it as-is, 2.16 extends it). 2.13's review also fixed a gesture-swallowing bug (`AbsorbPointer` around `MarkdownPreview` in the card row) — irrelevant to this story's changes but worth knowing the card preview is tap-through-guarded; don't let a new `_RepoImage` widget accidentally intercept gestures either (it shouldn't — it's not adding any `GestureDetector`/`InkWell`).
- **`AllFilesRepoStorage.read()`** is the direct template for `readBytes` — same `_toOsPath`/`_normalizeRepoPath` calls, same `FileSystemException` → `RepoStorageException` translation, just without the UTF-8/BOM decode logic (bytes need none of that). Mirror its structure, don't reinvent path handling.

### Testing standards

- Prioritize the **degrade-to-placeholder** paths (AC3) — they're the actual risk (a new async I/O surface in a preview that must never crash) — over the happy-path render, per [[testing-emphasis]] (business-logic and data-safety guards earn tests; simple template/plumbing doesn't need exhaustive coverage).
- The wiring tests (Task 4.3) are justified because they prove `storage`/`filePath` actually reach `MarkdownPreview` end-to-end from both real call sites — a genuine regression risk (an editor param typo, a wrong `_repoPath` call) — not mere widget-presence assertions.
- Reuse `FakeRepoStorage` (extended with `fileBytes`) — no new fake type needed, consistent with every prior storage-touching story in this epic.

### Project Structure Notes

- No new files expected (the async image-loading widget can be a private class inside `markdown_preview.dart`, matching how `_MarkdownRenderer` is already private to that file).
- No new dependencies — `Image.memory` and `Uint8List` are Flutter/Dart SDK, no package needed for decoding common image formats (PNG/JPEG/GIF/WebP/BMP all supported natively by Flutter's image codecs).
- Variance from the spine's "`lore/` owns preview UI": as with 2.7/2.13, UI stays in `app/` (the documented, established split since Story 2.2) — `readBytes` is the only change that touches `storage/`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Story 2.16, lines 452–470]
- [Source: _bmad-output/implementation-artifacts/2-7-preview-rendered-markdown.md] — builds `MarkdownPreview`, explicitly defers image loading here, names the exact extension point (constructor gains `storage`/`filePath`)
- [Source: _bmad-output/implementation-artifacts/2-13-preview-the-entity-card-on-the-detail-screen.md] — the second `MarkdownPreview` call site this story must also wire; the `AbsorbPointer` gesture-guard precedent
- [Source: apps/mobile/lib/app/markdown_preview.dart] — full file: `MarkdownPreview`, `_MarkdownRenderer._image()` (the placeholder to extend), the outer `try/catch` (do not touch — different failure surface)
- [Source: apps/mobile/lib/storage/repo_storage.dart] — the port `readBytes` is added to; doc comments explain the AD-3/AD-9/NFR3 seam
- [Source: apps/mobile/lib/storage/all_files_repo_storage.dart] — `read()`'s structure is the template for `readBytes`; `_toOsPath`/`_normalizeRepoPath` (the `..`-neutralization this story's path-resolution relies on, not reimplements)
- [Source: apps/mobile/lib/app/file_editor.dart:303] — the editor-preview call site (covers `EditorPage` + `PairedEditorPage`)
- [Source: apps/mobile/lib/app/entity_detail_page.dart:54,221] — the detail-card call site + the existing `_repoPath` conversion to reuse
- [Source: apps/mobile/lib/lore/lore_model.dart] — `LoreEntry.id`/`.relDir` shape (context for why `_repoPath(entry.id)` is the right resolution, not a new field)
- [Source: apps/mobile/test/fakes.dart] — `FakeRepoStorage`, extended with `fileBytes`/`readBytes`
- [Source: _bmad-output/planning-artifacts/architecture/architecture-lore-and-story-2026-07-19/ARCHITECTURE-SPINE.md#AD-3, #AD-8, #AD-9] — the three ADRs this story's design is built around
- [Source: MOBILE.md §3.1, §6] — offline-first / no unconfigured network calls, the basis for the `http(s)://` guard
- [Source: _bmad-output/planning-artifacts/epics.md — NFR3, NFR4, NFR5, NFR7]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 5

### Debug Log References

- Baseline before work (branch tip `cecb2dd`): `flutter test` 311 passing (not 309 as Story 2.15's own notes said — confirmed empirically by stashing this story's changes and re-running; used the measured number rather than the stale figure), `flutter analyze` clean.
- One real bug caught by the test suite during Task 4: the "non-image bytes degrade to the placeholder" test initially asserted `find.byType(Image), findsNothing` — wrong. `Image.memory(bytes, errorBuilder: ...)` still mounts an `Image` widget even when the `errorBuilder` fallback is what's actually painted (the widget swaps its *internal* rendering, not itself). Fixed the assertion to check for the visible placeholder text instead of widget-type absence; this is a test-design correction only, no production code changed as a result.
- `flutter analyze` → **No issues found** (both mid-implementation, file-scoped, and the final full-project run).
- `flutter test` → **321 passing** (311 → +10: 2 `readBytes` storage tests, 6 new `MarkdownPreview` image-loading tests — load/missing/non-image/oversized/http(s)/`../`-containing — plus 2 end-to-end wiring tests, one per real call site).
- Contract gate: `git status --porcelain lib/lore.js test/fixtures/ scripts/ apps/mobile/lib/lore/lore_loader.dart apps/mobile/lib/lore/lore_model.dart` empty — no loader/model/contract touch.
- `dart:io` isolation: `grep -rn "^import 'dart:io'" lib/` returns exactly one hit, `lib/storage/all_files_repo_storage.dart` — confirmed no new `dart:io` leak (AD-3/AD-9/NFR3). (A broader text-grep for the string `dart:io` also matches several doc-comments that *mention* `dart:io` by name while explicitly declaring its absence — expected, not a violation.)
- No new dependencies: `Image.memory`, `Uint8List`, `FutureBuilder` are all Flutter/Dart SDK.

### Completion Notes List

- Added `Future<Uint8List> readBytes(String path)` to the `RepoStorage` port (`repo_storage.dart`), implemented only in `AllFilesRepoStorage` (mirrors `read()`'s `_toOsPath`/`_normalizeRepoPath`/`FileSystemException`→`RepoStorageException` structure, no UTF-8/BOM handling — bytes are opaque) and in the test fake (`FakeRepoStorage.fileBytes`/`readBytes`).
- Extended `MarkdownPreview` with optional `storage`/`filePath` (both nullable, default `null` — every existing bare `MarkdownPreview(text: ...)` call site, including the many test helpers, kept compiling unchanged). `_MarkdownRenderer._resolveImage()` implements the guard chain in order: null/empty src → placeholder; `http(s)://` src → placeholder, storage never touched (offline-first, NFR4/NFR5); no `storage`/`filePath` → placeholder (Story 2.7's original behavior, still the exact fallback the pre-existing "no file load" test now guards); otherwise join `dirname(filePath)` + normalized `src` and hand off to a new `_RepoImage` widget.
- `_RepoImage` (private `StatefulWidget`) loads bytes **once** (future cached in `initState`, only re-created in `didUpdateWidget` on an actual storage/path change — not on every rebuild), enforces a 15 MB sanity cap before attempting to decode (oversized bytes never reach `Image.memory`), and renders via `Image.memory(bytes, errorBuilder: ...)` — the `errorBuilder` is what turns non-image bytes into the placeholder instead of a decode exception. Every failure mode (missing/unreadable/oversized/non-image) converges on the **same** alt-text-with-icon placeholder `_image()` already built pre-story; `errorBuilder` doesn't fully remove the `Image` widget from the tree even on failure, which cost one test-assertion fix (see Debug Log) but doesn't affect the actual AC — the placeholder content is what's visually shown either way.
- Wired both real call sites: `file_editor.dart`'s single `MarkdownPreview` call (covers both `EditorPage` and `PairedEditorPage`, which both construct `FileEditor` with their own `storage`/`path` already) and `entity_detail_page.dart`'s card preview (reusing the existing `_repoPath(entry.id)` conversion).
- `../`-containing `src` is deliberately **not** specially handled in `MarkdownPreview` — it relies on `RepoStorage`'s own path normalization (already tested in `all_files_repo_storage_test.dart`) to neutralize traversal; in the widget-test suite (which uses `FakeRepoStorage`, a raw map lookup with no normalization), an unresolvable joined path simply misses the seed and degrades to "missing" exactly like any other absent file — confirmed via a dedicated test.
- No `lore/` model, loader, or JS-core/fixture changes; no new dependencies; `flutter analyze` clean; `flutter test` 311 → 321 (+10).

### File List

- MODIFIED: apps/mobile/lib/storage/repo_storage.dart
- MODIFIED: apps/mobile/lib/storage/all_files_repo_storage.dart
- MODIFIED: apps/mobile/lib/app/markdown_preview.dart
- MODIFIED: apps/mobile/lib/app/file_editor.dart
- MODIFIED: apps/mobile/lib/app/entity_detail_page.dart
- MODIFIED: apps/mobile/test/fakes.dart
- MODIFIED: apps/mobile/test/storage/all_files_repo_storage_test.dart
- MODIFIED: apps/mobile/test/app/markdown_preview_test.dart
- MODIFIED: apps/mobile/test/app/editor_page_test.dart
- MODIFIED: apps/mobile/test/app/entity_detail_page_test.dart
- MODIFIED: _bmad-output/implementation-artifacts/sprint-status.yaml
- NEW: apps/mobile/test/app/test_image_fixtures.dart
- MODIFIED: _bmad-output/implementation-artifacts/deferred-work.md

## Change Log

- 2026-08-05: Addressed code review findings — 5 patches applied. **High — `../` sub-entry image references silently broke**: `_resolveImage` now does genuine `.`/`..` segment resolution instead of relying on `RepoStorage`'s anti-escape-only normalization, fixing the documented (ARCHITECTURE.md) "media/ referenced by both the card and its sub-entries" pattern. **High — unconstrained image display size**: `Image.memory` now wrapped in a `ConstrainedBox` (280px cap, `BoxFit.contain`) so a real illustration can't blow out the inline preview. **Medium — `readBytes` call not defensively wrapped**: both call sites now go through `Future.sync`, guaranteeing no synchronous throw from a future `RepoStorage` implementation escapes `_RepoImage`. **Medium — inaccurate size-cap doc comment**: reworded to state precisely what it bounds. **Low — duplicated test fixture**: extracted to `test/app/test_image_fixtures.dart`. 3 items deferred to deferred-work.md (leading-slash paths, percent-encoded/query-suffixed src, exact cap-boundary testing); 6 dismissed (false premises, unreachable given real I/O, or explicitly out of scope). `flutter test` 321 → 323 (+2 regression tests); `flutter analyze` clean; contract gate clean.
- 2026-08-05: Implemented Story 2.16 — local repo images now load and render in the read-only markdown preview. Added `RepoStorage.readBytes` (port + `AllFilesRepoStorage` adapter + test fake); extended `MarkdownPreview` with optional `storage`/`filePath` to resolve a local-relative `src` against the open file's directory and load it via a new `_RepoImage` widget, degrading to the existing alt-text placeholder for every failure mode (missing, unreadable, non-image, oversized, or an `http(s)://` URL — never fetched). Wired both call sites (`FileEditor`, covering `EditorPage`+`PairedEditorPage`; `EntityDetailPage`'s card preview). No loader/model/contract change; no new dependencies. `flutter analyze` clean; `flutter test` 311 → 321 (+10).
